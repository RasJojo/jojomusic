import type { PodcastPayload, TrackPayload } from '../../common/payloads';
export declare class PlaybackEventCreateDto {
    event_type: string;
    listened_ms?: number;
    completion_ratio?: number;
    track: TrackPayload;
}
export declare class FollowPodcastDto {
    podcast: PodcastPayload;
}
