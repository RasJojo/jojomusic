import { Controller, Get, NotFoundException, Param, Res } from '@nestjs/common';
import type { Response } from 'express';
import { MusicService } from './music.service';

@Controller('api/v1/media')
export class MediaController {
  constructor(private readonly musicService: MusicService) {}

  @Get('audio/:assetKey')
  async streamAudioAsset(@Param('assetKey') assetKey: string, @Res() response: Response) {
    const asset = await this.musicService.getReadyAudioAssetByAssetKey(assetKey);
    if (!asset) {
      throw new NotFoundException('Audio asset not found');
    }
    response.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    response.setHeader('Accept-Ranges', 'bytes');
    return response.sendFile(asset.filePath);
  }

  @Get('image/:assetKey')
  async streamImageAsset(@Param('assetKey') assetKey: string, @Res() response: Response) {
    const asset = await this.musicService.getReadyImageAssetByAssetKey(assetKey);
    if (!asset) {
      throw new NotFoundException('Image asset not found');
    }
    response.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    if (asset.contentType) {
      response.type(asset.contentType);
    }
    return response.sendFile(asset.filePath);
  }
}
