import type { User } from '@prisma/client';
import type { TrackPayload } from '../common/payloads';
import { FollowPodcastDto, PlaybackEventCreateDto } from './dto/me.dto';
import { MeService } from './me.service';
export declare class MeController {
    private readonly meService;
    constructor(meService: MeService);
    likes(user: User): Promise<TrackPayload[]>;
    like(user: User, track: TrackPayload): Promise<TrackPayload>;
    unlike(user: User, trackKey: string): Promise<void>;
    history(user: User): Promise<{
        id: string;
        track_key: string;
        event_type: string;
        listened_ms: number;
        completion_ratio: number;
        track_payload: Record<string, unknown>;
        created_at: Date;
    }[]>;
    addHistory(user: User, payload: PlaybackEventCreateDto): Promise<{
        id: string;
        track_key: string;
        event_type: string;
        listened_ms: number;
        completion_ratio: number;
        track_payload: Record<string, unknown>;
        created_at: Date;
    }>;
    podcasts(user: User): Promise<import("../common/payloads").PodcastPayload[]>;
    followPodcast(user: User, payload: FollowPodcastDto): Promise<import("../common/payloads").PodcastPayload>;
    unfollowPodcast(user: User, podcastKey: string): Promise<void>;
    recommendations(user: User): Promise<TrackPayload[]>;
    home(user: User): Promise<import("../common/payloads").HomeResponse>;
    spotifyStatus(user: User): Promise<import("../common/payloads").SpotifyIntegrationStatus>;
    spotifyConnect(user: User): import("../common/payloads").SpotifyConnectResponse;
    spotifySync(user: User): Promise<import("../common/payloads").SpotifyIntegrationStatus>;
    spotifyDisconnect(user: User): Promise<void>;
    spotifyCallback(code?: string, state?: string, error?: string): Promise<string>;
}
