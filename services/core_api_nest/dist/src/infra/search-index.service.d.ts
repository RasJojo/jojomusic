import type { SearchResponse } from '../common/payloads';
import { AppConfigService } from '../common/app-config.service';
export declare class SearchIndexService {
    private readonly appConfig;
    private readonly logger;
    private readonly client;
    private ensurePromise;
    constructor(appConfig: AppConfigService);
    search(query: string, limit: number): Promise<SearchResponse | null>;
    indexSearchResponse(response: SearchResponse): Promise<void>;
    private ensureIndex;
}
