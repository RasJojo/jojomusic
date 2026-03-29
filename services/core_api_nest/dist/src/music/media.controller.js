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
exports.MediaController = void 0;
const common_1 = require("@nestjs/common");
const music_service_1 = require("./music.service");
let MediaController = class MediaController {
    musicService;
    constructor(musicService) {
        this.musicService = musicService;
    }
    async streamAudioAsset(assetKey, response) {
        const asset = await this.musicService.getReadyAudioAssetByAssetKey(assetKey);
        if (!asset) {
            throw new common_1.NotFoundException('Audio asset not found');
        }
        response.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
        response.setHeader('Accept-Ranges', 'bytes');
        return response.sendFile(asset.filePath);
    }
    async streamImageAsset(assetKey, response) {
        const asset = await this.musicService.getReadyImageAssetByAssetKey(assetKey);
        if (!asset) {
            throw new common_1.NotFoundException('Image asset not found');
        }
        response.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
        if (asset.contentType) {
            response.type(asset.contentType);
        }
        return response.sendFile(asset.filePath);
    }
};
exports.MediaController = MediaController;
__decorate([
    (0, common_1.Get)('audio/:assetKey'),
    __param(0, (0, common_1.Param)('assetKey')),
    __param(1, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], MediaController.prototype, "streamAudioAsset", null);
__decorate([
    (0, common_1.Get)('image/:assetKey'),
    __param(0, (0, common_1.Param)('assetKey')),
    __param(1, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], MediaController.prototype, "streamImageAsset", null);
exports.MediaController = MediaController = __decorate([
    (0, common_1.Controller)('api/v1/media'),
    __metadata("design:paramtypes", [music_service_1.MusicService])
], MediaController);
//# sourceMappingURL=media.controller.js.map