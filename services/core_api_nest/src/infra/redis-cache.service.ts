import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import { AppConfigService } from '../common/app-config.service';

@Injectable()
export class RedisCacheService implements OnModuleDestroy {
  private readonly logger = new Logger(RedisCacheService.name);
  private readonly client: Redis | null;

  constructor(private readonly appConfig: AppConfigService) {
    this.client = this.appConfig.redisUrl
      ? new Redis(this.appConfig.redisUrl, {
          maxRetriesPerRequest: 1,
          lazyConnect: true,
        })
      : null;

    this.client?.on('error', (error) => {
      this.logger.warn(`Redis error: ${error instanceof Error ? error.message : String(error)}`);
    });
  }

  async getJson<T>(key: string): Promise<T | null> {
    const value = await this.get(key);
    if (!value) {
      return null;
    }
    try {
      return JSON.parse(value) as T;
    } catch {
      return null;
    }
  }

  async setJson(key: string, value: unknown, ttlSeconds: number): Promise<void> {
    await this.set(key, JSON.stringify(value), ttlSeconds);
  }

  async pushJsonToList(key: string, value: unknown): Promise<void> {
    if (!this.client) {
      return;
    }
    try {
      await this.ensureConnected();
      await this.client.lpush(key, JSON.stringify(value));
    } catch (error) {
      this.logger.warn(
        `Redis lpush failed for ${key}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  async delete(key: string): Promise<void> {
    if (!this.client) {
      return;
    }
    try {
      await this.ensureConnected();
      await this.client.del(key);
    } catch (error) {
      this.logger.warn(`Redis del failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  async get(key: string): Promise<string | null> {
    if (!this.client) {
      return null;
    }
    try {
      await this.ensureConnected();
      return await this.client.get(key);
    } catch (error) {
      this.logger.warn(`Redis get failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    if (!this.client) {
      return;
    }
    try {
      await this.ensureConnected();
      await this.client.set(key, value, 'EX', ttlSeconds);
    } catch (error) {
      this.logger.warn(`Redis set failed for ${key}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client) {
      await this.client.quit().catch(() => undefined);
    }
  }

  private async ensureConnected(): Promise<void> {
    if (!this.client) {
      return;
    }
    if (this.client.status === 'wait') {
      await this.client.connect();
    }
  }
}
