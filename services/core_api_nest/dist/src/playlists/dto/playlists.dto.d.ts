import type { TrackPayload } from '../../common/payloads';
export declare class PlaylistCreateDto {
    name: string;
    description?: string;
    artwork_url?: string;
}
export declare class PlaylistTrackCreateDto {
    track: TrackPayload;
}
