import { ConfigService } from '@nestjs/config';
export declare class AppConfigService {
    private readonly configService;
    constructor(configService: ConfigService);
    get appName(): string;
    get jwtSecret(): string;
    get jwtAlgorithm(): string;
    get accessTokenMinutes(): number;
    get resolverApiUrl(): string;
    get resolverTimeoutSeconds(): number;
    get lastfmApiKey(): string;
    get lastfmSharedSecret(): string;
    get lrclibBaseUrl(): string;
    get spotifyClientId(): string;
    get spotifyClientSecret(): string;
    get spotifyRedirectUri(): string;
    get spotifyScopes(): string;
    get geniusAccessToken(): string;
    get redisUrl(): string;
    get meilisearchUrl(): string;
    get meilisearchApiKey(): string;
    get publicBaseUrl(): string;
    get mediaCacheDir(): string;
    get mediaQueueKey(): string;
    get imageQueueKey(): string;
    get imageCacheDir(): string;
    get corsOrigins(): string[];
}
