"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.MeModule = void 0;
const common_1 = require("@nestjs/common");
const auth_module_1 = require("../auth/auth.module");
const app_config_service_1 = require("../common/app-config.service");
const music_module_1 = require("../music/music.module");
const me_controller_1 = require("./me.controller");
const me_service_1 = require("./me.service");
let MeModule = class MeModule {
};
exports.MeModule = MeModule;
exports.MeModule = MeModule = __decorate([
    (0, common_1.Module)({
        imports: [auth_module_1.AuthModule, music_module_1.MusicModule],
        controllers: [me_controller_1.MeController],
        providers: [app_config_service_1.AppConfigService, me_service_1.MeService],
        exports: [me_service_1.MeService],
    })
], MeModule);
//# sourceMappingURL=me.module.js.map