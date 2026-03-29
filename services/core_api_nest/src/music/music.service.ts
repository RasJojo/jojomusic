import { createHash } from 'node:crypto';
import { access } from 'node:fs/promises';
import { Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { XMLParser } from 'fast-xml-parser';
import {
  AlbumDetailsResponse,
  AlbumPayload,
  ArtistDetailsResponse,
  ArtistPayload,
  BROWSE_CATEGORIES,
  BrowseCategoryPayload,
  BrowseCategoryResponse,
  BrowseCategoryPayload as BrowsePayload,
  LyricsResponse,
  PodcastDetailsResponse,
  PodcastEpisodePayload,
  PodcastPayload,
  ResolvedStream,
  SearchResponse,
  TrackPayload,
  buildAlbumKey,
  buildArtistKey,
  buildTrackKey,
  makeTrackPayload,
  normalizeValue,
  generateId,
} from '../common/payloads';
import { fetchJson, fetchText } from '../common/http.util';
import { AppConfigService } from '../common/app-config.service';
import { RedisCacheService } from '../infra/redis-cache.service';
import { SearchIndexService } from '../infra/search-index.service';
import { PrismaService } from '../prisma/prisma.service';

type JsonObject = Record<string, any>;

const ITUNES_BASE = 'https://itunes.apple.com';
const LASTFM_BASE = 'https://ws.audioscrobbler.com/2.0/';
const MUSICBRAINZ_BASE = 'https://musicbrainz.org/ws/2';

const BROWSE_ARTWORK_QUERIES: Record<string, string> = {
  'new-releases': 'new music friday playlist cover',
  'pop-hits': 'pop hits playlist cover',
  'rap-hiphop': 'rap hip hop playlist cover',
  'afro-vibes': 'afrobeats playlist cover',
  'mada-vibes': 'music malagasy cover',
  'chill-mood': 'chill mix playlist cover',
  'workout-energy': 'workout playlist cover',
  'love-songs': 'love songs playlist cover',
  'podcasts-editorial': 'podcast microphone studio',
};

@Injectable()
export class MusicService {
  private readonly browseArtworkCache = new Map<string, string | null>();
  private readonly searchCache = new Map<string, { expiresAt: number; value: SearchResponse }>();
  private readonly thumbnailCache = new Map<
    string,
    { expiresAt: number; value: string | null }
  >();
  private readonly resolvedStreamCache = new Map<
    string,
    { expiresAt: number; value: ResolvedStream }
  >();
  private readonly xmlParser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '',
  });

  constructor(
    private readonly appConfig: AppConfigService,
    private readonly redisCache: RedisCacheService,
    private readonly searchIndex: SearchIndexService,
    private readonly prisma: PrismaService,
  ) {}

  async search(query: string, limit = 20): Promise<SearchResponse> {
    const normalizedQuery = query.trim();
    if (!normalizedQuery) {
      return {
        query: '',
        artists: [],
        tracks: [],
        albums: [],
        podcasts: [],
      };
    }

    const cacheKey = `${normalizedQuery.toLowerCase()}::${limit}`;
    const cached = this.searchCache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      const hydrated = await this.refreshManagedSearchResponse(cached.value);
      this.searchCache.set(cacheKey, {
        expiresAt: cached.expiresAt,
        value: hydrated,
      });
      return hydrated;
    }
    const redisCacheKey = `search:v3:${cacheKey}`;
    const sharedCached = await this.redisCache.getJson<SearchResponse>(redisCacheKey);
    if (sharedCached) {
      const hydrated = await this.refreshManagedSearchResponse(sharedCached);
      this.searchCache.set(cacheKey, {
        expiresAt: Date.now() + 5 * 60 * 1000,
        value: hydrated,
      });
      void this.primeAudioAssets(hydrated.tracks, 2);
      return hydrated;
    }
    const indexed = await this.searchIndex.search(normalizedQuery, limit);
    if (this.hasUsefulIndexedSearch(indexed, limit)) {
      this.searchCache.set(cacheKey, {
        expiresAt: Date.now() + 5 * 60 * 1000,
        value: indexed!,
      });
      await this.redisCache.setJson(redisCacheKey, indexed, 5 * 60);
      void this.primeAudioAssets(indexed!.tracks, 2);
      return indexed!;
    }

    const artistQueries = this.artistQueryVariants(normalizedQuery);
    const [tracks, lastfmArtistBatches, itunesArtistBatches, musicbrainzArtists, albums, mbAlbums, podcasts] =
      await Promise.all([
        this.safe(this.searchTracks(normalizedQuery, limit), []),
        Promise.all(
          artistQueries.map((candidate) =>
            this.safe(this.searchLastfmArtists(candidate, Math.min(limit, 5)), []),
          ),
        ),
        Promise.all(
          artistQueries.map((candidate) =>
            this.safe(this.searchItunesArtists(candidate, Math.min(limit, 5)), []),
          ),
        ),
        this.safe(this.searchMusicBrainzArtists(normalizedQuery, Math.min(limit, 6)), []),
        this.safe(this.searchAlbums(normalizedQuery, Math.min(limit, 8)), []),
        this.safe(this.searchMusicBrainzAlbums(normalizedQuery, Math.min(limit, 8)), []),
        this.safe(this.searchPodcasts(normalizedQuery, Math.min(limit, 6)), []),
      ]);

    let artists = this.dedupeArtists(
      [...lastfmArtistBatches.flat(), ...itunesArtistBatches.flat(), ...musicbrainzArtists].filter(
        (artist) => this.artistMatchesQuery(normalizedQuery, artist),
      ),
      Math.min(limit, 6),
    ).sort(
      (left, right) =>
        this.artistMatchScore(normalizedQuery, right) -
        this.artistMatchScore(normalizedQuery, left),
    );

    artists = await this.enrichArtistImages(artists);

    const bestArtist = this.findBestArtistMatch(normalizedQuery, artists);
    let resultTracks = this.dedupeTracks(tracks, limit);
    let resultAlbums = this.dedupeAlbums([...mbAlbums, ...albums], Math.min(limit, 10));

    if (
      bestArtist &&
      (resultTracks.length < Math.min(limit, 8) || resultAlbums.length < Math.min(limit, 6))
    ) {
      const [artistTracks, musicbrainzAlbums, itunesAlbums] = await Promise.all([
        this.safe(this.topTracksForArtist(bestArtist.name, Math.min(limit, 6)), []),
        this.safe(this.albumsForArtistMusicBrainz(bestArtist.name, Math.min(limit, 6)), []),
        this.safe(this.albumsForArtist(bestArtist.name, Math.min(limit, 6)), []),
      ]);
      resultTracks = this.dedupeTracks([...artistTracks, ...resultTracks], limit);
      const specificAlbums = this.dedupeAlbums([...musicbrainzAlbums, ...itunesAlbums], Math.min(limit, 10));
      if (specificAlbums.length > 0) {
        resultAlbums = specificAlbums;
      }
    }

    const artistLookup = new Map(artists.map((artist) => [artist.artist_key, artist]));
    resultTracks = await this.hydrateTrackVisuals(
      resultTracks,
      artistLookup,
      bestArtist?.image_url ?? null,
      Math.min(limit, 3),
    );
    artists = this.backfillArtistImagesFromTracks(artists, resultTracks);
    const [managedArtists, managedTracks, managedAlbums, managedPodcasts] = await Promise.all([
      this.attachManagedArtistImages(artists),
      this.attachManagedTrackVisuals(resultTracks),
      this.attachManagedAlbumArtwork(resultAlbums),
      this.attachManagedPodcastArtwork(podcasts),
    ]);

    const result = {
      query: normalizedQuery,
      artists: managedArtists,
      tracks: managedTracks,
      albums: managedAlbums,
      podcasts: managedPodcasts,
    };
    this.searchCache.set(cacheKey, {
      expiresAt: Date.now() + 5 * 60 * 1000,
      value: result,
    });
    await this.redisCache.setJson(redisCacheKey, result, 5 * 60);
    void this.searchIndex.indexSearchResponse(result);
    void this.primeAudioAssets(result.tracks, 3);
    return result;
  }

  async artistDetails(name: string): Promise<ArtistDetailsResponse> {
    const [info, musicbrainzInfo, lastfmTracks, itunesTracks, similarArtists, musicbrainzAlbums, itunesAlbums] =
      await Promise.all([
        this.safe(this.artistInfoLastfm(name), null),
        this.safe(this.artistInfoMusicBrainz(name), null),
        this.safe(this.topTracksLastfm(name, 10), []),
        this.safe(this.topTracksItunes(name, 10), []),
        this.safe(this.similarArtistsLastfm(name, 8), []),
        this.safe(this.albumsForArtistMusicBrainz(name, 24), []),
        this.safe(this.albumsForArtist(name, 24), []),
      ]);

    const artist =
      this.mergeArtist(info, musicbrainzInfo) ??
      this.findBestArtistMatch(name, await this.searchLastfmArtists(name, 3)) ??
      this.findBestArtistMatch(name, await this.searchMusicBrainzArtists(name, 3)) ?? {
        artist_key: buildArtistKey(name),
        name,
        provider: 'internal',
        image_url: null,
      };

    let topTracks = this.dedupeTracks([...lastfmTracks, ...itunesTracks], 12);
    const topAlbums = this.dedupeAlbums([...itunesAlbums, ...musicbrainzAlbums], 32)
      .sort((left, right) => {
        const leftTs = left.release_date ? new Date(left.release_date).getTime() : 0;
        const rightTs = right.release_date ? new Date(right.release_date).getTime() : 0;
        return rightTs - leftTs;
      })
      .slice(0, 20);

    let resolvedArtist = artist;
    if (!resolvedArtist.image_url && topTracks[0]) {
      const thumbnail =
        (await this.resolveThumbnail(`${topTracks[0].artist} - ${topTracks[0].title}`, 2500)) ??
        (await this.resolveThumbnail(`${resolvedArtist.name} official music`, 2500));
      if (thumbnail) {
        resolvedArtist = { ...resolvedArtist, image_url: thumbnail };
      } else if (topTracks[0].artwork_url) {
        resolvedArtist = { ...resolvedArtist, image_url: topTracks[0].artwork_url };
      }
    }

    topTracks = await this.hydrateTrackVisuals(
      topTracks,
      new Map([[resolvedArtist.artist_key, resolvedArtist]]),
      resolvedArtist.image_url ?? null,
      6,
    );
    const [managedArtist, managedTracks, managedAlbums, managedSimilar] = await Promise.all([
      this.attachManagedArtistImage(resolvedArtist),
      this.attachManagedTrackVisuals(topTracks),
      this.attachManagedAlbumArtwork(topAlbums),
      this.attachManagedArtistImages(this.dedupeArtists(similarArtists, 8)),
    ]);

    void this.primeAudioAssets(managedTracks, 6);

    return {
      artist: managedArtist,
      top_tracks: managedTracks,
      top_albums: managedAlbums,
      similar_artists: managedSimilar,
    };
  }

  async albumDetails(
    artist: string,
    title: string,
    externalId?: string,
  ): Promise<AlbumDetailsResponse> {
    const [musicbrainzAlbum, lastfmAlbum, itunesAlbum] = await Promise.all([
      this.albumDetailsMusicBrainz(artist, title),
      this.albumDetailsLastfm(artist, title),
      this.albumDetailsItunes(artist, title, externalId),
    ]);

    const album =
      this.dedupeAlbums(
        [musicbrainzAlbum, lastfmAlbum.album, itunesAlbum.album].filter(Boolean) as AlbumPayload[],
        1,
      )[0] ?? {
        album_key: buildAlbumKey(artist, title),
        title,
        artist,
        provider: 'internal',
      };

    const tracks = this.dedupeTracks(
      [...lastfmAlbum.tracks, ...itunesAlbum.tracks],
      20,
    );
    const [managedAlbum, managedTracks] = await Promise.all([
      this.attachManagedAlbumArtwork([
        {
          ...album,
          artwork_url: album.artwork_url ?? tracks[0]?.artwork_url ?? null,
          track_count: album.track_count ?? (tracks.length > 0 ? tracks.length : null),
        },
      ]).then((items) => items[0]!),
      this.attachManagedTrackVisuals(tracks),
    ]);
    void this.primeAudioAssets(managedTracks, 6);

    return {
      album: managedAlbum,
      tracks: managedTracks,
    };
  }

  async browseCategories(): Promise<BrowseCategoryPayload[]> {
    const missing = BROWSE_CATEGORIES.filter(
      (category) => !this.browseArtworkCache.get(category.category_id),
    );

    if (missing.length > 0) {
      const thumbnails = await Promise.all(
        missing.map((category) =>
          this.resolveThumbnail(
            BROWSE_ARTWORK_QUERIES[category.category_id] ?? category.search_seed,
            2500,
          ).catch(() => null),
        ),
      );
      const fallbacks = await Promise.all(
        missing.map((category) =>
          this.search(category.search_seed, 6)
            .then((result) => {
              return (
                result.tracks.find((track) => track.artwork_url)?.artwork_url ??
                result.albums.find((album) => album.artwork_url)?.artwork_url ??
                result.podcasts.find((podcast) => podcast.artwork_url)?.artwork_url ??
                result.artists.find((artist) => artist.image_url)?.image_url ??
                null
              );
            })
            .catch(() => null),
        ),
      );
      missing.forEach((category, index) => {
        this.browseArtworkCache.set(
          category.category_id,
          thumbnails[index] ?? fallbacks[index] ?? null,
        );
      });
    }

    return this.attachManagedBrowseArtwork(
      BROWSE_CATEGORIES.map((category) => ({
      ...category,
      artwork_url: this.browseArtworkCache.get(category.category_id) ?? null,
      })),
    );
  }

  async browseCategory(categoryId: string): Promise<BrowseCategoryResponse> {
    const category = (await this.browseCategories()).find(
      (item) => item.category_id === categoryId,
    );
    if (!category) {
      throw new NotFoundException('Browse category not found');
    }
    const search = await this.search(category.search_seed, 12);
    void this.primeAudioAssets(search.tracks, 4);
    return {
      category,
      tracks: search.tracks.slice(0, 12),
      artists: search.artists.slice(0, 8),
      albums: search.albums.slice(0, 8),
      podcasts: search.podcasts.slice(0, 6),
    };
  }

  async searchPodcasts(query: string, limit = 12): Promise<PodcastPayload[]> {
    const normalizedQuery = this.normalizeLyricsValue(query);
    const queries = this.dedupeNonEmpty([
      query,
      `${query} podcast`,
      query.replace(/\s+/g, ''),
      query.replace(/\bpodcast\b/gi, '').trim(),
    ]);
    const scored = new Map<string, { podcast: PodcastPayload; score: number }>();

    for (const candidateQuery of queries) {
      if (!candidateQuery) {
        continue;
      }
      const data = await this.itunesSearch({
        term: candidateQuery,
        entity: 'podcast',
        limit: Math.max(limit, 10),
      }).catch(() => ({ results: [] as JsonObject[] }));

      for (const item of data.results ?? []) {
        if (item.kind !== 'podcast') {
          continue;
        }
        const podcastId = `${item.collectionId ?? item.trackId ?? ''}`;
        if (!podcastId) {
          continue;
        }
        const podcast: PodcastPayload = {
          podcast_key: podcastId,
          title: item.collectionName ?? item.trackName ?? '',
          publisher: item.artistName ?? 'Podcast',
          description: item.description ?? null,
          artwork_url: this.upscaleArtwork(item.artworkUrl600 ?? item.artworkUrl100),
          feed_url: item.feedUrl ?? null,
          external_url: item.collectionViewUrl ?? item.trackViewUrl ?? null,
          episode_count: item.trackCount ?? null,
          release_date: this.parseDate(item.releaseDate),
        };
        const score = this.scorePodcastSearchResult(normalizedQuery, podcast);
        const current = scored.get(podcastId);
        if (!current || score > current.score) {
          scored.set(podcastId, { podcast, score });
        }
      }
    }

    const ranked = [...scored.values()]
      .sort((left, right) => {
        if (right.score != left.score) {
          return right.score - left.score;
        }
        const leftDate = left.podcast.release_date?.getTime() ?? 0;
        const rightDate = right.podcast.release_date?.getTime() ?? 0;
        return rightDate - leftDate;
      })
      .slice(0, limit)
      .map((item) => item.podcast);

    return this.attachManagedPodcastArtwork(ranked);
  }

  async podcastDetails(podcastKey: string): Promise<PodcastDetailsResponse> {
    const podcast = await this.lookupPodcast(podcastKey);
    if (!podcast) {
      throw new NotFoundException('Podcast not found');
    }
    const episodes = await this.podcastEpisodes(podcast, 16);
    const [managedPodcast, managedEpisodes] = await Promise.all([
      this.attachManagedPodcastArtwork([podcast]).then((items) => items[0]!),
      this.attachManagedEpisodeArtwork(episodes),
    ]);
    return { podcast: managedPodcast, episodes: managedEpisodes };
  }

  async lyrics(artist: string, title: string): Promise<LyricsResponse | null> {
    const genius = await this.fetchGeniusLyrics(artist, title).catch(() => null);
    if (genius) {
      return genius;
    }

    const tononkira = await this.fetchTononkiraLyrics(artist, title).catch(() => null);
    if (tononkira) {
      return tononkira;
    }

    const lrclib = await this.fetchLrclibLyrics(artist, title).catch(() => null);
    if (lrclib) {
      return lrclib;
    }

    return null;
  }

  async resolveTrack(payload: {
    track?: TrackPayload;
    query?: string;
    artist?: string;
    title?: string;
  }): Promise<ResolvedStream> {
    const query = payload.track
      ? `${payload.track.artist} - ${payload.track.title}`
      : payload.artist && payload.title
        ? `${payload.artist} - ${payload.title}`
      : payload.query?.trim();
    if (!query) {
      throw new NotFoundException('Missing query');
    }

    const cacheKey = this.resolvedStreamCacheKey(payload, query);
    const lookupKey = this.audioAssetLookupKey(cacheKey);
    const readyAsset = await this.findReadyAudioAssetByLookupKey(lookupKey);
    if (readyAsset) {
      return readyAsset;
    }

    void this.ensureAudioAssetQueued(payload, query, cacheKey);

    const cached = this.resolvedStreamCache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.value;
    }
    const redisCacheKey = `resolved:${cacheKey}`;
    const sharedCached = await this.redisCache.getJson<ResolvedStream>(redisCacheKey);
    if (sharedCached) {
      this.resolvedStreamCache.set(cacheKey, {
        expiresAt: Date.now() + 18 * 60 * 1000,
        value: sharedCached,
      });
      return sharedCached;
    }

    const response = await fetchJson<ResolvedStream>(
      `${this.appConfig.resolverApiUrl}/api/v1/resolve`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ query }),
      },
      this.appConfig.resolverTimeoutSeconds * 1000,
    ).catch((error) => {
      throw new ServiceUnavailableException(String(error));
    });

    this.resolvedStreamCache.set(cacheKey, {
      expiresAt: Date.now() + 18 * 60 * 1000,
      value: response,
    });
    await this.redisCache.setJson(redisCacheKey, response, 18 * 60);
    return response;
  }

  async getReadyAudioAssetByAssetKey(assetKey: string): Promise<{
    filePath: string;
    publicUrl: string;
    title: string;
    artist: string;
    thumbnailUrl: string | null;
    durationMs: number | null;
  } | null> {
    const asset = await this.prisma.audioAsset.findUnique({
      where: { assetKey },
    });
    if (!asset || asset.status !== 'READY' || !asset.filePath || !asset.publicPath) {
      return null;
    }
    try {
      await access(asset.filePath);
    } catch {
      return null;
    }
    const thumbnailUrl = await this.attachManagedImageMap([
      {
        entityType: 'track',
        entityKey: asset.trackKey,
        sourceUrl: asset.thumbnailUrl ?? null,
      },
    ]).then((managed) => managed.get(`track:${asset.trackKey}`) ?? asset.thumbnailUrl ?? null);
    return {
      filePath: asset.filePath,
      publicUrl: this.toPublicUrl(asset.publicPath),
      title: asset.title,
      artist: asset.artist,
      thumbnailUrl,
      durationMs: asset.durationMs ?? null,
    };
  }

  async getReadyImageAssetByAssetKey(assetKey: string): Promise<{
    filePath: string;
    publicUrl: string;
    contentType: string | null;
  } | null> {
    const asset = await this.prisma.imageAsset.findUnique({
      where: { assetKey },
    });
    if (!asset || asset.status !== 'READY' || !asset.filePath || !asset.publicPath) {
      return null;
    }
    try {
      await access(asset.filePath);
    } catch {
      return null;
    }
    return {
      filePath: asset.filePath,
      publicUrl: this.toPublicUrl(asset.publicPath),
      contentType: asset.contentType ?? null,
    };
  }

  async primeAudioAssets(tracks: TrackPayload[], limit = 3): Promise<void> {
    const unique = this.dedupeTracks(tracks, limit).slice(0, limit);
    await Promise.allSettled(
      unique.map((track) =>
        this.ensureAudioAssetQueued(
          { track },
          `${track.artist} - ${track.title}`,
          this.resolvedStreamCacheKey({ track }, `${track.artist} - ${track.title}`),
        ),
      ),
    );
  }

  async similarTracks(
    seedTrack: TrackPayload,
    excludeKeys: string[] = [],
    limit = 12,
  ): Promise<TrackPayload[]> {
    const excluded = new Set<string>([seedTrack.track_key, ...excludeKeys]);
    const similar = await this.similarTracksLastfm(seedTrack.artist, seedTrack.title, limit * 2);
    const artistTracks = await this.topTracksForArtist(seedTrack.artist, limit * 2);
    return this.dedupeTracks(
      [...similar, ...artistTracks].filter((track) => !excluded.has(track.track_key)),
      limit,
    );
  }

  async buildFeaturedPodcasts(limit = 6): Promise<PodcastPayload[]> {
    const seeds = [
      'podcast musique',
      'rap podcast',
      'interview artiste podcast',
      'comedy podcast',
      'business podcast',
      'society podcast',
    ];
    const result = new Map<string, PodcastPayload>();
    for (const seed of seeds) {
      const podcasts = await this.searchPodcasts(seed, 3).catch(() => []);
      for (const podcast of podcasts) {
        if (!result.has(podcast.podcast_key)) {
          result.set(podcast.podcast_key, podcast);
        }
        if (result.size >= limit) {
          return this.attachManagedPodcastArtwork([...result.values()]);
        }
      }
    }
    return this.attachManagedPodcastArtwork([...result.values()]);
  }

  async topTracksForArtist(artist: string, limit = 10): Promise<TrackPayload[]> {
    const [lastfm, itunes] = await Promise.all([
      this.topTracksLastfm(artist, limit),
      this.topTracksItunes(artist, limit),
    ]);
    return this.attachManagedTrackVisuals(this.dedupeTracks([...lastfm, ...itunes], limit));
  }

  async searchTracks(query: string, limit = 25): Promise<TrackPayload[]> {
    const data = await this.itunesSearch({ term: query, entity: 'song', limit });
    const tracks = new Map<string, TrackPayload>();
    for (const item of data.results ?? []) {
      if (!item.artistName || !item.trackName) {
        continue;
      }
      const track = makeTrackPayload({
        title: item.trackName,
        artist: item.artistName,
        album: item.collectionName ?? null,
        artwork_url: this.upscaleArtwork(item.artworkUrl100),
        duration_ms: item.trackTimeMillis ?? null,
        provider: 'itunes',
        external_id: item.trackId ? `${item.trackId}` : null,
        preview_url: item.previewUrl ?? null,
      });
      if (!tracks.has(track.track_key)) {
        tracks.set(track.track_key, track);
      }
    }
    return [...tracks.values()];
  }

  async topTracksItunes(artist: string, limit = 10): Promise<TrackPayload[]> {
    const tracks = await this.searchTracks(artist, limit * 2);
    return this.dedupeTracks(
      tracks.filter((track) => buildArtistKey(track.artist).includes(buildArtistKey(artist))),
      limit,
    );
  }

  async topTracksLastfm(artist: string, limit = 10): Promise<TrackPayload[]> {
    if (!this.appConfig.lastfmApiKey) {
      return [];
    }
    const payload = await this.lastfm('artist.gettoptracks', { artist, limit }).catch(() => null);
    const tracks = this.asList(payload?.toptracks?.track);
    return tracks
      .map((row) => {
        const title = `${row.name ?? ''}`.trim();
        const rowArtist = `${row.artist?.name ?? artist}`.trim();
        if (!title || !rowArtist) {
          return null;
        }
        return makeTrackPayload({
          title,
          artist: rowArtist,
          artwork_url: this.chooseLastfmImage(row.image),
          provider: 'lastfm',
          external_id: row.mbid || null,
        });
      })
      .filter(Boolean)
      .slice(0, limit) as TrackPayload[];
  }

  async similarTracksLastfm(artist: string, title: string, limit = 12): Promise<TrackPayload[]> {
    if (!this.appConfig.lastfmApiKey) {
      return [];
    }
    const payload = await this.lastfm('track.getsimilar', { artist, track: title, limit }).catch(
      () => null,
    );
    const tracks = this.asList(payload?.similartracks?.track);
    return tracks
      .map((row) => {
        const rowArtist = `${row.artist?.name ?? ''}`.trim();
        const rowTitle = `${row.name ?? ''}`.trim();
        if (!rowArtist || !rowTitle) {
          return null;
        }
        return makeTrackPayload({
          title: rowTitle,
          artist: rowArtist,
          artwork_url: this.chooseLastfmImage(row.image),
          provider: 'lastfm',
          external_id: row.mbid || null,
        });
      })
      .filter(Boolean)
      .slice(0, limit) as TrackPayload[];
  }

  async searchLastfmArtists(query: string, limit = 5): Promise<ArtistPayload[]> {
    if (!this.appConfig.lastfmApiKey) {
      return [];
    }
    const payload = await this.lastfm('artist.search', {
      artist: query,
      limit,
    }).catch(() => null);
    const artists = this.asList(payload?.results?.artistmatches?.artist);
    return artists
      .map((row) => {
        const name = `${row.name ?? ''}`.trim();
        if (!name) {
          return null;
        }
        return {
          artist_key: buildArtistKey(name),
          name,
          image_url: this.chooseLastfmImage(row.image),
          provider: 'lastfm',
          external_id: row.mbid || null,
          url: row.url || null,
          listeners: Number.isFinite(Number(row.listeners)) ? Number(row.listeners) : null,
          summary: null,
        } satisfies ArtistPayload;
      })
      .filter(Boolean)
      .slice(0, limit) as ArtistPayload[];
  }

  async searchItunesArtists(query: string, limit = 5): Promise<ArtistPayload[]> {
    const data = await this.itunesSearch({
      term: query,
      entity: 'musicArtist',
      attribute: 'artistTerm',
      limit,
    });
    const artists = new Map<string, ArtistPayload>();
    for (const item of data.results ?? []) {
      const name = `${item.artistName ?? ''}`.trim();
      if (!name) {
        continue;
      }
      const artist = {
        artist_key: buildArtistKey(name),
        name,
        image_url: null,
        provider: 'itunes',
        external_id: item.artistId ? `${item.artistId}` : null,
        url: item.artistLinkUrl ?? null,
        listeners: null,
        summary: null,
      } satisfies ArtistPayload;
      if (!artists.has(artist.artist_key)) {
        artists.set(artist.artist_key, artist);
      }
    }
    return [...artists.values()];
  }

  async searchMusicBrainzArtists(query: string, limit = 6): Promise<ArtistPayload[]> {
    const url = new URL(`${MUSICBRAINZ_BASE}/artist`);
    url.searchParams.set('query', query);
    url.searchParams.set('fmt', 'json');
    url.searchParams.set('limit', `${limit}`);
    const payload = await fetchJson<JsonObject>(
      url,
      { headers: { 'User-Agent': 'JojoMusic/1.0 (jojomusic@example.com)' } },
      6000,
    ).catch(() => null);
    const artists = this.asList(payload?.artists);
    return artists
      .map((row) => {
        const name = `${row.name ?? ''}`.trim();
        if (!name) {
          return null;
        }
        return {
          artist_key: buildArtistKey(name),
          name,
          image_url: null,
          provider: 'musicbrainz',
          external_id: row.id || null,
          url: row.disambiguation ? `https://musicbrainz.org/artist/${row.id}` : null,
          listeners: null,
          summary: null,
        } satisfies ArtistPayload;
      })
      .filter(Boolean) as ArtistPayload[];
  }

  async artistInfoLastfm(name: string): Promise<ArtistPayload | null> {
    if (!this.appConfig.lastfmApiKey) {
      return null;
    }
    const payload = await this.lastfm('artist.getinfo', { artist: name }).catch(() => null);
    const artist = payload?.artist;
    if (!artist?.name) {
      return null;
    }
    return {
      artist_key: buildArtistKey(artist.name),
      name: artist.name,
      image_url: this.chooseLastfmImage(artist.image),
      provider: 'lastfm',
      external_id: artist.mbid || null,
      url: artist.url || null,
      listeners: Number.isFinite(Number(artist.stats?.listeners))
        ? Number(artist.stats.listeners)
        : null,
      summary: this.stripLastfmSummary(artist.bio?.summary ?? null),
    };
  }

  async artistInfoMusicBrainz(name: string): Promise<ArtistPayload | null> {
    const artists = await this.searchMusicBrainzArtists(name, 1);
    return artists[0] ?? null;
  }

  async similarArtistsLastfm(name: string, limit = 8): Promise<ArtistPayload[]> {
    if (!this.appConfig.lastfmApiKey) {
      return [];
    }
    const payload = await this.lastfm('artist.getsimilar', { artist: name, limit }).catch(
      () => null,
    );
    const artists = this.asList(payload?.similarartists?.artist);
    return artists
      .map((artist) => {
        const artistName = `${artist.name ?? ''}`.trim();
        if (!artistName) {
          return null;
        }
        return {
          artist_key: buildArtistKey(artistName),
          name: artistName,
          image_url: this.chooseLastfmImage(artist.image),
          provider: 'lastfm',
          external_id: artist.mbid || null,
          url: artist.url || null,
          listeners: null,
          summary: null,
        } satisfies ArtistPayload;
      })
      .filter(Boolean)
      .slice(0, limit) as ArtistPayload[];
  }

  async searchAlbums(query: string, limit = 10): Promise<AlbumPayload[]> {
    const data = await this.itunesSearch({ term: query, entity: 'album', limit });
    const albums = new Map<string, AlbumPayload>();
    for (const item of data.results ?? []) {
      const artist = `${item.artistName ?? ''}`.trim();
      const title = `${item.collectionName ?? ''}`.trim();
      if (!artist || !title) {
        continue;
      }
      const album = {
        album_key: buildAlbumKey(artist, title),
        title,
        artist,
        artwork_url: this.upscaleArtwork(item.artworkUrl100),
        provider: 'itunes',
        external_id: item.collectionId ? `${item.collectionId}` : null,
        summary: null,
        release_date: this.parseDate(item.releaseDate),
        track_count: item.trackCount ?? null,
      } satisfies AlbumPayload;
      if (!albums.has(album.album_key)) {
        albums.set(album.album_key, album);
      }
    }
    return [...albums.values()];
  }

  async albumsForArtist(artist: string, limit = 8): Promise<AlbumPayload[]> {
    const exactArtist =
      this.findBestArtistMatch(artist, await this.searchItunesArtists(artist, 5)) ?? null;
    const payload = exactArtist?.external_id
      ? await fetchJson<JsonObject>(
          new URL(
            `${ITUNES_BASE}/lookup?id=${encodeURIComponent(exactArtist.external_id)}&entity=album`,
          ),
          undefined,
          8000,
        ).catch(() => ({ results: [] }))
      : await this.itunesSearch({
          term: artist,
          entity: 'album',
          attribute: 'artistTerm',
          limit: Math.max(limit * 4, 24),
        }).catch(() => ({ results: [] }));

    const albums: AlbumPayload[] = [];
    for (const item of this.asList(payload.results)) {
      if (item.wrapperType && item.wrapperType !== 'collection') {
        continue;
      }
      const rowArtist = `${item.artistName ?? ''}`.trim();
      const title = `${item.collectionName ?? ''}`.trim();
      if (!rowArtist || !title) {
        continue;
      }
      albums.push({
        album_key: buildAlbumKey(rowArtist, title),
        title,
        artist: rowArtist,
        artwork_url: this.upscaleArtwork(item.artworkUrl100),
        provider: 'itunes',
        external_id: item.collectionId ? `${item.collectionId}` : null,
        summary: null,
        release_date: this.parseDate(item.releaseDate),
        track_count: item.trackCount ?? null,
      });
    }
    return this.dedupeAlbums(
      albums.filter((album) => buildArtistKey(album.artist).includes(buildArtistKey(artist))),
      limit,
    );
  }

  async searchMusicBrainzAlbums(query: string, limit = 8): Promise<AlbumPayload[]> {
    const url = new URL(`${MUSICBRAINZ_BASE}/release-group`);
    url.searchParams.set('query', query);
    url.searchParams.set('fmt', 'json');
    url.searchParams.set('limit', `${limit}`);
    const payload = await fetchJson<JsonObject>(
      url,
      { headers: { 'User-Agent': 'JojoMusic/1.0 (jojomusic@example.com)' } },
      6000,
    ).catch(() => null);
    const albums = this.asList(payload?.['release-groups']);
    return albums
      .map((row) => {
        const title = `${row.title ?? ''}`.trim();
        const artist = `${row['artist-credit']?.[0]?.name ?? ''}`.trim();
        if (!title || !artist) {
          return null;
        }
        return {
          album_key: buildAlbumKey(artist, title),
          title,
          artist,
          artwork_url: null,
          provider: 'musicbrainz',
          external_id: row.id || null,
          summary: null,
          release_date: this.parsePartialDate(row['first-release-date']),
          track_count: null,
        } satisfies AlbumPayload;
      })
      .filter(Boolean) as AlbumPayload[];
  }

  async albumsForArtistMusicBrainz(artist: string, limit = 8): Promise<AlbumPayload[]> {
    const bestArtist =
      this.findBestArtistMatch(artist, await this.searchMusicBrainzArtists(artist, 5)) ??
      null;
    const url = new URL(`${MUSICBRAINZ_BASE}/release-group`);
    url.searchParams.set(
      'query',
      bestArtist?.external_id ? `arid:${bestArtist.external_id}` : `artist:${artist}`,
    );
    url.searchParams.set('fmt', 'json');
    url.searchParams.set('limit', `${Math.max(limit, 24)}`);
    const payload = await fetchJson<JsonObject>(
      url,
      { headers: { 'User-Agent': 'JojoMusic/1.0 (jojomusic@example.com)' } },
      6000,
    ).catch(() => null);
    const albums: AlbumPayload[] = [];
    for (const row of this.asList(payload?.['release-groups'])) {
      const title = `${row.title ?? ''}`.trim();
      const rowArtist = `${row['artist-credit']?.[0]?.name ?? artist}`.trim();
      if (!title || !rowArtist) {
        continue;
      }
      albums.push({
        album_key: buildAlbumKey(rowArtist, title),
        title,
        artist: rowArtist,
        artwork_url: null,
        provider: 'musicbrainz',
        external_id: row.id || null,
        summary: null,
        release_date: this.parsePartialDate(row['first-release-date']),
        track_count: null,
      });
    }
    return albums.sort((left, right) => {
        const leftTs = left.release_date ? new Date(left.release_date).getTime() : 0;
        const rightTs = right.release_date ? new Date(right.release_date).getTime() : 0;
        return rightTs - leftTs;
      });
  }

  async albumDetailsLastfm(
    artist: string,
    title: string,
  ): Promise<{ album: AlbumPayload | null; tracks: TrackPayload[] }> {
    if (!this.appConfig.lastfmApiKey) {
      return { album: null, tracks: [] };
    }
    const payload = await this.lastfm('album.getinfo', { artist, album: title }).catch(() => null);
    const album = payload?.album;
    if (!album?.name) {
      return { album: null, tracks: [] };
    }
    const tracks = this.asList(album.tracks?.track)
      .map((row) => {
        const rowTitle = `${row.name ?? ''}`.trim();
        if (!rowTitle) {
          return null;
        }
        return makeTrackPayload({
          title: rowTitle,
          artist,
          album: title,
          artwork_url: this.chooseLastfmImage(album.image),
          duration_ms: Number.isFinite(Number(row.duration)) ? Number(row.duration) * 1000 : null,
          provider: 'lastfm',
        });
      })
      .filter(Boolean) as TrackPayload[];

    return {
      album: {
        album_key: buildAlbumKey(artist, title),
        title,
        artist,
        artwork_url: this.chooseLastfmImage(album.image),
        provider: 'lastfm',
        external_id: album.mbid || null,
        summary: this.stripLastfmSummary(album.wiki?.summary ?? null),
        release_date: this.parsePartialDate(album.wiki?.published ?? album.releasedate ?? null),
        track_count: tracks.length > 0 ? tracks.length : null,
      },
      tracks,
    };
  }

  async albumDetailsItunes(
    artist: string,
    title: string,
    externalId?: string,
  ): Promise<{ album: AlbumPayload | null; tracks: TrackPayload[] }> {
    if (externalId) {
      const lookup = new URL(`${ITUNES_BASE}/lookup`);
      lookup.searchParams.set('id', externalId);
      lookup.searchParams.set('entity', 'song');
      const payload = await fetchJson<JsonObject>(lookup, undefined, 8000).catch(() => null);
      const results = this.asList(payload?.results);
      return this.mapItunesAlbumLookup(results, artist, title);
    }

    const data = await this.itunesSearch({ term: `${artist} ${title}`, entity: 'album', limit: 8 });
    const best = this.asList(data.results).find((item) => {
      const rowArtist = buildArtistKey(`${item.artistName ?? ''}`);
      const rowTitle = buildAlbumKey(`${item.artistName ?? ''}`, `${item.collectionName ?? ''}`);
      return rowArtist.includes(buildArtistKey(artist)) && rowTitle === buildAlbumKey(artist, title);
    });
    if (!best?.collectionId) {
      return { album: null, tracks: [] };
    }
    const lookup = new URL(`${ITUNES_BASE}/lookup`);
    lookup.searchParams.set('id', `${best.collectionId}`);
    lookup.searchParams.set('entity', 'song');
    const payload = await fetchJson<JsonObject>(lookup, undefined, 8000).catch(() => null);
    return this.mapItunesAlbumLookup(this.asList(payload?.results), artist, title);
  }

  async albumDetailsMusicBrainz(artist: string, title: string): Promise<AlbumPayload | null> {
    const albums = await this.searchMusicBrainzAlbums(`${artist} ${title}`, 6);
    return (
      albums.find((album) => album.album_key === buildAlbumKey(artist, title)) ??
      albums.find((album) => buildArtistKey(album.artist).includes(buildArtistKey(artist))) ??
      null
    );
  }

  async hydrateTrackVisuals(
    tracks: TrackPayload[],
    artistLookup = new Map<string, ArtistPayload>(),
    fallbackArtistImage: string | null = null,
    thumbnailLimit = 0,
  ): Promise<TrackPayload[]> {
    const assetArtwork = await this.readyAssetArtworkByTrackKey(tracks);
    const enriched = tracks.map((track) => {
      const artist = artistLookup.get(buildArtistKey(track.artist));
      return {
        ...track,
        artwork_url: track.artwork_url ?? assetArtwork.get(track.track_key) ?? null,
        artist_image_url:
          track.artist_image_url ?? artist?.image_url ?? fallbackArtistImage ?? null,
      };
    });

    const pending = enriched
      .map((track, index) => ({ track, index }))
      .filter(
        ({ track }, index) =>
          index < thumbnailLimit &&
          !track.artwork_url &&
          !track.artist_image_url,
      );
    const thumbnails = await Promise.all(
      pending.map(({ track }) =>
        this.resolveThumbnail(`${track.artist} - ${track.title}`, 2200).catch(() => null),
      ),
    );

    pending.forEach(({ track }, index) => {
      const thumbnail = thumbnails[index];
      const matchIndex = enriched.findIndex((item) => item.track_key === track.track_key);
      if (matchIndex >= 0 && thumbnail) {
        enriched[matchIndex] = { ...enriched[matchIndex], artwork_url: thumbnail };
      }
    });
    return enriched;
  }

  private async itunesSearch(params: Record<string, string | number>): Promise<JsonObject> {
    const url = new URL(`${ITUNES_BASE}/search`);
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, `${value}`));
    return fetchJson<JsonObject>(url, undefined, 8000);
  }

  private async lookupPodcast(podcastKey: string): Promise<PodcastPayload | null> {
    const lookup = new URL(`${ITUNES_BASE}/lookup`);
    lookup.searchParams.set('id', podcastKey);
    lookup.searchParams.set('entity', 'podcast');
    const payload = await fetchJson<JsonObject>(lookup, undefined, 8000).catch(() => null);
    const item = this.asList(payload?.results).find((row) => row.kind === 'podcast');
    if (!item) {
      return null;
    }
    return {
      podcast_key: `${item.collectionId ?? item.trackId}`,
      title: item.collectionName ?? item.trackName ?? '',
      publisher: item.artistName ?? 'Podcast',
      description: item.description ?? null,
      artwork_url: this.upscaleArtwork(item.artworkUrl600 ?? item.artworkUrl100),
      feed_url: item.feedUrl ?? null,
      external_url: item.collectionViewUrl ?? item.trackViewUrl ?? null,
      episode_count: item.trackCount ?? null,
      release_date: this.parseDate(item.releaseDate),
    };
  }

  private async podcastEpisodes(
    podcast: PodcastPayload,
    limit = 16,
  ): Promise<PodcastEpisodePayload[]> {
    if (!podcast.feed_url) {
      return [];
    }
    const xml = await fetchText(podcast.feed_url, undefined, 8000).catch(() => null);
    if (!xml) {
      return [];
    }
    const parsed = this.xmlParser.parse(xml);
    const channel = parsed?.rss?.channel ?? parsed?.feed;
    const rawItems = this.asList(channel?.item ?? channel?.entry);
    return rawItems.slice(0, limit).map((item, index) => {
      const enclosure = item.enclosure ?? {};
      const image = item['itunes:image']?.href ?? item.image?.url ?? podcast.artwork_url ?? null;
      return {
        episode_key: `${podcast.podcast_key}-${normalizeValue(item.guid ?? item.id ?? item.title ?? `${index}`)}`,
        podcast_title: podcast.title,
        title: item.title ?? `Episode ${index + 1}`,
        publisher: podcast.publisher,
        description: this.stripHtml(item['content:encoded'] ?? item.description ?? null),
        artwork_url: image,
        audio_url: enclosure.url ?? null,
        external_url: item.link?.href ?? item.link ?? null,
        duration_seconds: this.parseDuration(item['itunes:duration'] ?? null),
        published_at: this.parseDate(item.pubDate ?? item.published ?? item.updated),
      };
    });
  }

  private async lastfm(method: string, params: Record<string, string | number>) {
    const url = new URL(LASTFM_BASE);
    url.searchParams.set('method', method);
    url.searchParams.set('api_key', this.appConfig.lastfmApiKey);
    url.searchParams.set('format', 'json');
    Object.entries(params).forEach(([key, value]) => {
      url.searchParams.set(key, `${value}`);
    });
    return fetchJson<JsonObject>(url, undefined, 8000);
  }

  private async resolveThumbnail(query: string, timeoutMs = 3000): Promise<string | null> {
    const cacheKey = query.trim().toLowerCase();
    const cached = this.thumbnailCache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.value;
    }
    const redisCacheKey = `thumbnail:${cacheKey}`;
    const sharedCached = await this.redisCache.getJson<string | null>(redisCacheKey);
    if (sharedCached !== null) {
      this.thumbnailCache.set(cacheKey, {
        expiresAt: Date.now() + 30 * 60 * 1000,
        value: sharedCached,
      });
      return sharedCached;
    }
    const payload = await fetchJson<{ thumbnail_url?: string | null }>(
      `${this.appConfig.resolverApiUrl}/api/v1/resolve`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ query }),
      },
      timeoutMs,
    ).catch(() => null);
    const value = payload?.thumbnail_url ?? null;
    this.thumbnailCache.set(cacheKey, {
      expiresAt: Date.now() + 30 * 60 * 1000,
      value,
    });
    await this.redisCache.setJson(redisCacheKey, value, 30 * 60);
    return value;
  }

  private async readyAssetArtworkByTrackKey(
    tracks: TrackPayload[],
  ): Promise<Map<string, string>> {
    const trackKeys = [...new Set(tracks.map((track) => track.track_key).filter(Boolean))];
    if (trackKeys.length === 0) {
      return new Map();
    }

    const assets = await this.prisma.audioAsset.findMany({
      where: {
        trackKey: { in: trackKeys },
        status: 'READY',
        thumbnailUrl: { not: null },
      },
      orderBy: { updatedAt: 'desc' },
    });

    const map = new Map<string, string>();
    for (const asset of assets) {
      if (asset.thumbnailUrl && !map.has(asset.trackKey)) {
        map.set(asset.trackKey, asset.thumbnailUrl);
      }
    }
    return map;
  }

  async attachManagedTrackVisuals(tracks: TrackPayload[]): Promise<TrackPayload[]> {
    const trackArtwork = await this.attachManagedImageMap(
      tracks.map((track) => ({
        entityType: 'track',
        entityKey: track.track_key,
        sourceUrl: track.artwork_url ?? null,
      })),
    );
    const artistArtwork = await this.attachManagedImageMap(
      tracks.map((track) => ({
        entityType: 'artist',
        entityKey: buildArtistKey(track.artist),
        sourceUrl: track.artist_image_url ?? null,
      })),
    );
    return tracks.map((track) => ({
      ...track,
      artwork_url:
        trackArtwork.get(`track:${track.track_key}`) ?? track.artwork_url ?? null,
      artist_image_url:
        artistArtwork.get(`artist:${buildArtistKey(track.artist)}`) ??
        track.artist_image_url ??
        null,
    }));
  }

  async attachManagedArtistImage(artist: ArtistPayload): Promise<ArtistPayload> {
    const [managed] = await this.attachManagedArtistImages([artist]);
    return managed ?? artist;
  }

  async attachManagedArtistImages(artists: ArtistPayload[]): Promise<ArtistPayload[]> {
    const managed = await this.attachManagedImageMap(
      artists.map((artist) => ({
        entityType: 'artist',
        entityKey: artist.artist_key,
        sourceUrl: artist.image_url ?? null,
      })),
    );
    return artists.map((artist) => ({
      ...artist,
      image_url:
        managed.get(`artist:${artist.artist_key}`) ?? artist.image_url ?? null,
    }));
  }

  async attachManagedAlbumArtwork(albums: AlbumPayload[]): Promise<AlbumPayload[]> {
    const managed = await this.attachManagedImageMap(
      albums.map((album) => ({
        entityType: 'album',
        entityKey: album.album_key,
        sourceUrl: album.artwork_url ?? null,
      })),
    );
    return albums.map((album) => ({
      ...album,
      artwork_url:
        managed.get(`album:${album.album_key}`) ?? album.artwork_url ?? null,
    }));
  }

  async attachManagedPodcastArtwork(podcasts: PodcastPayload[]): Promise<PodcastPayload[]> {
    const managed = await this.attachManagedImageMap(
      podcasts.map((podcast) => ({
        entityType: 'podcast',
        entityKey: podcast.podcast_key,
        sourceUrl: podcast.artwork_url ?? null,
      })),
    );
    return podcasts.map((podcast) => ({
      ...podcast,
      artwork_url:
        managed.get(`podcast:${podcast.podcast_key}`) ?? podcast.artwork_url ?? null,
    }));
  }

  async attachManagedEpisodeArtwork(
    episodes: PodcastEpisodePayload[],
  ): Promise<PodcastEpisodePayload[]> {
    const managed = await this.attachManagedImageMap(
      episodes.map((episode) => ({
        entityType: 'episode',
        entityKey: episode.episode_key,
        sourceUrl: episode.artwork_url ?? null,
      })),
    );
    return episodes.map((episode) => ({
      ...episode,
      artwork_url:
        managed.get(`episode:${episode.episode_key}`) ?? episode.artwork_url ?? null,
    }));
  }

  async attachManagedBrowseArtwork(
    categories: BrowseCategoryPayload[],
  ): Promise<BrowseCategoryPayload[]> {
    const managed = await this.attachManagedImageMap(
      categories.map((category) => ({
        entityType: 'browse',
        entityKey: category.category_id,
        sourceUrl: category.artwork_url ?? null,
      })),
    );
    return categories.map((category) => ({
      ...category,
      artwork_url:
        managed.get(`browse:${category.category_id}`) ?? category.artwork_url ?? null,
    }));
  }

  private async attachManagedImageMap(
    requests: Array<{ entityType: string; entityKey: string; sourceUrl: string | null }>,
  ): Promise<Map<string, string>> {
    const entries = new Map<
      string,
      { entityType: string; entityKey: string; sourceUrl: string }
    >();
    for (const request of requests) {
      const sourceUrl = request.sourceUrl?.trim();
      if (!request.entityKey || !sourceUrl) {
        continue;
      }
      const compound = `${request.entityType}:${request.entityKey}`;
      if (!entries.has(compound)) {
        entries.set(compound, {
          entityType: request.entityType,
          entityKey: request.entityKey,
          sourceUrl,
        });
      }
    }
    if (entries.size === 0) {
      return new Map();
    }

    const values = [...entries.values()];
    const lookupKeys = values.map((entry) =>
      this.imageAssetLookupKey(entry.entityType, entry.entityKey),
    );
    const existing = await this.prisma.imageAsset.findMany({
      where: { lookupKey: { in: lookupKeys } },
    });
    const existingMap = new Map(existing.map((asset) => [asset.lookupKey, asset]));
    const managed = new Map<string, string>();
    const toQueue: typeof values = [];

    for (const entry of values) {
      const lookupKey = this.imageAssetLookupKey(entry.entityType, entry.entityKey);
      if (this.isManagedMediaUrl(entry.sourceUrl)) {
        managed.set(`${entry.entityType}:${entry.entityKey}`, entry.sourceUrl);
        continue;
      }
      const current = existingMap.get(lookupKey);
      if (current?.status === 'READY' && current.publicPath) {
        managed.set(
          `${entry.entityType}:${entry.entityKey}`,
          this.toPublicUrl(current.publicPath),
        );
        continue;
      }
      managed.set(`${entry.entityType}:${entry.entityKey}`, entry.sourceUrl);
      if (current?.sourceUrl !== entry.sourceUrl || !this.imageRecentlyQueued(current?.lastQueuedAt)) {
        toQueue.push(entry);
      }
    }

    await Promise.allSettled(
      toQueue.map((entry) =>
        this.ensureImageAssetQueued(entry.entityType, entry.entityKey, entry.sourceUrl),
      ),
    );
    return managed;
  }

  private async refreshManagedSearchResponse(
    response: SearchResponse,
  ): Promise<SearchResponse> {
    const [artists, tracks, albums, podcasts] = await Promise.all([
      this.attachManagedArtistImages(response.artists),
      this.attachManagedTrackVisuals(response.tracks),
      this.attachManagedAlbumArtwork(response.albums),
      this.attachManagedPodcastArtwork(response.podcasts),
    ]);
    return {
      ...response,
      artists,
      tracks,
      albums,
      podcasts,
    };
  }

  private async fetchLrclibLyrics(
    artist: string,
    title: string,
  ): Promise<LyricsResponse | null> {
    const url = new URL('/api/search', this.appConfig.lrclibBaseUrl);
    url.searchParams.set('track_name', title);
    url.searchParams.set('artist_name', artist);
    const payload = await fetchJson<JsonObject[]>(url, undefined, 6000).catch(() => []);
    const candidate = payload[0];
    if (!candidate) {
      return null;
    }
    return {
      artist,
      title,
      plain_lyrics: candidate.plainLyrics ?? null,
      synced_lyrics: candidate.syncedLyrics ?? null,
      provider: 'lrclib',
    };
  }

  private async fetchGeniusLyrics(
    artist: string,
    title: string,
  ): Promise<LyricsResponse | null> {
    if (!this.appConfig.geniusAccessToken) {
      return null;
    }
    const search = new URL('https://api.genius.com/search');
    search.searchParams.set('q', `${artist} ${title}`);
    const payload = await fetchJson<JsonObject>(
      search,
      {
        headers: { Authorization: `Bearer ${this.appConfig.geniusAccessToken}` },
      },
      6000,
    ).catch(() => null);
    const hit = this.asList(payload?.response?.hits).find((entry) =>
      this.normalizeLyricsValue(`${entry.result?.primary_artist?.name ?? ''}`).includes(
        this.normalizeLyricsValue(artist),
      ),
    );
    const pageUrl = hit?.result?.url as string | undefined;
    if (!pageUrl) {
      return null;
    }
    const html = await fetchText(pageUrl, undefined, 8000).catch(() => null);
    if (!html) {
      return null;
    }
    const match =
      html.match(/"lyricsData":\{"body":\{"html":"([^"]+)"/) ??
      html.match(/<div data-lyrics-container="true">([\s\S]*?)<\/div>/);
    if (!match?.[1]) {
      return null;
    }
    const plain = this.sanitizeGeniusLyrics(this.htmlToTextWithBreaks(match[1]));
    if (!plain) {
      return null;
    }
    return {
      artist,
      title,
      plain_lyrics: plain,
      synced_lyrics: null,
      provider: 'genius',
    };
  }

  private async fetchTononkiraLyrics(
    artist: string,
    title: string,
  ): Promise<LyricsResponse | null> {
    let bestPayload: {
      score: [number, number, number];
      value: LyricsResponse;
    } | null = null;

    for (const candidateUrl of this.tononkiraCandidateUrls(artist, title)) {
      const html = await fetchText(candidateUrl, undefined, 6000).catch(() => null);
      if (!html) {
        continue;
      }
      const payload = this.tononkiraPayloadFromHtml(html, artist, title);
      if (!payload) {
        continue;
      }
      if (!bestPayload || this.compareTononkiraScore(payload.score, bestPayload.score) > 0) {
        bestPayload = payload;
      }
      if (payload.score[0] === 1 && payload.score[1] >= 950 && payload.score[2] >= 950) {
        return payload.value;
      }
    }

    const discoveredUrls = new Set<string>();
    for (const [artistVariant, titleVariant] of this.lyricsQueryVariants(artist, title)) {
      const queryVariants = [
        { lohateny: titleVariant, mpihira: artistVariant },
        { lohateny: titleVariant },
        { lohateny: `${titleVariant} ${artistVariant}` },
        { lohateny: `${artistVariant} ${titleVariant}` },
        { mpihira: artistVariant },
      ];
      for (const params of queryVariants) {
        const url = new URL('https://tononkira.serasera.org/tononkira');
        for (const [key, value] of Object.entries(params)) {
          const normalized = value.trim();
          if (normalized) {
            url.searchParams.set(key, normalized);
          }
        }
        const html = await fetchText(url, undefined, 6000).catch(() => null);
        if (!html) {
          continue;
        }
        for (const candidateUrl of this.extractTononkiraSongUrls(html)) {
          discoveredUrls.add(candidateUrl);
        }
      }
    }

    if (!discoveredUrls.size) {
      for (const query of this.dedupeNonEmpty([
        title,
        `${title} ${artist}`,
        `${artist} ${title}`,
        `${artist} - ${title}`,
        artist,
      ])) {
        const url = new URL('https://tononkira.serasera.org/tononkira');
        url.searchParams.set('lohateny', query);
        const html = await fetchText(url, undefined, 6000).catch(() => null);
        if (!html) {
          continue;
        }
        for (const candidateUrl of this.extractTononkiraSongUrls(html)) {
          discoveredUrls.add(candidateUrl);
        }
      }
    }

    for (const candidateUrl of Array.from(discoveredUrls).slice(0, 12)) {
      const html = await fetchText(candidateUrl, undefined, 6000).catch(() => null);
      if (!html) {
        continue;
      }
      const payload = this.tononkiraPayloadFromHtml(html, artist, title);
      if (!payload) {
        continue;
      }
      if (!bestPayload || this.compareTononkiraScore(payload.score, bestPayload.score) > 0) {
        bestPayload = payload;
      }
    }

    return bestPayload?.value ?? null;
  }

  private mapItunesAlbumLookup(
    results: JsonObject[],
    artist: string,
    title: string,
  ): { album: AlbumPayload | null; tracks: TrackPayload[] } {
    const albumRow = results.find((item) => item.collectionType === 'Album' || item.wrapperType === 'collection');
    const trackRows = results.filter((item) => item.wrapperType === 'track' && item.kind === 'song');
    const tracks = trackRows.map((row) =>
      makeTrackPayload({
        title: row.trackName,
        artist: row.artistName,
        album: row.collectionName ?? title,
        artwork_url: this.upscaleArtwork(row.artworkUrl100 ?? albumRow?.artworkUrl100),
        duration_ms: row.trackTimeMillis ?? null,
        provider: 'itunes',
        external_id: row.trackId ? `${row.trackId}` : null,
        preview_url: row.previewUrl ?? null,
      }),
    );
    return {
      album: albumRow
        ? {
            album_key: buildAlbumKey(artist, title),
            title: albumRow.collectionName ?? title,
            artist: albumRow.artistName ?? artist,
            artwork_url: this.upscaleArtwork(albumRow.artworkUrl100),
            provider: 'itunes',
            external_id: albumRow.collectionId ? `${albumRow.collectionId}` : null,
            summary: null,
            release_date: this.parseDate(albumRow.releaseDate),
            track_count: trackRows.length,
          }
        : null,
      tracks,
    };
  }

  private resolvedStreamCacheKey(payload: { track?: TrackPayload; query?: string }, query: string): string {
    if (payload.track) {
      if (payload.track.external_id) {
        return `track:external:${payload.track.external_id}`;
      }
      const parts = [
        payload.track.provider ?? '',
        payload.track.artist ?? '',
        payload.track.title ?? '',
        payload.track.album ?? '',
        payload.track.track_key ?? '',
      ];
      return `track:${parts.map((value) => value.trim().toLowerCase()).join('||')}`;
    }
    return `query:${query.trim().toLowerCase()}`;
  }

  private audioAssetLookupKey(cacheKey: string): string {
    return createHash('sha1').update(cacheKey).digest('hex');
  }

  private audioAssetTrackKey(payload: { track?: TrackPayload }, query: string): string {
    if (payload.track?.track_key) {
      return payload.track.track_key;
    }
    const [artist = '', title = query] = query.split(/\s+-\s+/, 2);
    return buildTrackKey(artist || 'unknown', title || query);
  }

  private audioAssetTitle(payload: { track?: TrackPayload }, query: string): string {
    if (payload.track?.title) {
      return payload.track.title;
    }
    const [, title = query] = query.split(/\s+-\s+/, 2);
    return title || query;
  }

  private audioAssetArtist(payload: { track?: TrackPayload }, query: string): string {
    if (payload.track?.artist) {
      return payload.track.artist;
    }
    const [artist = 'Unknown Artist'] = query.split(/\s+-\s+/, 2);
    return artist || 'Unknown Artist';
  }

  private audioAssetKey(lookupKey: string): string {
    return lookupKey;
  }

  private imageAssetLookupKey(entityType: string, entityKey: string): string {
    return createHash('sha1').update(`image:${entityType}:${entityKey}`).digest('hex');
  }

  private imageAssetKey(lookupKey: string): string {
    return lookupKey;
  }

  private toPublicUrl(path: string): string {
    return `${this.appConfig.publicBaseUrl.replace(/\/+$/, '')}${path.startsWith('/') ? path : `/${path}`}`;
  }

  private isManagedMediaUrl(url: string | null | undefined): boolean {
    if (!url) {
      return false;
    }
    return (
      url.startsWith('/api/v1/media/') ||
      url.startsWith(`${this.appConfig.publicBaseUrl.replace(/\/+$/, '')}/api/v1/media/`)
    );
  }

  private imageRecentlyQueued(lastQueuedAt: Date | null | undefined): boolean {
    if (!lastQueuedAt) {
      return false;
    }
    return Date.now() - lastQueuedAt.getTime() < 10 * 60 * 1000;
  }

  private async findReadyAudioAssetByLookupKey(lookupKey: string): Promise<ResolvedStream | null> {
    const asset = await this.prisma.audioAsset.findUnique({
      where: { lookupKey },
    });
    if (!asset || asset.status !== 'READY' || !asset.filePath || !asset.publicPath) {
      return null;
    }
    try {
      await access(asset.filePath);
    } catch {
      return null;
    }
    const thumbnailUrl = await this.attachManagedImageMap([
      {
        entityType: 'track',
        entityKey: asset.trackKey,
        sourceUrl: asset.thumbnailUrl ?? null,
      },
    ]).then((managed) => managed.get(`track:${asset.trackKey}`) ?? asset.thumbnailUrl ?? null);
    return {
      stream_url: this.toPublicUrl(asset.publicPath),
      webpage_url: asset.sourceWebpageUrl ?? null,
      thumbnail_url: thumbnailUrl,
      title: asset.title,
      artist: asset.artist,
      duration_ms: asset.durationMs ?? null,
      source: asset.source,
    };
  }

  private async ensureAudioAssetQueued(
    payload: { track?: TrackPayload; query?: string },
    query: string,
    cacheKey: string,
  ): Promise<void> {
    const lookupKey = this.audioAssetLookupKey(cacheKey);
    const assetKey = this.audioAssetKey(lookupKey);
    const existing = await this.prisma.audioAsset.findUnique({
      where: { lookupKey },
    });
    if (existing?.status === 'READY' && existing.publicPath && existing.filePath) {
      return;
    }

    const now = new Date();
    const lastQueuedAt = existing?.lastQueuedAt?.getTime() ?? 0;
    const recentlyQueued = lastQueuedAt > 0 && now.getTime() - lastQueuedAt < 10 * 60 * 1000;
    if (recentlyQueued && (existing?.status === 'QUEUED' || existing?.status === 'PROCESSING')) {
      return;
    }

    const title = this.audioAssetTitle(payload, query);
    const artist = this.audioAssetArtist(payload, query);
    const trackKey = this.audioAssetTrackKey(payload, query);
    const publicPath = `/api/v1/media/audio/${assetKey}`;

    const saved = await this.prisma.audioAsset.upsert({
      where: { lookupKey },
      create: {
        id: generateId(),
        lookupKey,
        trackKey,
        query,
        title,
        artist,
        assetKey,
        status: 'QUEUED',
        publicPath,
        lastQueuedAt: now,
      },
      update: {
        trackKey,
        query,
        title,
        artist,
        assetKey,
        publicPath,
        status: 'QUEUED',
        failureReason: null,
        lastQueuedAt: now,
      },
    });

    await this.redisCache.pushJsonToList(this.appConfig.mediaQueueKey, {
      lookup_key: saved.lookupKey,
      asset_key: saved.assetKey,
      track_key: saved.trackKey,
      query: saved.query,
      title: saved.title,
      artist: saved.artist,
    });
  }

  private async ensureImageAssetQueued(
    entityType: string,
    entityKey: string,
    sourceUrl: string,
  ): Promise<void> {
    if (!sourceUrl || this.isManagedMediaUrl(sourceUrl)) {
      return;
    }

    const lookupKey = this.imageAssetLookupKey(entityType, entityKey);
    const assetKey = this.imageAssetKey(lookupKey);
    const existing = await this.prisma.imageAsset.findUnique({
      where: { lookupKey },
    });

    if (existing?.status === 'READY' && existing.publicPath && existing.filePath) {
      return;
    }

    const now = new Date();
    if (
      existing?.sourceUrl === sourceUrl &&
      this.imageRecentlyQueued(existing.lastQueuedAt) &&
      (existing.status === 'QUEUED' || existing.status === 'PROCESSING')
    ) {
      return;
    }

    const publicPath = `/api/v1/media/image/${assetKey}`;
    const saved = await this.prisma.imageAsset.upsert({
      where: { lookupKey },
      create: {
        id: generateId(),
        lookupKey,
        entityType,
        entityKey,
        sourceUrl,
        assetKey,
        status: 'QUEUED',
        publicPath,
        lastQueuedAt: now,
      },
      update: {
        entityType,
        entityKey,
        sourceUrl,
        assetKey,
        publicPath,
        status: 'QUEUED',
        failureReason: null,
        lastQueuedAt: now,
      },
    });

    await this.redisCache.pushJsonToList(this.appConfig.imageQueueKey, {
      lookup_key: saved.lookupKey,
      asset_key: saved.assetKey,
      entity_type: saved.entityType,
      entity_key: saved.entityKey,
      source_url: saved.sourceUrl,
    });
  }

  private findBestArtistMatch(query: string, artists: ArtistPayload[]): ArtistPayload | null {
    const key = buildArtistKey(query);
    return (
      artists.find((artist) => artist.artist_key === key) ??
      artists.find((artist) => artist.artist_key.includes(key)) ??
      artists[0] ??
      null
    );
  }

  private artistMatchesQuery(query: string, artist: ArtistPayload): boolean {
    const key = buildArtistKey(query);
    return (
      artist.artist_key === key ||
      artist.artist_key.startsWith(key) ||
      artist.artist_key.includes(key) ||
      this.artistQueryVariants(query).some((variant) => artist.artist_key.includes(buildArtistKey(variant)))
    );
  }

  private artistMatchScore(query: string, artist: ArtistPayload): number {
    const key = buildArtistKey(query);
    if (artist.artist_key === key) {
      return 10_000 + (artist.listeners ?? 0);
    }
    if (artist.artist_key.startsWith(key)) {
      return 8_000 + (artist.listeners ?? 0);
    }
    if (artist.artist_key.includes(key)) {
      return 6_000 + (artist.listeners ?? 0);
    }
    return artist.listeners ?? 0;
  }

  private artistQueryVariants(query: string): string[] {
    const variants = new Set<string>();
    variants.add(query.trim());
    query
      .split(/\s+(?:feat\.?|ft\.?|with|x)\s+|,|&|\//i)
      .map((part) => part.trim())
      .filter((part) => part.length >= 2)
      .forEach((part) => variants.add(part));
    return [...variants];
  }

  private async enrichArtistImages(artists: ArtistPayload[]): Promise<ArtistPayload[]> {
    const missing = artists.filter((artist) => !artist.image_url).slice(0, 4);
    if (missing.length === 0) {
      return artists;
    }
    const thumbnails = await Promise.all(
      missing.map((artist) =>
        this.resolveThumbnail(`${artist.name} official music`, 2200).catch(() => null),
      ),
    );
    const map = new Map<string, string>();
    missing.forEach((artist, index) => {
      if (thumbnails[index]) {
        map.set(artist.artist_key, thumbnails[index] as string);
      }
    });
    return artists.map((artist) =>
      map.has(artist.artist_key) ? { ...artist, image_url: map.get(artist.artist_key) ?? null } : artist,
    );
  }

  private backfillArtistImagesFromTracks(
    artists: ArtistPayload[],
    tracks: TrackPayload[],
  ): ArtistPayload[] {
    const byArtist = new Map<string, string>();
    for (const track of tracks) {
      const visual = track.artist_image_url ?? track.artwork_url ?? null;
      if (!visual) {
        continue;
      }
      const artistKey = buildArtistKey(track.artist);
      if (!byArtist.has(artistKey)) {
        byArtist.set(artistKey, visual);
      }
    }

    return artists.map((artist) =>
      artist.image_url
        ? artist
        : {
            ...artist,
            image_url: byArtist.get(artist.artist_key) ?? null,
          },
    );
  }

  private dedupeTracks(tracks: TrackPayload[], limit: number): TrackPayload[] {
    const map = new Map<string, TrackPayload>();
    for (const track of tracks) {
      if (!map.has(track.track_key)) {
        map.set(track.track_key, track);
      } else {
        const existing = map.get(track.track_key)!;
        map.set(track.track_key, {
          ...existing,
          album: existing.album ?? track.album ?? null,
          artwork_url: existing.artwork_url ?? track.artwork_url ?? null,
          artist_image_url: existing.artist_image_url ?? track.artist_image_url ?? null,
          duration_ms: existing.duration_ms ?? track.duration_ms ?? null,
          preview_url: existing.preview_url ?? track.preview_url ?? null,
          external_id: existing.external_id ?? track.external_id ?? null,
          provider: existing.provider === 'lastfm' && track.provider !== 'lastfm' ? track.provider : existing.provider,
        });
      }
      if (map.size >= limit) {
        break;
      }
    }
    return [...map.values()].slice(0, limit);
  }

  private dedupeArtists(artists: ArtistPayload[], limit: number): ArtistPayload[] {
    const map = new Map<string, ArtistPayload>();
    for (const artist of artists) {
      if (!map.has(artist.artist_key)) {
        map.set(artist.artist_key, artist);
      } else {
        const existing = map.get(artist.artist_key)!;
        map.set(artist.artist_key, this.mergeArtist(existing, artist) ?? existing);
      }
    }
    return [...map.values()].slice(0, limit);
  }

  private dedupeAlbums(albums: AlbumPayload[], limit: number): AlbumPayload[] {
    const map = new Map<string, AlbumPayload>();
    for (const album of albums) {
      if (!map.has(album.album_key)) {
        map.set(album.album_key, album);
      } else {
        const existing = map.get(album.album_key)!;
        map.set(album.album_key, {
          ...existing,
          artwork_url: existing.artwork_url ?? album.artwork_url ?? null,
          external_id: existing.external_id ?? album.external_id ?? null,
          summary: existing.summary ?? album.summary ?? null,
          release_date: existing.release_date ?? album.release_date ?? null,
          track_count: existing.track_count ?? album.track_count ?? null,
          provider: existing.provider === 'lastfm' && album.provider !== 'lastfm' ? album.provider : existing.provider,
        });
      }
    }
    return [...map.values()].slice(0, limit);
  }

  private mergeArtist(left: ArtistPayload | null, right: ArtistPayload | null): ArtistPayload | null {
    if (!left && !right) {
      return null;
    }
    if (!left) {
      return right;
    }
    if (!right) {
      return left;
    }
    return {
      ...left,
      image_url: left.image_url ?? right.image_url ?? null,
      external_id: left.external_id ?? right.external_id ?? null,
      url: left.url ?? right.url ?? null,
      listeners: left.listeners ?? right.listeners ?? null,
      summary: left.summary ?? right.summary ?? null,
      provider: left.provider === 'lastfm' && right.provider !== 'lastfm' ? right.provider : left.provider,
    };
  }

  private asList(value: unknown): JsonObject[] {
    if (!value) {
      return [];
    }
    if (Array.isArray(value)) {
      return value.filter((item): item is JsonObject => !!item && typeof item === 'object');
    }
    if (typeof value === 'object') {
      return [value as JsonObject];
    }
    return [];
  }

  private upscaleArtwork(url: string | null | undefined): string | null {
    if (!url) {
      return null;
    }
    return url.replace(/\/\d+x\d+bb\.jpg/, '/1200x1200bb.jpg');
  }

  private chooseLastfmImage(images: unknown): string | null {
    const list = this.asList(images);
    const order = ['mega', 'extralarge', 'large', 'medium', 'small'];
    for (const preferred of order) {
      for (const image of list) {
        if (image.size === preferred && image['#text'] && !this.isPlaceholderImage(image['#text'])) {
          return image['#text'];
        }
      }
    }
    for (const image of list) {
      if (image['#text'] && !this.isPlaceholderImage(image['#text'])) {
        return image['#text'];
      }
    }
    return null;
  }

  private isPlaceholderImage(url: string | null | undefined): boolean {
    return !url || url.includes('2a96cbd8b46e442fc41c2b86b821562f');
  }

  private stripLastfmSummary(summary: string | null): string | null {
    if (!summary) {
      return null;
    }
    return this.stripHtml(
      summary
        .replace(
          /(?:Read more on Last\.fm\.?|User-contributed text is available under the Creative Commons By-SA License; additional terms may apply\.)\s*$/i,
          '',
        )
        .trim(),
    );
  }

  private stripHtml(value: string | null): string | null {
    if (!value) {
      return null;
    }
    const text = value
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .trim();
    return text || null;
  }

  private htmlToTextWithBreaks(value: string): string {
    return this.stripHtml(value) ?? '';
  }

  private sanitizeGeniusLyrics(value: string | null): string | null {
    if (!value) {
      return null;
    }
    return value
      .replace(/^\s*\d+\s+Contributors.*?Lyrics/, '')
      .replace(/You might also like/gi, '')
      .replace(/\d*Embed\s*$/g, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private sanitizeTononkiraLyrics(value: string | null): string | null {
    if (!value) {
      return null;
    }
    const lines = value
      .replace(/\r/g, '')
      .split('\n')
      .map((line) => line.replace(/\s+$/g, ''));
    const trimmedLines =
      lines.length >= 2 && /^-{4,}$/.test(lines[1]?.trim() ?? '') ? lines.slice(2) : lines;
    return trimmedLines.join('\n').replace(/\n{3,}/g, '\n\n').trim() || null;
  }

  private tononkiraSlug(value: string): string {
    return value
      .toLowerCase()
      .normalize('NFKD')
      .replace(/[^\x00-\x7F]/g, '')
      .replace(/\(feat[^)]*\)/gi, '')
      .replace(/\b(?:feat\.?|ft\.?|featuring|avec)\b.*$/gi, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  private normalizeLyricsValue(value: string): string {
    return value
      .toLowerCase()
      .normalize('NFKD')
      .replace(/[^\x00-\x7F]/g, '')
      .replace(/\(feat[^)]*\)/gi, '')
      .replace(/\b(?:feat\.?|ft\.?|featuring|avec)\b.*$/gi, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  }

  private lyricsQueryVariants(artist: string, title: string): Array<[string, string]> {
    const artists = this.dedupeNonEmpty([
      artist,
      ...artist.split(/\s*(?:,|&| x | feat\.?| ft\.?| featuring )\s*/i),
    ]);
    const titles = this.dedupeNonEmpty([
      title,
      title.replace(/\s*\([^)]*\)/g, '').trim(),
      title.replace(/\s*-\s*(?:live|remix|edit|version).*$/i, '').trim(),
      title.replace(/\s*(?:feat\.?|ft\.?|featuring)\s+.*$/i, '').trim(),
    ]);
    const variants: Array<[string, string]> = [];
    const seen = new Set<string>();
    for (const artistVariant of artists) {
      for (const titleVariant of titles) {
        const normalizedArtist = this.normalizeLyricsValue(artistVariant);
        const normalizedTitle = this.normalizeLyricsValue(titleVariant);
        if (!normalizedArtist || !normalizedTitle) {
          continue;
        }
        const key = `${normalizedArtist}::${normalizedTitle}`;
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);
        variants.push([artistVariant.trim(), titleVariant.trim()]);
      }
    }
    return variants.length ? variants : [[artist, title]];
  }

  private dedupeNonEmpty(values: string[]): string[] {
    const seen = new Set<string>();
    const deduped: string[] = [];
    for (const value of values) {
      const normalized = value.trim();
      if (!normalized) {
        continue;
      }
      const key = this.normalizeLyricsValue(normalized);
      if (!key || seen.has(key)) {
        continue;
      }
      seen.add(key);
      deduped.push(normalized);
    }
    return deduped;
  }

  private lyricsSimilarity(left: string, right: string): number {
    const normalizedLeft = this.normalizeLyricsValue(left);
    const normalizedRight = this.normalizeLyricsValue(right);
    if (!normalizedLeft || !normalizedRight) {
      return 0;
    }
    if (normalizedLeft === normalizedRight) {
      return 1000;
    }
    if (
      normalizedLeft.includes(normalizedRight) ||
      normalizedRight.includes(normalizedLeft)
    ) {
      const ratio =
        Math.min(normalizedLeft.length, normalizedRight.length) /
        Math.max(normalizedLeft.length, normalizedRight.length);
      return Math.round(ratio * 1000);
    }
    const leftTokens = normalizedLeft.split(' ');
    const rightTokens = normalizedRight.split(' ');
    const overlap = leftTokens.filter((token) => rightTokens.includes(token)).length;
    const denominator = Math.max(leftTokens.length, rightTokens.length, 1);
    return Math.round((overlap / denominator) * 1000);
  }

  private tononkiraCandidateUrls(artist: string, title: string): string[] {
    const urls: string[] = [];
    const seen = new Set<string>();
    const basePaths = [
      'https://tononkira.serasera.org/hira',
      'https://tononkira.serasera.org/mg/hira',
    ];
    for (const [artistVariant, titleVariant] of this.lyricsQueryVariants(artist, title)) {
      const artistSlug = this.tononkiraSlug(artistVariant);
      const titleSlug = this.tononkiraSlug(titleVariant);
      if (!artistSlug || !titleSlug) {
        continue;
      }
      const artistSlugs = /-\d+$/.test(artistSlug) ? [artistSlug] : [artistSlug, `${artistSlug}-1`];
      const titleSlugs = /-\d+$/.test(titleSlug) ? [titleSlug] : [titleSlug, `${titleSlug}-1`];
      for (const basePath of basePaths) {
        for (const artistSlugVariant of artistSlugs) {
          for (const titleSlugVariant of titleSlugs) {
            const url = `${basePath}/${artistSlugVariant}/${titleSlugVariant}`;
            if (seen.has(url)) {
              continue;
            }
            seen.add(url);
            urls.push(url);
          }
        }
      }
    }
    return urls;
  }

  private extractTononkiraSongUrls(html: string): string[] {
    const matches = html.matchAll(
      /href=["'](?<url>(?:https:\/\/tononkira\.serasera\.org)?\/(?:mg\/)?hira\/[^"'<\s?#]+)/gi,
    );
    const urls: string[] = [];
    const seen = new Set<string>();
    for (const match of matches) {
      const rawUrl = match.groups?.url;
      if (!rawUrl) {
        continue;
      }
      const resolved = new URL(rawUrl, 'https://tononkira.serasera.org').toString();
      if (seen.has(resolved) || resolved.endsWith('/ankafizo')) {
        continue;
      }
      seen.add(resolved);
      urls.push(resolved);
    }
    return urls;
  }

  private tononkiraPayloadFromHtml(
    html: string,
    artist: string,
    title: string,
  ): { score: [number, number, number]; value: LyricsResponse } | null {
    const pageTitle = html.match(/<title>\s*(.+?)\s*<\/title>/is)?.[1];
    if (pageTitle && pageTitle.includes('Lisitry ny hira')) {
      return null;
    }

    const ogMatch = html.match(
      /property="og:title"\s+content="(.+?)\s*-\s*(.+?)\s*-\s*Tononkira/is,
    );
    let candidateTitle = title;
    let candidateArtist = artist;
    if (ogMatch) {
      candidateTitle = this.stripHtml(ogMatch[1]) ?? title;
      candidateArtist = this.stripHtml(ogMatch[2]) ?? artist;
    }

    const lyricsMatch = html.match(
      /\(Nalaina tao amin'ny tononkira\.serasera\.org\)\s*<\/div>\s*(?<lyrics>.*?)\s*<br\s*\/?>\s*--------\s*<br\s*\/?>/is,
    );
    if (!lyricsMatch?.groups?.lyrics) {
      return null;
    }

    const plain = this.sanitizeTononkiraLyrics(
      this.htmlToTextWithBreaks(lyricsMatch.groups.lyrics),
    );
    if (!plain) {
      return null;
    }

    const normalizedArtist = this.normalizeLyricsValue(artist);
    const normalizedTitle = this.normalizeLyricsValue(title);
    const titleScore = this.lyricsSimilarity(normalizedTitle, candidateTitle);
    const artistScore = this.lyricsSimilarity(normalizedArtist, candidateArtist);
    const exactBonus = Number(
      this.normalizeLyricsValue(candidateTitle) === normalizedTitle &&
        this.normalizeLyricsValue(candidateArtist) === normalizedArtist,
    ) as 0 | 1;

    if (titleScore < 580 && artistScore < 580) {
      return null;
    }

    return {
      score: [exactBonus, titleScore, artistScore],
      value: {
        artist,
        title,
        plain_lyrics: plain,
        synced_lyrics: null,
        provider: 'tononkira',
      },
    };
  }

  private compareTononkiraScore(
    left: [number, number, number],
    right: [number, number, number],
  ): number {
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) {
        return left[index] - right[index];
      }
    }
    return 0;
  }

  private scorePodcastSearchResult(normalizedQuery: string, podcast: PodcastPayload): number {
    const normalizedTitle = this.normalizeLyricsValue(podcast.title);
    const normalizedPublisher = this.normalizeLyricsValue(podcast.publisher);
    const compactQuery = normalizedQuery.replace(/\s+/g, '');
    const compactTitle = normalizedTitle.replace(/\s+/g, '');
    let score = 0;

    if (normalizedTitle === normalizedQuery || compactTitle === compactQuery) {
      score += 4000;
    } else if (normalizedTitle.startsWith(normalizedQuery) || compactTitle.startsWith(compactQuery)) {
      score += 2800;
    } else if (normalizedTitle.includes(normalizedQuery) || compactTitle.includes(compactQuery)) {
      score += 2200;
    }

    if (normalizedPublisher.includes(normalizedQuery) || normalizedPublisher.replace(/\s+/g, '').includes(compactQuery)) {
      score += 900;
    }

    score += this.lyricsSimilarity(normalizedQuery, podcast.title);
    score += Math.min((podcast.episode_count ?? 0) * 2, 250);
    score += Math.min(
      Math.round((podcast.release_date?.getTime() ?? 0) / 1000 / 60 / 60 / 24 / 365),
      75,
    );

    return score;
  }

  private parseDate(value: string | null | undefined): Date | null {
    if (!value) {
      return null;
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private parsePartialDate(value: string | null | undefined): Date | null {
    if (!value) {
      return null;
    }
    if (/^\d{4}$/.test(value)) {
      return new Date(`${value}-01-01T00:00:00Z`);
    }
    if (/^\d{4}-\d{2}$/.test(value)) {
      return new Date(`${value}-01T00:00:00Z`);
    }
    return this.parseDate(value);
  }

  private parseDuration(value: string | number | null): number | null {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : null;
    }
    if (!value) {
      return null;
    }
    if (/^\d+$/.test(value)) {
      return Number(value);
    }
    const parts = value.split(':').map((part) => Number(part));
    if (parts.some((part) => !Number.isFinite(part))) {
      return null;
    }
    return parts.reduce((acc, part) => acc * 60 + part, 0);
  }

  private async safe<T>(promise: Promise<T>, fallback: T): Promise<T> {
    try {
      return await promise;
    } catch {
      return fallback;
    }
  }

  private hasUsefulIndexedSearch(
    response: SearchResponse | null,
    limit: number,
  ): response is SearchResponse {
    if (!response) {
      return false;
    }
    return (
      response.artists.length > 0 ||
      response.albums.length > 0 ||
      response.podcasts.length > 0 ||
      response.tracks.length >= Math.min(6, limit)
    );
  }
}
