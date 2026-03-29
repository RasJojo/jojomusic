import { OnModuleDestroy } from '@nestjs/common';
import { AppConfigService } from '../common/app-config.service';
export declare class RedisCacheService implements OnModuleDestroy {
    private readonly appConfig;
    private readonly logger;
    private readonly client;
    constructor(appConfig: AppConfigService);
    getJson<T>(key: string): Promise<T | null>;
    setJson(key: string, value: unknown, ttlSeconds: number): Promise<void>;
    pushJsonToList(key: string, value: unknown): Promise<void>;
    delete(key: string): Promise<void>;
    get(key: string): Promise<string | null>;
    set(key: string, value: string, ttlSeconds: number): Promise<void>;
    onModuleDestroy(): Promise<void>;
    private ensureConnected;
}
