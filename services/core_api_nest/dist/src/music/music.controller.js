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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.MusicController = void 0;
const common_1 = require("@nestjs/common");
const music_service_1 = require("./music.service");
const music_dto_1 = require("./dto/music.dto");
let MusicController = class MusicController {
    musicService;
    constructor(musicService) {
        this.musicService = musicService;
    }
    search(query) {
        return this.musicService.search(query.query, query.limit ?? 20);
    }
    artistDetails(query) {
        return this.musicService.artistDetails(query.name);
    }
    albumDetails(query) {
        return this.musicService.albumDetails(query.artist, query.title, query.external_id);
    }
    browseCategories() {
        return this.musicService.browseCategories();
    }
    browseCategory(categoryId) {
        return this.musicService.browseCategory(categoryId);
    }
    podcastsSearch(query) {
        return this.musicService.searchPodcasts(query.query, query.limit ?? 12);
    }
    podcastDetails(podcastKey) {
        return this.musicService.podcastDetails(podcastKey);
    }
    lyrics(query) {
        return this.musicService.lyrics(query.artist, query.title);
    }
    resolveTrack(payload) {
        return this.musicService.resolveTrack(payload);
    }
    similarTracks(payload) {
        return this.musicService.similarTracks(payload.track, payload.exclude_track_keys ?? [], payload.limit ?? 12);
    }
};
exports.MusicController = MusicController;
__decorate([
    (0, common_1.Get)('search'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.SearchQueryDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "search", null);
__decorate([
    (0, common_1.Get)('artists/details'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.ArtistDetailsDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "artistDetails", null);
__decorate([
    (0, common_1.Get)('albums/details'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.AlbumDetailsDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "albumDetails", null);
__decorate([
    (0, common_1.Get)('browse/categories'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "browseCategories", null);
__decorate([
    (0, common_1.Get)('browse/categories/:categoryId'),
    __param(0, (0, common_1.Param)('categoryId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "browseCategory", null);
__decorate([
    (0, common_1.Get)('podcasts/search'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.PodcastSearchDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "podcastsSearch", null);
__decorate([
    (0, common_1.Get)('podcasts/:podcastKey'),
    __param(0, (0, common_1.Param)('podcastKey')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "podcastDetails", null);
__decorate([
    (0, common_1.Get)('lyrics'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.LyricsDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "lyrics", null);
__decorate([
    (0, common_1.Post)('tracks/resolve'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.ResolveTrackRequestDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "resolveTrack", null);
__decorate([
    (0, common_1.Post)('tracks/similar'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [music_dto_1.SimilarTracksRequestDto]),
    __metadata("design:returntype", void 0)
], MusicController.prototype, "similarTracks", null);
exports.MusicController = MusicController = __decorate([
    (0, common_1.Controller)('api/v1'),
    __metadata("design:paramtypes", [music_service_1.MusicService])
], MusicController);
//# sourceMappingURL=music.controller.js.map