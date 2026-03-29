import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class AppConfigService {
  constructor(private readonly configService: ConfigService) {}

  get appName(): string {
    return this.configService.get<string>('APP_NAME') ?? 'JojoMusic Core API';
  }

  get jwtSecret(): string {
    return this.configService.get<string>('JWT_SECRET') ?? 'change-me';
  }

  get jwtAlgorithm(): string {
    return this.configService.get<string>('JWT_ALGORITHM') ?? 'HS256';
  }

  get accessTokenMinutes(): number {
    return Number(this.configService.get<string>('ACCESS_TOKEN_MINUTES') ?? 60 * 24 * 7);
  }

  get resolverApiUrl(): string {
    return this.configService.get<string>('RESOLVER_API_URL') ?? 'http://localhost:8001';
  }

  get resolverTimeoutSeconds(): number {
    return Number(this.configService.get<string>('RESOLVER_TIMEOUT_SECONDS') ?? 25);
  }

  get lastfmApiKey(): string {
    return this.configService.get<string>('LASTFM_API_KEY') ?? '';
  }

  get lastfmSharedSecret(): string {
    return this.configService.get<string>('LASTFM_SHARED_SECRET') ?? '';
  }

  get lrclibBaseUrl(): string {
    return this.configService.get<string>('LRCLIB_BASE_URL') ?? 'https://lrclib.net';
  }

  get spotifyClientId(): string {
    return this.configService.get<string>('SPOTIFY_CLIENT_ID') ?? '';
  }

  get spotifyClientSecret(): string {
    return this.configService.get<string>('SPOTIFY_CLIENT_SECRET') ?? '';
  }

  get spotifyRedirectUri(): string {
    return (
      this.configService.get<string>('SPOTIFY_REDIRECT_URI') ??
      'http://127.0.0.1:8000/api/v1/integrations/spotify/callback'
    );
  }

  get spotifyScopes(): string {
    return (
      this.configService.get<string>('SPOTIFY_SCOPES') ??
      'user-library-read user-read-email user-read-private user-read-recently-played'
    );
  }

  get geniusAccessToken(): string {
    return this.configService.get<string>('GENIUS_ACCESS_TOKEN') ?? '';
  }

  get redisUrl(): string {
    return this.configService.get<string>('REDIS_URL') ?? '';
  }

  get meilisearchUrl(): string {
    return this.configService.get<string>('MEILISEARCH_URL') ?? '';
  }

  get meilisearchApiKey(): string {
    return this.configService.get<string>('MEILISEARCH_API_KEY') ?? '';
  }

  get publicBaseUrl(): string {
    return this.configService.get<string>('PUBLIC_BASE_URL') ?? 'http://127.0.0.1:8000';
  }

  get mediaCacheDir(): string {
    return this.configService.get<string>('MEDIA_CACHE_DIR') ?? '/data/audio_cache';
  }

  get mediaQueueKey(): string {
    return this.configService.get<string>('MEDIA_QUEUE_KEY') ?? 'media:ingest';
  }

  get imageQueueKey(): string {
    return this.configService.get<string>('IMAGE_QUEUE_KEY') ?? 'image:ingest';
  }

  get imageCacheDir(): string {
    return this.configService.get<string>('IMAGE_CACHE_DIR') ?? '/data/image_cache';
  }

  get corsOrigins(): string[] {
    const value =
      this.configService.get<string>('CORS_ALLOW_ORIGINS') ??
      [
        'https://jojomusic-web.vercel.app',
        'http://localhost:3000',
        'http://127.0.0.1:3000',
        'http://localhost:8877',
        'http://127.0.0.1:8877',
      ].join(',');
    return value
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean);
  }
}
