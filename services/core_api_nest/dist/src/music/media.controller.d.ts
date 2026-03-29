import type { Response } from 'express';
import { MusicService } from './music.service';
export declare class MediaController {
    private readonly musicService;
    constructor(musicService: MusicService);
    streamAudioAsset(assetKey: string, response: Response): Promise<void>;
    streamImageAsset(assetKey: string, response: Response): Promise<void>;
}
