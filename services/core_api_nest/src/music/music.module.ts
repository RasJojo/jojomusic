import { Module } from '@nestjs/common';
import { AppConfigService } from '../common/app-config.service';
import { MediaController } from './media.controller';
import { MusicController } from './music.controller';
import { MusicService } from './music.service';

@Module({
  controllers: [MusicController, MediaController],
  providers: [AppConfigService, MusicService],
  exports: [MusicService],
})
export class MusicModule {}
