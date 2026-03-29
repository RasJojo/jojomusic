import { Injectable, Logger } from '@nestjs/common';
import { MeiliSearch, Index } from 'meilisearch';
import type {
  AlbumPayload,
  ArtistPayload,
  PodcastPayload,
  SearchResponse,
  TrackPayload,
} from '../common/payloads';
import { AppConfigService } from '../common/app-config.service';

type CatalogDocument = {
  id: string;
  type: 'artist' | 'track' | 'album' | 'podcast';
  title: string;
  artist?: string | null;
  album?: string | null;
  payload: ArtistPayload | TrackPayload | AlbumPayload | PodcastPayload;
};

@Injectable()
export class SearchIndexService {
  private readonly logger = new Logger(SearchIndexService.name);
  private readonly client: MeiliSearch | null;
  private ensurePromise: Promise<Index<CatalogDocument>> | null = null;

  constructor(private readonly appConfig: AppConfigService) {
    this.client = this.appConfig.meilisearchUrl
      ? new MeiliSearch({
          host: this.appConfig.meilisearchUrl,
          apiKey: this.appConfig.meilisearchApiKey || undefined,
        })
      : null;
  }

  async search(query: string, limit: number): Promise<SearchResponse | null> {
    if (!this.client) {
      return null;
    }
    try {
      const index = await this.ensureIndex();
      const result = await index.search(query, {
        limit: Math.max(limit * 4, 24),
        attributesToRetrieve: ['type', 'payload'],
      });
      const artists: ArtistPayload[] = [];
      const tracks: TrackPayload[] = [];
      const albums: AlbumPayload[] = [];
      const podcasts: PodcastPayload[] = [];

      for (const hit of result.hits) {
        switch (hit.type) {
          case 'artist':
            if (artists.length < Math.min(limit, 6)) {
              artists.push(hit.payload as ArtistPayload);
            }
            break;
          case 'track':
            if (tracks.length < limit) {
              tracks.push(hit.payload as TrackPayload);
            }
            break;
          case 'album':
            if (albums.length < Math.min(limit, 10)) {
              albums.push(hit.payload as AlbumPayload);
            }
            break;
          case 'podcast':
            if (podcasts.length < Math.min(limit, 6)) {
              podcasts.push(hit.payload as PodcastPayload);
            }
            break;
        }
      }

      if (
        artists.length === 0 &&
        tracks.length === 0 &&
        albums.length === 0 &&
        podcasts.length === 0
      ) {
        return null;
      }

      return {
        query,
        artists,
        tracks,
        albums,
        podcasts,
      };
    } catch (error) {
      this.logger.warn(
        `Meilisearch query failed: ${error instanceof Error ? error.message : String(error)}`,
      );
      return null;
    }
  }

  async indexSearchResponse(response: SearchResponse): Promise<void> {
    if (!this.client) {
      return;
    }
    const documents: CatalogDocument[] = [
      ...response.artists.map((artist) => ({
        id: `artist:${artist.artist_key}`,
        type: 'artist' as const,
        title: artist.name,
        payload: artist,
      })),
      ...response.tracks.map((track) => ({
        id: `track:${track.track_key}`,
        type: 'track' as const,
        title: track.title,
        artist: track.artist,
        album: track.album ?? null,
        payload: track,
      })),
      ...response.albums.map((album) => ({
        id: `album:${album.album_key}`,
        type: 'album' as const,
        title: album.title,
        artist: album.artist,
        payload: album,
      })),
      ...response.podcasts.map((podcast) => ({
        id: `podcast:${podcast.podcast_key}`,
        type: 'podcast' as const,
        title: podcast.title,
        artist: podcast.publisher,
        payload: podcast,
      })),
    ];

    if (documents.length === 0) {
      return;
    }

    try {
      const index = await this.ensureIndex();
      await index.addDocuments(documents);
    } catch (error) {
      this.logger.warn(
        `Meilisearch indexing failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  private async ensureIndex(): Promise<Index<CatalogDocument>> {
    if (!this.client) {
      throw new Error('Meilisearch is not configured');
    }
    if (!this.ensurePromise) {
      this.ensurePromise = (async () => {
        const uid = 'catalog';
        const indexes = await this.client!.getIndexes();
        const existing = indexes.results.find((index) => index.uid === uid);
        if (!existing) {
          await this.client!.createIndex(uid, { primaryKey: 'id' });
        }
        const index = this.client!.index<CatalogDocument>(uid);

        await index.updateSearchableAttributes(['title', 'artist', 'album']);
        await index.updateFilterableAttributes(['type']);
        return index;
      })();
    }
    return this.ensurePromise;
  }
}
