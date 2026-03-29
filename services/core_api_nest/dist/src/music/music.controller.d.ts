import { MusicService } from './music.service';
import { AlbumDetailsDto, ArtistDetailsDto, LyricsDto, PodcastSearchDto, ResolveTrackRequestDto, SearchQueryDto, SimilarTracksRequestDto } from './dto/music.dto';
export declare class MusicController {
    private readonly musicService;
    constructor(musicService: MusicService);
    search(query: SearchQueryDto): Promise<import("../common/payloads").SearchResponse>;
    artistDetails(query: ArtistDetailsDto): Promise<import("../common/payloads").ArtistDetailsResponse>;
    albumDetails(query: AlbumDetailsDto): Promise<import("../common/payloads").AlbumDetailsResponse>;
    browseCategories(): Promise<import("../common/payloads").BrowseCategoryPayload[]>;
    browseCategory(categoryId: string): Promise<import("../common/payloads").BrowseCategoryResponse>;
    podcastsSearch(query: PodcastSearchDto): Promise<import("../common/payloads").PodcastPayload[]>;
    podcastDetails(podcastKey: string): Promise<import("../common/payloads").PodcastDetailsResponse>;
    lyrics(query: LyricsDto): Promise<import("../common/payloads").LyricsResponse | null>;
    resolveTrack(payload: ResolveTrackRequestDto): Promise<import("../common/payloads").ResolvedStream>;
    similarTracks(payload: SimilarTracksRequestDto): Promise<import("../common/payloads").TrackPayload[]>;
}
