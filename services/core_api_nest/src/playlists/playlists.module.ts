import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MeModule } from '../me/me.module';
import { MusicModule } from '../music/music.module';
import { PlaylistsController } from './playlists.controller';
import { PlaylistsService } from './playlists.service';

@Module({
  imports: [AuthModule, MeModule, MusicModule],
  controllers: [PlaylistsController],
  providers: [PlaylistsService],
})
export class PlaylistsModule {}
