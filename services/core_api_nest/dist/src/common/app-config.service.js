"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppConfigService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
let AppConfigService = class AppConfigService {
    configService;
    constructor(configService) {
        this.configService = configService;
    }
    get appName() {
        return this.configService.get('APP_NAME') ?? 'JojoMusic Core API';
    }
    get jwtSecret() {
        return this.configService.get('JWT_SECRET') ?? 'change-me';
    }
    get jwtAlgorithm() {
        return this.configService.get('JWT_ALGORITHM') ?? 'HS256';
    }
    get accessTokenMinutes() {
        return Number(this.configService.get('ACCESS_TOKEN_MINUTES') ?? 60 * 24 * 7);
    }
    get resolverApiUrl() {
        return this.configService.get('RESOLVER_API_URL') ?? 'http://localhost:8001';
    }
    get resolverTimeoutSeconds() {
        return Number(this.configService.get('RESOLVER_TIMEOUT_SECONDS') ?? 25);
    }
    get lastfmApiKey() {
        return this.configService.get('LASTFM_API_KEY') ?? '';
    }
    get lastfmSharedSecret() {
        return this.configService.get('LASTFM_SHARED_SECRET') ?? '';
    }
    get lrclibBaseUrl() {
        return this.configService.get('LRCLIB_BASE_URL') ?? 'https://lrclib.net';
    }
    get spotifyClientId() {
        return this.configService.get('SPOTIFY_CLIENT_ID') ?? '';
    }
    get spotifyClientSecret() {
        return this.configService.get('SPOTIFY_CLIENT_SECRET') ?? '';
    }
    get spotifyRedirectUri() {
        return (this.configService.get('SPOTIFY_REDIRECT_URI') ??
            'http://127.0.0.1:8000/api/v1/integrations/spotify/callback');
    }
    get spotifyScopes() {
        return (this.configService.get('SPOTIFY_SCOPES') ??
            'user-library-read user-read-email user-read-private user-read-recently-played');
    }
    get geniusAccessToken() {
        return this.configService.get('GENIUS_ACCESS_TOKEN') ?? '';
    }
    get redisUrl() {
        return this.configService.get('REDIS_URL') ?? '';
    }
    get meilisearchUrl() {
        return this.configService.get('MEILISEARCH_URL') ?? '';
    }
    get meilisearchApiKey() {
        return this.configService.get('MEILISEARCH_API_KEY') ?? '';
    }
    get publicBaseUrl() {
        return this.configService.get('PUBLIC_BASE_URL') ?? 'http://127.0.0.1:8000';
    }
    get mediaCacheDir() {
        return this.configService.get('MEDIA_CACHE_DIR') ?? '/data/audio_cache';
    }
    get mediaQueueKey() {
        return this.configService.get('MEDIA_QUEUE_KEY') ?? 'media:ingest';
    }
    get imageQueueKey() {
        return this.configService.get('IMAGE_QUEUE_KEY') ?? 'image:ingest';
    }
    get imageCacheDir() {
        return this.configService.get('IMAGE_CACHE_DIR') ?? '/data/image_cache';
    }
    get corsOrigins() {
        const value = this.configService.get('CORS_ALLOW_ORIGINS') ??
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
};
exports.AppConfigService = AppConfigService;
exports.AppConfigService = AppConfigService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [config_1.ConfigService])
], AppConfigService);
//# sourceMappingURL=app-config.service.js.map