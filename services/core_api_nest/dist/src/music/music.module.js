"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.MusicModule = void 0;
const common_1 = require("@nestjs/common");
const app_config_service_1 = require("../common/app-config.service");
const media_controller_1 = require("./media.controller");
const music_controller_1 = require("./music.controller");
const music_service_1 = require("./music.service");
let MusicModule = class MusicModule {
};
exports.MusicModule = MusicModule;
exports.MusicModule = MusicModule = __decorate([
    (0, common_1.Module)({
        controllers: [music_controller_1.MusicController, media_controller_1.MediaController],
        providers: [app_config_service_1.AppConfigService, music_service_1.MusicService],
        exports: [music_service_1.MusicService],
    })
], MusicModule);
//# sourceMappingURL=music.module.js.map