"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.InfraModule = void 0;
const common_1 = require("@nestjs/common");
const app_config_service_1 = require("../common/app-config.service");
const redis_cache_service_1 = require("./redis-cache.service");
const search_index_service_1 = require("./search-index.service");
let InfraModule = class InfraModule {
};
exports.InfraModule = InfraModule;
exports.InfraModule = InfraModule = __decorate([
    (0, common_1.Global)(),
    (0, common_1.Module)({
        providers: [app_config_service_1.AppConfigService, redis_cache_service_1.RedisCacheService, search_index_service_1.SearchIndexService],
        exports: [redis_cache_service_1.RedisCacheService, search_index_service_1.SearchIndexService],
    })
], InfraModule);
//# sourceMappingURL=infra.module.js.map