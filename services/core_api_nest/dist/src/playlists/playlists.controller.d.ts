import type { User } from '@prisma/client';
import { PlaylistCreateDto, PlaylistTrackCreateDto } from './dto/playlists.dto';
import { PlaylistsService } from './playlists.service';
export declare class PlaylistsController {
    private readonly playlistsService;
    constructor(playlistsService: PlaylistsService);
    list(user: User): Promise<{
        id: string;
        name: string;
        description: string;
        artwork_url: string | null;
        created_at: Date;
        updated_at: Date;
        tracks: {
            id: string;
            track_key: string;
            position: number;
            track_payload: Record<string, unknown>;
            created_at: Date;
        }[];
    }[]>;
    create(user: User, payload: PlaylistCreateDto): Promise<{
        id: string;
        name: string;
        description: string;
        artwork_url: string | null;
        created_at: Date;
        updated_at: Date;
        tracks: {
            id: string;
            track_key: string;
            position: number;
            track_payload: Record<string, unknown>;
            created_at: Date;
        }[];
    }>;
    addTrack(user: User, playlistId: string, payload: PlaylistTrackCreateDto): Promise<{
        id: string;
        name: string;
        description: string;
        artwork_url: string | null;
        created_at: Date;
        updated_at: Date;
        tracks: {
            id: string;
            track_key: string;
            position: number;
            track_payload: Record<string, unknown>;
            created_at: Date;
        }[];
    }>;
    removeTrack(user: User, playlistId: string, trackKey: string): Promise<{
        id: string;
        name: string;
        description: string;
        artwork_url: string | null;
        created_at: Date;
        updated_at: Date;
        tracks: {
            id: string;
            track_key: string;
            position: number;
            track_payload: Record<string, unknown>;
            created_at: Date;
        }[];
    }>;
    delete(user: User, playlistId: string): Promise<void>;
}
