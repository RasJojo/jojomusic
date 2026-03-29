import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { AppConfigService } from './common/app-config.service';
import { HealthController } from './health/health.controller';
import { InfraModule } from './infra/infra.module';
import { MeModule } from './me/me.module';
import { MusicModule } from './music/music.module';
import { PlaylistsModule } from './playlists/playlists.module';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env', '../../.env'],
    }),
    InfraModule,
    PrismaModule,
    AuthModule,
    MusicModule,
    MeModule,
    PlaylistsModule,
  ],
  controllers: [HealthController],
  providers: [AppConfigService],
})
export class AppModule {}
