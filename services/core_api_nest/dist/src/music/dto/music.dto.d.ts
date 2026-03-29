import type { TrackPayload } from '../../common/payloads';
export declare class SearchQueryDto {
    query: string;
    limit?: number;
}
export declare class ArtistDetailsDto {
    name: string;
}
export declare class AlbumDetailsDto {
    artist: string;
    title: string;
    external_id?: string;
}
export declare class BrowseCategoryDto {
    category_id: string;
}
export declare class PodcastSearchDto {
    query: string;
    limit?: number;
}
export declare class PodcastDetailsDto {
    podcast_key: string;
}
export declare class LyricsDto {
    artist: string;
    title: string;
}
export declare class ResolveTrackRequestDto {
    track?: TrackPayload;
    query?: string;
    artist?: string;
    title?: string;
}
export declare class SimilarTracksRequestDto {
    track: TrackPayload;
    limit?: number;
    exclude_track_keys?: string[];
}
