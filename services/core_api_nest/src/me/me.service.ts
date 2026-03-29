import {
  ConflictException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import type {
  PlaybackEvent,
  Prisma,
  SavedPodcastEpisode,
  SavedPodcastShow,
  SavedTrack,
  SpotifyAccountLink,
  User,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AppConfigService } from '../common/app-config.service';
import {
  GeneratedPlaylistPayload,
  HomeResponse,
  PodcastPayload,
  SpotifyConnectResponse,
  SpotifyIntegrationStatus,
  TrackPayload,
  generateId,
  makeTrackPayload,
} from '../common/payloads';
import { MusicService } from '../music/music.service';
import { AuthService } from '../auth/auth.service';
import { PlaybackEventCreateDto } from './dto/me.dto';
import { RedisCacheService } from '../infra/redis-cache.service';

type SpotifyTokens = {
  accessToken: string;
  refreshToken: string | null;
  expiresAt: Date | null;
};

type SpotifyImportBundle = {
  profile: Record<string, any>;
  likedTracks: Array<{ track: TrackPayload; createdAt: Date | null }>;
  savedShows: Array<{ podcast: PodcastPayload; createdAt: Date | null }>;
  savedEpisodes: Array<{
    episode: Record<string, any>;
    createdAt: Date | null;
  }>;
  recentTracks: Array<{ track: TrackPayload; createdAt: Date | null }>;
};

@Injectable()
export class MeService {
  private readonly homeCache = new Map<string, { expiresAt: number; value: HomeResponse }>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly appConfig: AppConfigService,
    private readonly musicService: MusicService,
    private readonly authService: AuthService,
    private readonly redisCache: RedisCacheService,
  ) {}

  async getLikes(user: User): Promise<TrackPayload[]> {
    const rows = await this.prisma.savedTrack.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
    });
    const tracks = rows.map((row) => row.trackPayload as unknown as TrackPayload);
    void this.musicService.primeAudioAssets(tracks, 8);
    return tracks;
  }

  async likeTrack(user: User, track: TrackPayload): Promise<TrackPayload> {
    const existing = await this.prisma.savedTrack.findUnique({
      where: {
        userId_trackKey: {
          userId: user.id,
          trackKey: track.track_key,
        },
      },
    });
    if (!existing) {
      await this.prisma.savedTrack.create({
        data: {
          id: generateId(),
          userId: user.id,
          trackKey: track.track_key,
          trackPayload: track as unknown as Prisma.InputJsonValue,
        },
      });
      this.invalidateHomeCache(user.id);
    }
    return track;
  }

  async unlikeTrack(user: User, trackKey: string): Promise<void> {
    await this.prisma.savedTrack.deleteMany({
      where: { userId: user.id, trackKey },
    });
    this.invalidateHomeCache(user.id);
  }

  async getHistory(user: User) {
    const rows = await this.prisma.playbackEvent.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return rows.map((row) => ({
      id: row.id,
      track_key: row.trackKey,
      event_type: row.eventType,
      listened_ms: row.listenedMs,
      completion_ratio: row.completionRatio,
      track_payload: row.trackPayload as Record<string, unknown>,
      created_at: row.createdAt,
    }));
  }

  async addHistory(user: User, payload: PlaybackEventCreateDto) {
    const event = await this.prisma.playbackEvent.create({
      data: {
        id: generateId(),
        userId: user.id,
        trackKey: payload.track.track_key,
        eventType: payload.event_type,
        listenedMs: payload.listened_ms ?? 0,
        completionRatio: payload.completion_ratio ?? 0,
        trackPayload: payload.track as unknown as Prisma.InputJsonValue,
      },
    });
    this.invalidateHomeCache(user.id);
    return {
      id: event.id,
      track_key: event.trackKey,
      event_type: event.eventType,
      listened_ms: event.listenedMs,
      completion_ratio: event.completionRatio,
      track_payload: event.trackPayload as Record<string, unknown>,
      created_at: event.createdAt,
    };
  }

  async getFollowedPodcasts(user: User): Promise<PodcastPayload[]> {
    const rows = await this.prisma.savedPodcastShow.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
    });
    const podcasts = rows.map((row) => row.podcastPayload as unknown as PodcastPayload);
    return this.musicService.attachManagedPodcastArtwork(podcasts);
  }

  async followPodcast(user: User, podcast: PodcastPayload): Promise<PodcastPayload> {
    await this.prisma.savedPodcastShow.upsert({
      where: {
        userId_podcastKey: {
          userId: user.id,
          podcastKey: podcast.podcast_key,
        },
      },
      update: {
        podcastPayload: podcast as unknown as Prisma.InputJsonValue,
      },
      create: {
        id: generateId(),
        userId: user.id,
        podcastKey: podcast.podcast_key,
        podcastPayload: podcast as unknown as Prisma.InputJsonValue,
      },
    });
    return podcast;
  }

  async unfollowPodcast(user: User, podcastKey: string): Promise<void> {
    await this.prisma.savedPodcastShow.deleteMany({
      where: { userId: user.id, podcastKey },
    });
  }

  async recommendations(user: User): Promise<TrackPayload[]> {
    const tracks = await this.buildRecommendations(user, 20);
    void this.musicService.primeAudioAssets(tracks, 8);
    return tracks;
  }

  async home(user: User): Promise<HomeResponse> {
    const cached = this.homeCache.get(user.id);
    if (cached && cached.expiresAt > Date.now()) {
      const managed = await this.refreshManagedHomeResponse(cached.value);
      this.homeCache.set(user.id, {
        expiresAt: cached.expiresAt,
        value: managed,
      });
      return managed;
    }
    const redisCacheKey = `home:${user.id}`;
    const sharedCached = await this.redisCache.getJson<HomeResponse>(redisCacheKey);
    if (sharedCached) {
      const managed = await this.refreshManagedHomeResponse(sharedCached);
      this.homeCache.set(user.id, {
        expiresAt: Date.now() + 90_000,
        value: managed,
      });
      return managed;
    }

    const [likedRows, historyRows, recommendations, browseCategories, featuredPodcasts] =
      await Promise.all([
        this.prisma.savedTrack.findMany({
          where: { userId: user.id },
          orderBy: { createdAt: 'desc' },
          take: 12,
        }),
        this.prisma.playbackEvent.findMany({
          where: { userId: user.id },
          orderBy: { createdAt: 'desc' },
          take: 20,
        }),
        this.safeTimed(() => this.buildRecommendations(user, 16), [], 4000),
        this.safeTimed(() => this.musicService.browseCategories(), [], 3000),
        this.safeTimed(() => this.musicService.buildFeaturedPodcasts(6), [], 1200),
      ]);

    const likedTracks = likedRows.map((row) => row.trackPayload as unknown as TrackPayload);
    const recentlyPlayedMap = new Map<string, TrackPayload>();
    historyRows.forEach((row) => {
      if (!recentlyPlayedMap.has(row.trackKey)) {
        recentlyPlayedMap.set(row.trackKey, row.trackPayload as unknown as TrackPayload);
      }
    });
    let recentlyPlayed = [...recentlyPlayedMap.values()].slice(0, 12);

    const generatedPlaylists = await this.safeTimed(
      () => this.buildGeneratedPlaylists(user, recommendations),
      [],
      2500,
    );

    const artistLookup = new Map<string, never>();
    const [hydratedRecommendations, hydratedHistory, hydratedLikes] = await Promise.all([
      this.safeTimed(
        () => this.musicService.hydrateTrackVisuals(recommendations, artistLookup, null, 2),
        recommendations,
        1200,
      ),
      this.safeTimed(
        () => this.musicService.hydrateTrackVisuals(recentlyPlayed, artistLookup, null, 0),
        recentlyPlayed,
        800,
      ),
      this.safeTimed(
        () => this.musicService.hydrateTrackVisuals(likedTracks, artistLookup, null, 0),
        likedTracks,
        800,
      ),
    ]);

    const [
      managedRecommendations,
      managedHistory,
      managedLikes,
      managedGeneratedPlaylists,
      managedBrowseCategories,
      managedFeaturedPodcasts,
    ] = await Promise.all([
      this.safeTimed(
        () => this.musicService.attachManagedTrackVisuals(hydratedRecommendations),
        hydratedRecommendations,
        1200,
      ),
      this.safeTimed(
        () => this.musicService.attachManagedTrackVisuals(hydratedHistory),
        hydratedHistory,
        800,
      ),
      this.safeTimed(
        () => this.musicService.attachManagedTrackVisuals(hydratedLikes),
        hydratedLikes,
        800,
      ),
      this.safeTimed(
        () => this.attachManagedGeneratedPlaylists(generatedPlaylists),
        generatedPlaylists,
        1200,
      ),
      this.safeTimed(
        () => this.musicService.attachManagedBrowseArtwork(browseCategories),
        browseCategories,
        800,
      ),
      this.safeTimed(
        () => this.musicService.attachManagedPodcastArtwork(featuredPodcasts),
        featuredPodcasts,
        800,
      ),
    ]);

    recentlyPlayed = managedHistory;

    const response: HomeResponse = {
      recently_played: recentlyPlayed,
      liked_tracks: managedLikes,
      recommendations: managedRecommendations,
      generated_playlists: managedGeneratedPlaylists,
      browse_categories: managedBrowseCategories,
      featured_podcasts: managedFeaturedPodcasts,
    };
    this.homeCache.set(user.id, { expiresAt: Date.now() + 90_000, value: response });
    await this.redisCache.setJson(redisCacheKey, response, 90);
    void this.musicService.primeAudioAssets(
      [
        ...managedRecommendations.slice(0, 4),
        ...recentlyPlayed.slice(0, 2),
        ...managedGeneratedPlaylists.flatMap((playlist) => playlist.tracks.slice(0, 1)),
      ],
      6,
    );
    return response;
  }

  invalidateHomeCache(userId: string): void {
    this.homeCache.delete(userId);
    void this.redisCache.delete(`home:${userId}`);
  }

  getSpotifyConfigurationStatus(): Pick<SpotifyIntegrationStatus, 'configured' | 'configuration_hint'> {
    const missing: string[] = [];
    if (!this.appConfig.spotifyClientId) {
      missing.push('SPOTIFY_CLIENT_ID');
    }
    if (!this.appConfig.spotifyClientSecret) {
      missing.push('SPOTIFY_CLIENT_SECRET');
    }
    if (!this.appConfig.spotifyRedirectUri) {
      missing.push('SPOTIFY_REDIRECT_URI');
    }
    return {
      configured: missing.length === 0,
      configuration_hint:
        missing.length === 0 ? null : `Le serveur doit encore définir ${missing.join(', ')}.`,
    };
  }

  async spotifyStatus(user: User): Promise<SpotifyIntegrationStatus> {
    const config = this.getSpotifyConfigurationStatus();
    const link = await this.prisma.spotifyAccountLink.findUnique({
      where: { userId: user.id },
    });
    if (!link) {
      return {
        configured: config.configured,
        connected: false,
        configuration_hint: config.configuration_hint,
        liked_tracks_imported: 0,
        saved_shows_imported: 0,
        saved_episodes_imported: 0,
        recent_tracks_imported: 0,
        saved_shows: [],
      };
    }
    const shows = await this.prisma.savedPodcastShow.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: 6,
    });
    return {
      configured: config.configured,
      connected: true,
      configuration_hint: config.configuration_hint,
      spotify_user_id: link.spotifyUserId,
      display_name: link.displayName,
      email: link.email,
      avatar_url: link.avatarUrl,
      country: link.country,
      product: link.product,
      imported_at: link.importedAt,
      liked_tracks_imported: link.likedTracksImported,
      saved_shows_imported: link.savedShowsImported,
      saved_episodes_imported: link.savedEpisodesImported,
      recent_tracks_imported: link.recentTracksImported,
      saved_shows: shows.map((row) => row.podcastPayload as unknown as PodcastPayload),
    };
  }

  spotifyConnect(user: User): SpotifyConnectResponse {
    const config = this.getSpotifyConfigurationStatus();
    if (!config.configured) {
      throw new ServiceUnavailableException('Spotify integration is not configured');
    }
    const state = this.authService.createToken(
      { sub: user.id, kind: 'spotify_link' },
      15,
    );
    const params = new URLSearchParams({
      client_id: this.appConfig.spotifyClientId,
      response_type: 'code',
      redirect_uri: this.appConfig.spotifyRedirectUri,
      scope: this.appConfig.spotifyScopes,
      state,
      show_dialog: 'true',
    });
    return {
      authorize_url: `https://accounts.spotify.com/authorize?${params.toString()}`,
    };
  }

  async spotifySync(user: User): Promise<SpotifyIntegrationStatus> {
    const config = this.getSpotifyConfigurationStatus();
    if (!config.configured) {
      throw new ServiceUnavailableException('Spotify integration is not configured');
    }
    const link = await this.prisma.spotifyAccountLink.findUnique({
      where: { userId: user.id },
    });
    if (!link) {
      throw new NotFoundException('Spotify account not linked');
    }
    const tokens = await this.ensureSpotifyAccessToken(link);
    const bundle = await this.fetchSpotifyImportBundle(tokens.accessToken);
    await this.importSpotifyBundle(user, link, bundle, tokens);
    return this.spotifyStatus(user);
  }

  async spotifyDisconnect(user: User): Promise<void> {
    await this.prisma.spotifyAccountLink.deleteMany({ where: { userId: user.id } });
    await this.prisma.savedPodcastShow.deleteMany({ where: { userId: user.id } });
    await this.prisma.savedPodcastEpisode.deleteMany({ where: { userId: user.id } });
  }

  async spotifyCallback(
    code: string | undefined,
    state: string | undefined,
    error: string | undefined,
  ): Promise<string> {
    if (error) {
      return this.spotifyCallbackHtml(false, `Spotify a refusé la connexion: ${error}.`);
    }
    const config = this.getSpotifyConfigurationStatus();
    if (!config.configured) {
      return this.spotifyCallbackHtml(
        false,
        "Le backend JojoMusique n'est pas configuré pour Spotify.",
      );
    }
    if (!code || !state) {
      return this.spotifyCallbackHtml(false, 'Le callback Spotify est incomplet.');
    }

    let payload: { sub?: string; kind?: string };
    try {
      payload = this.authService.decodeToken<{ sub?: string; kind?: string }>(state);
    } catch {
      return this.spotifyCallbackHtml(false, 'Le state Spotify est invalide ou expiré.');
    }
    if (payload.kind !== 'spotify_link' || !payload.sub) {
      return this.spotifyCallbackHtml(
        false,
        'Le state Spotify ne correspond pas à une liaison valide.',
      );
    }
    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) {
      return this.spotifyCallbackHtml(
        false,
        "Le compte JojoMusique lié à cette importation est introuvable.",
      );
    }

    try {
      const tokens = await this.exchangeSpotifyCode(code);
      const bundle = await this.fetchSpotifyImportBundle(tokens.accessToken);
      const existingSameSpotify = await this.prisma.spotifyAccountLink.findFirst({
        where: {
          spotifyUserId: `${bundle.profile.id}`,
          userId: { not: user.id },
        },
      });
      if (existingSameSpotify) {
        return this.spotifyCallbackHtml(
          false,
          'Ce compte Spotify est déjà lié à un autre compte JojoMusique.',
        );
      }
      const link =
        (await this.prisma.spotifyAccountLink.findUnique({ where: { userId: user.id } })) ??
        ({
          id: generateId(),
          userId: user.id,
          spotifyUserId: `${bundle.profile.id}`,
          displayName: null,
          email: null,
          avatarUrl: null,
          country: null,
          product: null,
          accessToken: null,
          refreshToken: null,
          tokenExpiresAt: null,
          importedAt: null,
          likedTracksImported: 0,
          savedShowsImported: 0,
          savedEpisodesImported: 0,
          recentTracksImported: 0,
          createdAt: new Date(),
          updatedAt: new Date(),
        } as SpotifyAccountLink);

      await this.importSpotifyBundle(user, link, bundle, tokens);
      return this.spotifyCallbackHtml(
        true,
        `Import terminé: ${bundle.likedTracks.length} titres likés, ${bundle.savedShows.length} shows et ${bundle.savedEpisodes.length} épisodes sauvegardés.`,
      );
    } catch (errorObject) {
      return this.spotifyCallbackHtml(false, this.spotifyErrorMessage(errorObject));
    }
  }

  private async buildRecommendations(user: User, limit: number): Promise<TrackPayload[]> {
    const [likedRows, historyRows] = await Promise.all([
      this.prisma.savedTrack.findMany({
        where: { userId: user.id },
        orderBy: { createdAt: 'desc' },
        take: 64,
      }),
      this.prisma.playbackEvent.findMany({
        where: { userId: user.id },
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
    ]);

    const artistWeights = new Map<string, number>();
    likedRows.forEach((row) => {
      const track = row.trackPayload as unknown as TrackPayload;
      if (track.artist) {
        artistWeights.set(track.artist, (artistWeights.get(track.artist) ?? 0) + 4);
      }
    });
    historyRows.forEach((row) => {
      const track = row.trackPayload as unknown as TrackPayload;
      if (!track.artist) {
        return;
      }
      const current = artistWeights.get(track.artist) ?? 0;
      const delta =
        row.eventType === 'track_completed'
          ? 3
          : row.eventType === 'play_started'
            ? 1
            : row.eventType.startsWith('skip')
              ? -1
              : 0;
      artistWeights.set(track.artist, current + delta);
    });

    const excludedKeys = new Set([
      ...likedRows.map((row) => row.trackKey),
      ...historyRows.map((row) => row.trackKey),
    ]);

    if (artistWeights.size === 0) {
      return this.editorialTracks(excludedKeys, limit);
    }

    const trackMap = new Map<string, TrackPayload>();
    const seedTracks = [
      ...likedRows.slice(0, 2).map((row) => row.trackPayload as unknown as TrackPayload),
      ...historyRows
        .filter((row) => ['play_started', 'track_completed'].includes(row.eventType))
        .slice(0, 2)
        .map((row) => row.trackPayload as unknown as TrackPayload),
    ];

    const similarBatches = await Promise.all(
      seedTracks.map((seed) =>
        this.musicService
          .similarTracks(seed, [...excludedKeys], 6)
          .catch(() => [] as TrackPayload[]),
      ),
    );

    for (const batch of similarBatches) {
      for (const track of batch) {
        if (!trackMap.has(track.track_key) && !excludedKeys.has(track.track_key)) {
          trackMap.set(track.track_key, track);
        }
        if (trackMap.size >= limit) {
          return [...trackMap.values()].slice(0, limit);
        }
      }
    }

    const topArtists = [...artistWeights.entries()]
      .sort((left, right) => right[1] - left[1])
      .slice(0, 2)
      .map(([artist]) => artist);

    const artistBatches = await Promise.all(
      topArtists.map((artist) => this.musicService.topTracksForArtist(artist, 8).catch(() => [])),
    );
    for (const batch of artistBatches) {
      for (const track of batch) {
        if (!trackMap.has(track.track_key) && !excludedKeys.has(track.track_key)) {
          trackMap.set(track.track_key, track);
        }
        if (trackMap.size >= limit) {
          return [...trackMap.values()].slice(0, limit);
        }
      }
    }

    return [...trackMap.values()].slice(0, limit);
  }

  private async buildGeneratedPlaylists(
    user: User,
    recommendationsSeed: TrackPayload[],
  ): Promise<GeneratedPlaylistPayload[]> {
    const [likedRows, historyRows] = await Promise.all([
      this.prisma.savedTrack.findMany({
        where: { userId: user.id },
        orderBy: { createdAt: 'desc' },
        take: 24,
      }),
      this.prisma.playbackEvent.findMany({
        where: { userId: user.id },
        orderBy: { createdAt: 'desc' },
        take: 40,
      }),
    ]);

    const likedTracks = likedRows.map((row) => row.trackPayload as unknown as TrackPayload);
    const historyTracks = historyRows.map((row) => row.trackPayload as unknown as TrackPayload);
    const playlists: GeneratedPlaylistPayload[] = [];

    if (recommendationsSeed.length > 0) {
      playlists.push({
        playlist_key: 'discover-weekly',
        title: 'Découvertes de la semaine',
        subtitle: 'Une sélection fraîche construite autour de ce que tu écoutes déjà',
        artwork_url: this.bestTrackVisual(recommendationsSeed),
        tracks: recommendationsSeed.slice(0, 12),
      });
    }

    if (likedTracks.length > 0 || historyTracks.length > 0) {
      const rewind = this.dedupeTracks([...historyTracks.slice(0, 6), ...likedTracks.slice(0, 6)]).slice(
        0,
        12,
      );
      playlists.push({
        playlist_key: 'on-repeat',
        title: 'On Repeat',
        subtitle: 'Les titres que tu rejoues le plus en ce moment',
        artwork_url: this.bestTrackVisual(rewind),
        tracks: rewind,
      });
    }

    const topArtists = [...this.countArtists([...likedTracks, ...historyTracks]).entries()]
      .sort((left, right) => right[1] - left[1])
      .slice(0, 2)
      .map(([artist]) => artist);

    for (const [index, artist] of topArtists.entries()) {
      let artistTracks = this.dedupeTracks(
        [
          ...likedTracks.filter((track) => track.artist === artist),
          ...historyTracks.filter((track) => track.artist === artist),
          ...recommendationsSeed.filter((track) => track.artist === artist),
        ],
      ).slice(0, 12);
      if (artistTracks.length < 8) {
        const fetched = await this.musicService.topTracksForArtist(artist, 8).catch(() => []);
        artistTracks = this.dedupeTracks([...artistTracks, ...fetched]).slice(0, 12);
      }
      if (artistTracks.length > 0) {
        playlists.push({
          playlist_key: `daily-mix-${index + 1}-${artist.toLowerCase().replace(/\s+/g, '-')}`,
          title: `Daily Mix ${index + 1}`,
          subtitle: `Un mix centré sur ${artist} et les artistes qui gravitent autour`,
          artwork_url: this.bestTrackVisual(artistTracks),
          tracks: artistTracks,
        });
      }
    }

    if (topArtists[0]) {
      const artist = topArtists[0];
      let artistTracks = this.dedupeTracks(
        [
          ...recommendationsSeed.filter((track) => track.artist === artist),
          ...likedTracks.filter((track) => track.artist === artist),
          ...historyTracks.filter((track) => track.artist === artist),
        ],
      ).slice(0, 12);
      if (artistTracks.length < 8) {
        const fetched = await this.musicService.topTracksForArtist(artist, 8).catch(() => []);
        artistTracks = this.dedupeTracks([...artistTracks, ...fetched]).slice(0, 12);
      }
      if (artistTracks.length > 0) {
        playlists.push({
          playlist_key: `artist-radio-${artist.toLowerCase().replace(/\s+/g, '-')}`,
          title: `Radio ${artist}`,
          subtitle: 'Une station auto-générée à partir de ton artiste dominant',
          artwork_url: this.bestTrackVisual(artistTracks),
          tracks: artistTracks,
        });
      }
    }

    if (playlists.length === 0) {
      const editorialSeeds = [
        ['daily-mix-1', 'Daily Mix 1', 'Une base polyvalente pour démarrer l’écoute', 'pop hits'],
        [
          'discover-weekly',
          'Découvertes de la semaine',
          'Des sorties et titres frais pour lancer ton profil',
          'new music friday',
        ],
        ['afro-mix', 'Afro Mix', 'Afrobeats, amapiano et chaleur immédiate', 'afrobeats hits'],
        ['chill-mix', 'Chill Mix', 'Textures calmes, pop nocturne et morceaux posés', 'chill hits'],
      ] as const;

      for (const [key, title, subtitle, query] of editorialSeeds) {
        const tracks = await this.musicService.searchTracks(query, 12).catch(() => []);
        if (tracks.length === 0) {
          continue;
        }
        playlists.push({
          playlist_key: key,
          title,
          subtitle,
          artwork_url: this.bestTrackVisual(tracks),
          tracks,
        });
      }
    }

    return playlists.slice(0, 5);
  }

  private editorialTracks(excludedKeys: Set<string>, limit: number): Promise<TrackPayload[]> {
    const queries = [
      'new music friday',
      'pop hits',
      'rap francais',
      'hip hop hits',
      'afrobeats hits',
      'chill hits',
    ];
    return (async () => {
      const result = new Map<string, TrackPayload>();
      for (const query of queries) {
        const tracks = await this.musicService.searchTracks(query, limit).catch(() => []);
        for (const track of tracks) {
          if (!excludedKeys.has(track.track_key) && !result.has(track.track_key)) {
            result.set(track.track_key, track);
          }
          if (result.size >= limit) {
            return [...result.values()].slice(0, limit);
          }
        }
      }
      return [...result.values()].slice(0, limit);
    })();
  }

  private bestTrackVisual(tracks: TrackPayload[]): string | null {
    return (
      tracks.find((track) => track.artwork_url)?.artwork_url ??
      tracks.find((track) => track.artist_image_url)?.artist_image_url ??
      null
    );
  }

  private dedupeTracks(tracks: TrackPayload[]): TrackPayload[] {
    const map = new Map<string, TrackPayload>();
    for (const track of tracks) {
      if (!map.has(track.track_key)) {
        map.set(track.track_key, track);
      }
    }
    return [...map.values()];
  }

  private countArtists(tracks: TrackPayload[]): Map<string, number> {
    const map = new Map<string, number>();
    for (const track of tracks) {
      if (!track.artist) {
        continue;
      }
      map.set(track.artist, (map.get(track.artist) ?? 0) + 1);
    }
    return map;
  }

  private async safeTimed<T>(fn: () => Promise<T>, fallback: T, timeoutMs: number): Promise<T> {
    try {
      return await Promise.race([
        fn(),
        new Promise<T>((resolve) => setTimeout(() => resolve(fallback), timeoutMs)),
      ]);
    } catch {
      return fallback;
    }
  }

  private async attachManagedGeneratedPlaylists(
    playlists: GeneratedPlaylistPayload[],
  ): Promise<GeneratedPlaylistPayload[]> {
    const tracksByPlaylist = await Promise.all(
      playlists.map((playlist) => this.enrichGeneratedPlaylistTracks(playlist.tracks)),
    );
    return playlists.map((playlist, index) => ({
      ...playlist,
      tracks: tracksByPlaylist[index] ?? playlist.tracks,
      artwork_url:
        this.bestTrackVisual(tracksByPlaylist[index] ?? playlist.tracks) ??
        playlist.artwork_url,
    }));
  }

  private async enrichGeneratedPlaylistTracks(tracks: TrackPayload[]): Promise<TrackPayload[]> {
    const subset = await Promise.all(
      tracks.slice(0, 4).map((track) => this.enrichGeneratedTrackVisualFallback(track)),
    );
    const hydratedSubset = await this.musicService.attachManagedTrackVisuals(subset);
    const byKey = new Map(hydratedSubset.map((track) => [track.track_key, track]));
    return tracks.map((track) => byKey.get(track.track_key) ?? track);
  }

  private async enrichGeneratedTrackVisualFallback(track: TrackPayload): Promise<TrackPayload> {
    if (
      (track.artwork_url && track.artwork_url.length > 0) ||
      (track.artist_image_url && track.artist_image_url.length > 0)
    ) {
      return track;
    }

    const candidates = await this.musicService
      .searchTracks(`${track.artist} ${track.title}`, 4)
      .catch(() => [] as TrackPayload[]);
    if (candidates.length === 0) {
      return track;
    }

    for (const candidate of candidates) {
      if (
        this.normalizeForMatch(candidate.artist) === this.normalizeForMatch(track.artist) &&
        this.normalizeForMatch(candidate.title) === this.normalizeForMatch(track.title)
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

  private async refreshManagedHomeResponse(response: HomeResponse): Promise<HomeResponse> {
    const [
      recentlyPlayed,
      likedTracks,
      recommendations,
      generatedPlaylists,
      browseCategories,
      featuredPodcasts,
    ] = await Promise.all([
      this.musicService.attachManagedTrackVisuals(response.recently_played),
      this.musicService.attachManagedTrackVisuals(response.liked_tracks),
      this.musicService.attachManagedTrackVisuals(response.recommendations),
      this.attachManagedGeneratedPlaylists(response.generated_playlists),
      this.musicService.attachManagedBrowseArtwork(response.browse_categories),
      this.musicService.attachManagedPodcastArtwork(response.featured_podcasts),
    ]);
    return {
      recently_played: recentlyPlayed,
      liked_tracks: likedTracks,
      recommendations,
      generated_playlists: generatedPlaylists,
      browse_categories: browseCategories,
      featured_podcasts: featuredPodcasts,
    };
  }

  private async ensureSpotifyAccessToken(link: SpotifyAccountLink): Promise<SpotifyTokens> {
    if (link.accessToken && link.tokenExpiresAt && link.tokenExpiresAt > new Date(Date.now() + 120_000)) {
      return {
        accessToken: link.accessToken,
        refreshToken: link.refreshToken,
        expiresAt: link.tokenExpiresAt,
      };
    }
    if (!link.refreshToken) {
      throw new ConflictException('Spotify refresh token missing');
    }
    return this.refreshSpotifyAccessToken(link.refreshToken);
  }

  private async exchangeSpotifyCode(code: string): Promise<SpotifyTokens> {
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: this.appConfig.spotifyRedirectUri,
    });
    return this.spotifyTokenRequest(body);
  }

  private async refreshSpotifyAccessToken(refreshToken: string): Promise<SpotifyTokens> {
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    });
    const tokens = await this.spotifyTokenRequest(body);
    return {
      ...tokens,
      refreshToken: tokens.refreshToken ?? refreshToken,
    };
  }

  private async spotifyTokenRequest(body: URLSearchParams): Promise<SpotifyTokens> {
    const basic = Buffer.from(
      `${this.appConfig.spotifyClientId}:${this.appConfig.spotifyClientSecret}`,
    ).toString('base64');
    const response = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${basic}`,
        'content-type': 'application/x-www-form-urlencoded',
      },
      body,
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      throw new Error(await response.text());
    }
    const payload = (await response.json()) as Record<string, any>;
    return {
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token ?? null,
      expiresAt:
        typeof payload.expires_in === 'number'
          ? new Date(Date.now() + payload.expires_in * 1000)
          : null,
    };
  }

  private async fetchSpotifyApi(path: string, accessToken: string, params?: Record<string, string>) {
    const url = new URL(`https://api.spotify.com/v1${path}`);
    Object.entries(params ?? {}).forEach(([key, value]) => url.searchParams.set(key, value));
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      const text = await response.text();
      throw new Error(`${response.status}:${text}`);
    }
    return (await response.json()) as Record<string, any>;
  }

  private async fetchSpotifyImportBundle(accessToken: string): Promise<SpotifyImportBundle> {
    const [profile, likedTracks, savedShows, savedEpisodes, recentTracks] = await Promise.all([
      this.fetchSpotifyApi('/me', accessToken),
      this.safeSpotifyOptional(async () => this.fetchSpotifySavedTracks(accessToken)),
      this.safeSpotifyOptional(async () => this.fetchSpotifySavedShows(accessToken)),
      this.safeSpotifyOptional(async () => this.fetchSpotifySavedEpisodes(accessToken)),
      this.safeSpotifyOptional(async () => this.fetchSpotifyRecentTracks(accessToken)),
    ]);
    return {
      profile,
      likedTracks,
      savedShows,
      savedEpisodes,
      recentTracks,
    };
  }

  private async fetchSpotifySavedTracks(accessToken: string) {
    const rows = await this.spotifyPaginate('/me/tracks', accessToken);
    return rows
      .map((row) => {
        const track = this.mapSpotifyTrack(row.track);
        return track ? { track, createdAt: this.parseSpotifyDate(row.added_at) } : null;
      })
      .filter(Boolean) as Array<{ track: TrackPayload; createdAt: Date | null }>;
  }

  private async fetchSpotifySavedShows(accessToken: string) {
    const rows = await this.spotifyPaginate('/me/shows', accessToken);
    return rows
      .map((row) => {
        const podcast = this.mapSpotifyShow(row.show);
        return podcast ? { podcast, createdAt: this.parseSpotifyDate(row.added_at) } : null;
      })
      .filter(Boolean) as Array<{ podcast: PodcastPayload; createdAt: Date | null }>;
  }

  private async fetchSpotifySavedEpisodes(accessToken: string) {
    const rows = await this.spotifyPaginate('/me/episodes', accessToken);
    return rows
      .map((row) => {
        const episode = this.mapSpotifyEpisode(row.episode);
        return episode ? { episode, createdAt: this.parseSpotifyDate(row.added_at) } : null;
      })
      .filter(Boolean) as Array<{ episode: Record<string, any>; createdAt: Date | null }>;
  }

  private async fetchSpotifyRecentTracks(accessToken: string) {
    const payload = await this.fetchSpotifyApi('/me/player/recently-played', accessToken, {
      limit: '50',
    });
    return (payload.items ?? [])
      .map((row: Record<string, any>) => {
        const track = this.mapSpotifyTrack(row.track);
        return track ? { track, createdAt: this.parseSpotifyDate(row.played_at) } : null;
      })
      .filter(Boolean) as Array<{ track: TrackPayload; createdAt: Date | null }>;
  }

  private async spotifyPaginate(path: string, accessToken: string) {
    const items: Record<string, any>[] = [];
    let offset = 0;
    const limit = 50;
    while (true) {
      try {
        const payload = await this.fetchSpotifyApi(path, accessToken, {
          limit: `${limit}`,
          offset: `${offset}`,
        });
        const batch = Array.isArray(payload.items) ? payload.items : [];
        items.push(...batch);
        if (!payload.next) {
          break;
        }
        offset += limit;
      } catch (errorObject) {
        const message = String(errorObject);
        if (message.startsWith('401:') || message.startsWith('403:')) {
          break;
        }
        throw errorObject;
      }
    }
    return items;
  }

  private async safeSpotifyOptional<T>(fn: () => Promise<T>): Promise<T> {
    try {
      return await fn();
    } catch (errorObject) {
      const message = String(errorObject);
      if (message.startsWith('401:') || message.startsWith('403:')) {
        return [] as T;
      }
      throw errorObject;
    }
  }

  private mapSpotifyTrack(track: Record<string, any> | undefined): TrackPayload | null {
    if (!track?.name || !Array.isArray(track.artists) || track.artists.length === 0) {
      return null;
    }
    const artist = track.artists
      .map((item: Record<string, any>) => `${item.name ?? ''}`.trim())
      .filter(Boolean)
      .join(', ');
    return makeTrackPayload({
      title: `${track.name}`.trim(),
      artist,
      album: track.album?.name ?? null,
      artwork_url: track.album?.images?.[0]?.url ?? null,
      duration_ms: track.duration_ms ?? null,
      provider: 'spotify',
      external_id: track.id ?? null,
      preview_url: track.preview_url ?? null,
    });
  }

  private mapSpotifyShow(show: Record<string, any> | undefined): PodcastPayload | null {
    if (!show?.name) {
      return null;
    }
    return {
      podcast_key: `spotify-show-${show.id}`,
      title: `${show.name}`.trim(),
      publisher: `${show.publisher ?? 'Spotify'}`.trim(),
      description: `${show.description ?? ''}`.trim() || null,
      artwork_url: show.images?.[0]?.url ?? null,
      feed_url: null,
      external_url: show.external_urls?.spotify ?? null,
      episode_count: show.total_episodes ?? null,
      release_date: null,
    };
  }

  private mapSpotifyEpisode(episode: Record<string, any> | undefined): Record<string, any> | null {
    if (!episode?.name) {
      return null;
    }
    return {
      episode_key: `spotify-episode-${episode.id}`,
      podcast_title: episode.show?.name ?? 'Spotify',
      title: `${episode.name}`.trim(),
      publisher: `${episode.show?.publisher ?? ''}`.trim() || null,
      description: `${episode.description ?? ''}`.trim() || null,
      artwork_url: episode.images?.[0]?.url ?? episode.show?.images?.[0]?.url ?? null,
      external_url: episode.external_urls?.spotify ?? null,
      duration_seconds:
        typeof episode.duration_ms === 'number' ? Math.round(episode.duration_ms / 1000) : null,
      published_at: this.parseSpotifyDate(episode.release_date),
    };
  }

  private parseSpotifyDate(value: string | null | undefined): Date | null {
    if (!value) {
      return null;
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private async importSpotifyBundle(
    user: User,
    link: SpotifyAccountLink,
    bundle: SpotifyImportBundle,
    tokens: SpotifyTokens,
  ) {
    this.invalidateHomeCache(user.id);
    const avatar =
      Array.isArray(bundle.profile.images) && bundle.profile.images[0]?.url
        ? bundle.profile.images[0].url
        : null;
    await this.prisma.$transaction(async (tx) => {
      await tx.spotifyAccountLink.upsert({
        where: { userId: user.id },
        update: {
          spotifyUserId: `${bundle.profile.id}`,
          displayName: bundle.profile.display_name ?? null,
          email: bundle.profile.email ?? null,
          avatarUrl: avatar,
          country: bundle.profile.country ?? null,
          product: bundle.profile.product ?? null,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken ?? link.refreshToken,
          tokenExpiresAt: tokens.expiresAt,
          importedAt: new Date(),
          likedTracksImported: bundle.likedTracks.length,
          savedShowsImported: bundle.savedShows.length,
          savedEpisodesImported: bundle.savedEpisodes.length,
          recentTracksImported: bundle.recentTracks.length,
        },
        create: {
          id: link.id,
          userId: user.id,
          spotifyUserId: `${bundle.profile.id}`,
          displayName: bundle.profile.display_name ?? null,
          email: bundle.profile.email ?? null,
          avatarUrl: avatar,
          country: bundle.profile.country ?? null,
          product: bundle.profile.product ?? null,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          tokenExpiresAt: tokens.expiresAt,
          importedAt: new Date(),
          likedTracksImported: bundle.likedTracks.length,
          savedShowsImported: bundle.savedShows.length,
          savedEpisodesImported: bundle.savedEpisodes.length,
          recentTracksImported: bundle.recentTracks.length,
        },
      });

      for (const row of bundle.likedTracks) {
        await tx.savedTrack.upsert({
          where: {
            userId_trackKey: {
              userId: user.id,
              trackKey: row.track.track_key,
            },
          },
          update: {
            trackPayload: row.track as unknown as Prisma.InputJsonValue,
            createdAt: row.createdAt ?? undefined,
          },
          create: {
            id: generateId(),
            userId: user.id,
            trackKey: row.track.track_key,
            trackPayload: row.track as unknown as Prisma.InputJsonValue,
            createdAt: row.createdAt ?? new Date(),
          },
        });
      }

      await tx.savedPodcastShow.deleteMany({ where: { userId: user.id } });
      for (const row of bundle.savedShows) {
        await tx.savedPodcastShow.create({
          data: {
            id: generateId(),
            userId: user.id,
            podcastKey: row.podcast.podcast_key,
            podcastPayload: row.podcast as unknown as Prisma.InputJsonValue,
            createdAt: row.createdAt ?? new Date(),
          },
        });
      }

      await tx.savedPodcastEpisode.deleteMany({ where: { userId: user.id } });
      for (const row of bundle.savedEpisodes) {
        await tx.savedPodcastEpisode.create({
          data: {
            id: generateId(),
            userId: user.id,
            episodeKey: row.episode.episode_key,
            episodePayload: row.episode as Prisma.InputJsonValue,
            createdAt: row.createdAt ?? new Date(),
          },
        });
      }

      await tx.playbackEvent.deleteMany({
        where: { userId: user.id, eventType: 'spotify_import_recent' },
      });
      for (const row of bundle.recentTracks) {
        await tx.playbackEvent.create({
          data: {
            id: generateId(),
            userId: user.id,
            trackKey: row.track.track_key,
            eventType: 'spotify_import_recent',
            listenedMs: row.track.duration_ms ?? 0,
            completionRatio: 1,
            trackPayload: row.track as unknown as Prisma.InputJsonValue,
            createdAt: row.createdAt ?? new Date(),
          },
        });
      }
    });
  }

  private spotifyErrorMessage(errorObject: unknown): string {
    const message = String(errorObject);
    if (message.startsWith('403:')) {
      return (
        'Spotify a bien autorisé la connexion, mais la Web API refuse encore ce compte. ' +
        'Vérifie dans Spotify Developer Dashboard > User Management que le compte Spotify utilisé est bien ajouté ' +
        "aux utilisateurs autorisés en Development Mode. Vérifie aussi que le compte Spotify utilisé et le compte " +
        `propriétaire de l'app sont bien Premium, et que l'app a été créée avec l'API "Web API" sélectionnée dans le dashboard Spotify.`
      );
    }
    return `Impossible d'importer les données Spotify: ${message}.`;
  }

  private spotifyCallbackHtml(success: boolean, message: string): string {
    const accent = success ? '#61F5B9' : '#FF6B6B';
    const title = success ? 'Spotify import termine' : 'Spotify import impossible';
    return `
      <!doctype html>
      <html lang="fr">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>${title}</title>
          <style>
            body { margin: 0; background: linear-gradient(180deg, #132d2b 0%, #081717 60%, #041010 100%); color: #f4fffc; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
            .card { width: min(560px, calc(100vw - 48px)); margin: 10vh auto; padding: 28px; border-radius: 28px; background: rgba(12, 23, 24, 0.86); border: 1px solid rgba(255, 255, 255, 0.1); box-shadow: 0 20px 50px rgba(0,0,0,0.35); }
            .badge { display: inline-block; padding: 8px 12px; border-radius: 999px; background: rgba(0,0,0,0.2); color: ${accent}; border: 1px solid rgba(255,255,255,0.08); font-weight: 700; }
            h1 { margin: 18px 0 12px; font-size: 32px; }
            p { line-height: 1.5; color: #c9ddd8; }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="badge">JojoMusique × Spotify</div>
            <h1>${title}</h1>
            <p>${message}</p>
            <p>Tu peux fermer cette page et revenir dans JojoMusique.</p>
          </div>
        </body>
      </html>
    `;
  }
}
