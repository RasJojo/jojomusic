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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
var RedisCacheService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.RedisCacheService = void 0;
const common_1 = require("@nestjs/common");
const ioredis_1 = __importDefault(require("ioredis"));
const app_config_service_1 = require("../common/app-config.service");
let RedisCacheService = RedisCacheService_1 = class RedisCacheService {
    appConfig;
    logger = new common_1.Logger(RedisCacheService_1.name);
    client;
    constructor(appConfig) {
        this.appConfig = appConfig;
        this.client = this.appConfig.redisUrl
            ? new ioredis_1.default(this.appConfig.redisUrl, {
                maxRetriesPerRequest: 1,
                lazyConnect: true,
            })
            : null;
        this.client?.on('error', (error) => {
            this.logger.warn(`Redis error: ${error instanceof Error ? error.message : String(error)}`);
        });
    }
    async getJson(key) {
        const value = await this.get(key);
        if (!value) {
            return null;
        }
        try {
            return JSON.parse(value);
        }
        catch {
            return null;
        }
    }
    async setJson(key, value, ttlSeconds) {
        await this.set(key, JSON.stringify(value), ttlSeconds);
    }
    async pushJsonToList(key, value) {
        if (!this.client) {
            return;
        }
        try {
            await this.ensureConnected();
            await this.client.lpush(key, JSON.stringify(value));
        }
        catch (error) {
            this.logger.warn(`Redis lpush failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    async delete(key) {
        if (!this.client) {
            return;
        }
        try {
            await this.ensureConnected();
            await this.client.del(key);
        }
        catch (error) {
            this.logger.warn(`Redis del failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    async get(key) {
        if (!this.client) {
            return null;
        }
        try {
            await this.ensureConnected();
            return await this.client.get(key);
        }
        catch (error) {
            this.logger.warn(`Redis get failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
            return null;
        }
    }
    async set(key, value, ttlSeconds) {
        if (!this.client) {
            return;
        }
        try {
            await this.ensureConnected();
            await this.client.set(key, value, 'EX', ttlSeconds);
        }
        catch (error) {
            this.logger.warn(`Redis set failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    async onModuleDestroy() {
        if (this.client) {
            await this.client.quit().catch(() => undefined);
        }
    }
    async ensureConnected() {
        if (!this.client) {
            return;
        }
        if (this.client.status === 'wait') {
            await this.client.connect();
        }
    }
};
exports.RedisCacheService = RedisCacheService;
exports.RedisCacheService = RedisCacheService = RedisCacheService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [app_config_service_1.AppConfigService])
], RedisCacheService);
//# sourceMappingURL=redis-cache.service.js.map