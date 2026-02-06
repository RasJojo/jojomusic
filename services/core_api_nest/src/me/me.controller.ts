import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import type { User } from '@prisma/client';
import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../common/current-user.decorator';
import type { TrackPayload } from '../common/payloads';
import { FollowPodcastDto, PlaybackEventCreateDto } from './dto/me.dto';
import { MeService } from './me.service';

@Controller('api/v1')
export class MeController {
  constructor(private readonly meService: MeService) {}

  @Get('me/likes')
  @UseGuards(AuthGuard)
  likes(@CurrentUser() user: User) {
    return this.meService.getLikes(user);
  }

  @Post('me/likes')
  @UseGuards(AuthGuard)
  like(@CurrentUser() user: User, @Body() track: TrackPayload) {
    return this.meService.likeTrack(user, track);
  }

  @Delete('me/likes/:trackKey')
  @UseGuards(AuthGuard)
  unlike(@CurrentUser() user: User, @Param('trackKey') trackKey: string) {
    return this.meService.unlikeTrack(user, trackKey);
  }

  @Get('me/history')
  @UseGuards(AuthGuard)
  history(@CurrentUser() user: User) {
    return this.meService.getHistory(user);
  }

  @Post('me/history')
  @UseGuards(AuthGuard)
  addHistory(@CurrentUser() user: User, @Body() payload: PlaybackEventCreateDto) {
    return this.meService.addHistory(user, payload);
  }

  @Get('me/podcasts')
  @UseGuards(AuthGuard)
  podcasts(@CurrentUser() user: User) {
    return this.meService.getFollowedPodcasts(user);
  }

  @Post('me/podcasts')
  @UseGuards(AuthGuard)
  followPodcast(@CurrentUser() user: User, @Body() payload: FollowPodcastDto) {
    return this.meService.followPodcast(user, payload.podcast);
  }

  @Delete('me/podcasts/:podcastKey')
  @UseGuards(AuthGuard)
  unfollowPodcast(@CurrentUser() user: User, @Param('podcastKey') podcastKey: string) {
    return this.meService.unfollowPodcast(user, podcastKey);
  }

  @Get('recommendations')
  @UseGuards(AuthGuard)
  recommendations(@CurrentUser() user: User) {
    return this.meService.recommendations(user);
  }

  @Get('me/home')
  @UseGuards(AuthGuard)
  home(@CurrentUser() user: User) {
    return this.meService.home(user);
  }

  @Get('me/integrations/spotify')
  @UseGuards(AuthGuard)
  spotifyStatus(@CurrentUser() user: User) {
    return this.meService.spotifyStatus(user);
  }

  @Get('me/integrations/spotify/connect')
  @UseGuards(AuthGuard)
  spotifyConnect(@CurrentUser() user: User) {
    return this.meService.spotifyConnect(user);
  }

  @Post('me/integrations/spotify/sync')
  @UseGuards(AuthGuard)
  spotifySync(@CurrentUser() user: User) {
    return this.meService.spotifySync(user);
  }

  @Delete('me/integrations/spotify')
  @UseGuards(AuthGuard)
  spotifyDisconnect(@CurrentUser() user: User) {
    return this.meService.spotifyDisconnect(user);
  }

  @Get('integrations/spotify/callback')
  @Header('content-type', 'text/html; charset=utf-8')
  spotifyCallback(
    @Query('code') code?: string,
    @Query('state') state?: string,
    @Query('error') error?: string,
  ) {
    return this.meService.spotifyCallback(code, state, error);
  }
}
// Me endpoint
