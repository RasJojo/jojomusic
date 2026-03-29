import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { AppConfigService } from '../common/app-config.service';
import { MusicModule } from '../music/music.module';
import { MeController } from './me.controller';
import { MeService } from './me.service';

@Module({
  imports: [AuthModule, MusicModule],
  controllers: [MeController],
  providers: [AppConfigService, MeService],
  exports: [MeService],
})
export class MeModule {}
