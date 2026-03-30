import { Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma, User } from '@prisma/client';
import type { TrackPayload } from '../common/payloads';
import { PrismaService } from '../prisma/prisma.service';
import { generateId } from '../common/payloads';
import { MusicService } from '../music/music.service';
import {
  PlaylistCreateDto,
  PlaylistTrackCreateDto,
  PlaylistUpdateDto,
} from './dto/playlists.dto';

@Injectable()
export class PlaylistsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly musicService: MusicService,
  ) {}

  async list(user: User) {
    const playlists = await this.prisma.playlist.findMany({
      where: { userId: user.id },
      include: { tracks: { orderBy: { position: 'asc' } } },
      orderBy: { updatedAt: 'desc' },
    });
    const hydratedPlaylists = await Promise.all(
      playlists.map((playlist) => this.hydratePlaylistVisuals(playlist)),
    );
    void this.musicService.primeAudioAssets(
      hydratedPlaylists.flatMap((playlist) => this.trackPayloads(playlist.tracks)).slice(0, 10),
      8,
    );
    return hydratedPlaylists.map((playlist) => this.toPlaylistOut(playlist));
  }

  async create(user: User, payload: PlaylistCreateDto) {
    const playlist = await this.prisma.playlist.create({
      data: {
        id: generateId(),
        userId: user.id,
        name: payload.name.trim(),
        description: payload.description?.trim() ?? '',
        artworkUrl: payload.artwork_url ?? null,
      },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    return this.toPlaylistOut(await this.hydratePlaylistVisuals(playlist));
  }

  async update(user: User, playlistId: string, payload: PlaylistUpdateDto) {
    const playlist = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId: user.id },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    if (!playlist) {
      throw new NotFoundException('Playlist not found');
    }

    const data: Prisma.PlaylistUpdateInput = {
      updatedAt: new Date(),
    };
    if (payload.name != null) {
      data.name = payload.name.trim();
    }
    if (payload.description != null) {
      data.description = payload.description.trim();
    }
    if (payload.artwork_url != null) {
      data.artworkUrl = payload.artwork_url.trim() || null;
    }

    const updated = await this.prisma.playlist.update({
      where: { id: playlist.id },
      data,
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    const hydrated = await this.hydratePlaylistVisuals(updated);
    void this.musicService.primeAudioAssets(this.trackPayloads(hydrated.tracks), 6);
    return this.toPlaylistOut(hydrated);
  }

  async addTrack(user: User, playlistId: string, payload: PlaylistTrackCreateDto) {
    const playlist = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId: user.id },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    if (!playlist) {
      throw new NotFoundException('Playlist not found');
    }

    const existing = playlist.tracks.find((track) => track.trackKey === payload.track.track_key);
    if (!existing) {
      await this.prisma.playlistTrack.create({
        data: {
          id: generateId(),
          playlistId: playlist.id,
          trackKey: payload.track.track_key,
          position: playlist.tracks.length,
          trackPayload: payload.track as unknown as Prisma.InputJsonValue,
        },
      });
      await this.prisma.playlist.update({
        where: { id: playlist.id },
        data: {
          updatedAt: new Date(),
          artworkUrl: playlist.artworkUrl ?? payload.track.artwork_url ?? null,
        },
      });
    }

    const refreshed = await this.prisma.playlist.findUnique({
      where: { id: playlist.id },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    if (refreshed) {
      const hydrated = await this.hydratePlaylistVisuals(refreshed);
      void this.musicService.primeAudioAssets(this.trackPayloads(hydrated.tracks), 6);
      return this.toPlaylistOut(hydrated);
    }
    return this.toPlaylistOut(refreshed!);
  }

  async removeTrack(user: User, playlistId: string, trackKey: string) {
    const playlist = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId: user.id },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    if (!playlist) {
      throw new NotFoundException('Playlist not found');
    }
    await this.prisma.playlistTrack.deleteMany({
      where: { playlistId: playlist.id, trackKey },
    });
    const refreshed = await this.prisma.playlist.findUnique({
      where: { id: playlist.id },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    if (!refreshed) {
      throw new NotFoundException('Playlist not found');
    }

    await this.prisma.$transaction(
      refreshed.tracks.map((track, index) =>
        this.prisma.playlistTrack.update({
          where: { id: track.id },
          data: { position: index },
        }),
      ),
    );

    const artwork =
      refreshed.tracks.find((track) => (track.trackPayload as any)?.artwork_url)?.trackPayload as
        | { artwork_url?: string | null }
        | undefined;

    const updated = await this.prisma.playlist.update({
      where: { id: refreshed.id },
      data: {
        updatedAt: new Date(),
        artworkUrl: artwork?.artwork_url ?? null,
      },
      include: { tracks: { orderBy: { position: 'asc' } } },
    });
    const hydrated = await this.hydratePlaylistVisuals(updated);
    void this.musicService.primeAudioAssets(this.trackPayloads(hydrated.tracks), 6);

    return this.toPlaylistOut(hydrated);
  }

  async delete(user: User, playlistId: string) {
    const playlist = await this.prisma.playlist.findFirst({
      where: { id: playlistId, userId: user.id },
    });
    if (!playlist) {
      throw new NotFoundException('Playlist not found');
    }
    await this.prisma.playlist.delete({ where: { id: playlist.id } });
  }

  private trackPayloads(
    tracks: Array<{
      trackPayload: unknown;
    }>,
  ): TrackPayload[] {
    return tracks
      .map((track) => track.trackPayload as TrackPayload | null)
      .filter((track): track is TrackPayload => track != null);
  }

  private async hydratePlaylistVisuals<
    T extends {
      artworkUrl: string | null;
      tracks: Array<{
        id: string;
        trackKey: string;
        position: number;
        trackPayload: unknown;
        createdAt: Date;
      }>;
    },
  >(playlist: T): Promise<T> {
    const tracks = this.trackPayloads(playlist.tracks);
    if (tracks.length == 0) {
      return playlist;
    }

    const subset = tracks.slice(0, 4);
    const enrichedSubset = await Promise.all(
      subset.map((track) => this.enrichTrackVisualFallback(track)),
    );
    const hydratedSubset = await this.musicService.attachManagedTrackVisuals(enrichedSubset);
    const hydratedByKey = new Map(hydratedSubset.map((track) => [track.track_key, track]));
    const updatedTracks = playlist.tracks.map((track) => {
      const hydrated = hydratedByKey.get(track.trackKey);
      if (!hydrated) {
        return track;
      }
      return {
        ...track,
        trackPayload: hydrated,
      };
    });

    return {
      ...playlist,
      artworkUrl: playlist.artworkUrl ?? this.bestPlaylistArtwork(updatedTracks),
      tracks: updatedTracks,
    };
  }

  private bestPlaylistArtwork(
    tracks: Array<{
      trackPayload: unknown;
    }>,
  ): string | null {
    for (const track of this.trackPayloads(tracks)) {
      if (track.artwork_url && track.artwork_url.length > 0) {
        return track.artwork_url;
      }
      if (track.artist_image_url && track.artist_image_url.length > 0) {
        return track.artist_image_url;
      }
    }
    return null;
  }

  private async enrichTrackVisualFallback(track: TrackPayload): Promise<TrackPayload> {
    if (
      (track.artwork_url && track.artwork_url.length > 0) ||
      (track.artist_image_url && track.artist_image_url.length > 0)
    ) {
      return track;
    }

    const candidates = await this.musicService
      .searchTracks(`${track.artist} ${track.title}`, 4)
      .catch(() => [] as TrackPayload[]);
    if (candidates.length == 0) {
      return track;
    }

    for (const candidate of candidates) {
      if (
        this.normalizeForMatch(candidate.artist) == this.normalizeForMatch(track.artist) &&
        this.normalizeForMatch(candidate.title) == this.normalizeForMatch(track.title)
      ) {
        return {
          ...track,
          artwork_url: candidate.artwork_url ?? track.artwork_url ?? null,
          artist_image_url: candidate.artist_image_url ?? track.artist_image_url ?? null,
        };
      }
    }

    const candidate = candidates[0];
    return {
      ...track,
      artwork_url: candidate.artwork_url ?? track.artwork_url ?? null,
      artist_image_url: candidate.artist_image_url ?? track.artist_image_url ?? null,
    };
  }

  private normalizeForMatch(value: string | null | undefined): string {
    return `${value ?? ''}`.trim().toLowerCase();
  }

  private toPlaylistOut(playlist: {
    id: string;
    name: string;
    description: string;
    artworkUrl: string | null;
    createdAt: Date;
    updatedAt: Date;
    tracks: Array<{
      id: string;
      trackKey: string;
      position: number;
      trackPayload: unknown;
      createdAt: Date;
    }>;
  }) {
    return {
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      artwork_url: playlist.artworkUrl ?? this.bestPlaylistArtwork(playlist.tracks),
      created_at: playlist.createdAt,
      updated_at: playlist.updatedAt,
      tracks: playlist.tracks.map((track) => ({
        id: track.id,
        track_key: track.trackKey,
        position: track.position,
        track_payload: track.trackPayload as Record<string, unknown>,
        created_at: track.createdAt,
      })),
    };
  }
}
