import type { User } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MusicService } from '../music/music.service';
import { PlaylistCreateDto, PlaylistTrackCreateDto } from './dto/playlists.dto';
export declare class PlaylistsService {
    private readonly prisma;
    private readonly musicService;
    constructor(prisma: PrismaService, musicService: MusicService);
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
    private trackPayloads;
    private hydratePlaylistVisuals;
    private bestPlaylistArtwork;
    private enrichTrackVisualFallback;
    private normalizeForMatch;
    private toPlaylistOut;
}
