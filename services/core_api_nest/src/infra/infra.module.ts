import { Global, Module } from '@nestjs/common';
import { AppConfigService } from '../common/app-config.service';
import { RedisCacheService } from './redis-cache.service';
import { SearchIndexService } from './search-index.service';

@Global()
@Module({
  providers: [AppConfigService, RedisCacheService, SearchIndexService],
  exports: [RedisCacheService, SearchIndexService],
})
export class InfraModule {}
