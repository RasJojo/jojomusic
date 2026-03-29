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
var SearchIndexService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SearchIndexService = void 0;
const common_1 = require("@nestjs/common");
const meilisearch_1 = require("meilisearch");
const app_config_service_1 = require("../common/app-config.service");
let SearchIndexService = SearchIndexService_1 = class SearchIndexService {
    appConfig;
    logger = new common_1.Logger(SearchIndexService_1.name);
    client;
    ensurePromise = null;
    constructor(appConfig) {
        this.appConfig = appConfig;
        this.client = this.appConfig.meilisearchUrl
            ? new meilisearch_1.MeiliSearch({
                host: this.appConfig.meilisearchUrl,
                apiKey: this.appConfig.meilisearchApiKey || undefined,
            })
            : null;
    }
    async search(query, limit) {
        if (!this.client) {
            return null;
        }
        try {
            const index = await this.ensureIndex();
            const result = await index.search(query, {
                limit: Math.max(limit * 4, 24),
                attributesToRetrieve: ['type', 'payload'],
            });
            const artists = [];
            const tracks = [];
            const albums = [];
            const podcasts = [];
            for (const hit of result.hits) {
                switch (hit.type) {
                    case 'artist':
                        if (artists.length < Math.min(limit, 6)) {
                            artists.push(hit.payload);
                        }
                        break;
                    case 'track':
                        if (tracks.length < limit) {
                            tracks.push(hit.payload);
                        }
                        break;
                    case 'album':
                        if (albums.length < Math.min(limit, 10)) {
                            albums.push(hit.payload);
                        }
                        break;
                    case 'podcast':
                        if (podcasts.length < Math.min(limit, 6)) {
                            podcasts.push(hit.payload);
                        }
                        break;
                }
            }
            if (artists.length === 0 &&
                tracks.length === 0 &&
                albums.length === 0 &&
                podcasts.length === 0) {
                return null;
            }
            return {
                query,
                artists,
                tracks,
                albums,
                podcasts,
            };
        }
        catch (error) {
            this.logger.warn(`Meilisearch query failed: ${error instanceof Error ? error.message : String(error)}`);
            return null;
        }
    }
    async indexSearchResponse(response) {
        if (!this.client) {
            return;
        }
        const documents = [
            ...response.artists.map((artist) => ({
                id: `artist:${artist.artist_key}`,
                type: 'artist',
                title: artist.name,
                payload: artist,
            })),
            ...response.tracks.map((track) => ({
                id: `track:${track.track_key}`,
                type: 'track',
                title: track.title,
                artist: track.artist,
                album: track.album ?? null,
                payload: track,
            })),
            ...response.albums.map((album) => ({
                id: `album:${album.album_key}`,
                type: 'album',
                title: album.title,
                artist: album.artist,
                payload: album,
            })),
            ...response.podcasts.map((podcast) => ({
                id: `podcast:${podcast.podcast_key}`,
                type: 'podcast',
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
        }
        catch (error) {
            this.logger.warn(`Meilisearch indexing failed: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    async ensureIndex() {
        if (!this.client) {
            throw new Error('Meilisearch is not configured');
        }
        if (!this.ensurePromise) {
            this.ensurePromise = (async () => {
                const uid = 'catalog';
                const indexes = await this.client.getIndexes();
                const existing = indexes.results.find((index) => index.uid === uid);
                if (!existing) {
                    await this.client.createIndex(uid, { primaryKey: 'id' });
                }
                const index = this.client.index(uid);
                await index.updateSearchableAttributes(['title', 'artist', 'album']);
                await index.updateFilterableAttributes(['type']);
                return index;
            })();
        }
        return this.ensurePromise;
    }
};
exports.SearchIndexService = SearchIndexService;
exports.SearchIndexService = SearchIndexService = SearchIndexService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [app_config_service_1.AppConfigService])
], SearchIndexService);
//# sourceMappingURL=search-index.service.js.map