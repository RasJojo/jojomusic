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
exports.MeController = void 0;
const common_1 = require("@nestjs/common");
const auth_guard_1 = require("../auth/auth.guard");
const current_user_decorator_1 = require("../common/current-user.decorator");
const me_dto_1 = require("./dto/me.dto");
const me_service_1 = require("./me.service");
let MeController = class MeController {
    meService;
    constructor(meService) {
        this.meService = meService;
    }
    likes(user) {
        return this.meService.getLikes(user);
    }
    like(user, track) {
        return this.meService.likeTrack(user, track);
    }
    unlike(user, trackKey) {
        return this.meService.unlikeTrack(user, trackKey);
    }
    history(user) {
        return this.meService.getHistory(user);
    }
    addHistory(user, payload) {
        return this.meService.addHistory(user, payload);
    }
    podcasts(user) {
        return this.meService.getFollowedPodcasts(user);
    }
    followPodcast(user, payload) {
        return this.meService.followPodcast(user, payload.podcast);
    }
    unfollowPodcast(user, podcastKey) {
        return this.meService.unfollowPodcast(user, podcastKey);
    }
    recommendations(user) {
        return this.meService.recommendations(user);
    }
    home(user) {
        return this.meService.home(user);
    }
    spotifyStatus(user) {
        return this.meService.spotifyStatus(user);
    }
    spotifyConnect(user) {
        return this.meService.spotifyConnect(user);
    }
    spotifySync(user) {
        return this.meService.spotifySync(user);
    }
    spotifyDisconnect(user) {
        return this.meService.spotifyDisconnect(user);
    }
    spotifyCallback(code, state, error) {
        return this.meService.spotifyCallback(code, state, error);
    }
};
exports.MeController = MeController;
__decorate([
    (0, common_1.Get)('me/likes'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "likes", null);
__decorate([
    (0, common_1.Post)('me/likes'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "like", null);
__decorate([
    (0, common_1.Delete)('me/likes/:trackKey'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('trackKey')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "unlike", null);
__decorate([
    (0, common_1.Get)('me/history'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "history", null);
__decorate([
    (0, common_1.Post)('me/history'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, me_dto_1.PlaybackEventCreateDto]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "addHistory", null);
__decorate([
    (0, common_1.Get)('me/podcasts'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "podcasts", null);
__decorate([
    (0, common_1.Post)('me/podcasts'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, me_dto_1.FollowPodcastDto]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "followPodcast", null);
__decorate([
    (0, common_1.Delete)('me/podcasts/:podcastKey'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __param(1, (0, common_1.Param)('podcastKey')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "unfollowPodcast", null);
__decorate([
    (0, common_1.Get)('recommendations'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "recommendations", null);
__decorate([
    (0, common_1.Get)('me/home'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "home", null);
__decorate([
    (0, common_1.Get)('me/integrations/spotify'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "spotifyStatus", null);
__decorate([
    (0, common_1.Get)('me/integrations/spotify/connect'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "spotifyConnect", null);
__decorate([
    (0, common_1.Post)('me/integrations/spotify/sync'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "spotifySync", null);
__decorate([
    (0, common_1.Delete)('me/integrations/spotify'),
    (0, common_1.UseGuards)(auth_guard_1.AuthGuard),
    __param(0, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "spotifyDisconnect", null);
__decorate([
    (0, common_1.Get)('integrations/spotify/callback'),
    (0, common_1.Header)('content-type', 'text/html; charset=utf-8'),
    __param(0, (0, common_1.Query)('code')),
    __param(1, (0, common_1.Query)('state')),
    __param(2, (0, common_1.Query)('error')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", void 0)
], MeController.prototype, "spotifyCallback", null);
exports.MeController = MeController = __decorate([
    (0, common_1.Controller)('api/v1'),
    __metadata("design:paramtypes", [me_service_1.MeService])
], MeController);
//# sourceMappingURL=me.controller.js.map