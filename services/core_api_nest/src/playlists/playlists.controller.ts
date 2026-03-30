import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import type { User } from '@prisma/client';
import { AuthGuard } from '../auth/auth.guard';
import { CurrentUser } from '../common/current-user.decorator';
import {
  PlaylistCreateDto,
  PlaylistTrackCreateDto,
  PlaylistUpdateDto,
} from './dto/playlists.dto';
import { PlaylistsService } from './playlists.service';

@Controller('api/v1/playlists')
@UseGuards(AuthGuard)
export class PlaylistsController {
  constructor(private readonly playlistsService: PlaylistsService) {}

  @Get()
  list(@CurrentUser() user: User) {
    return this.playlistsService.list(user);
  }

  @Post()
  create(@CurrentUser() user: User, @Body() payload: PlaylistCreateDto) {
    return this.playlistsService.create(user, payload);
  }

  @Patch(':playlistId')
  update(
    @CurrentUser() user: User,
    @Param('playlistId') playlistId: string,
    @Body() payload: PlaylistUpdateDto,
  ) {
    return this.playlistsService.update(user, playlistId, payload);
  }

  @Post(':playlistId/tracks')
  addTrack(
    @CurrentUser() user: User,
    @Param('playlistId') playlistId: string,
    @Body() payload: PlaylistTrackCreateDto,
  ) {
    return this.playlistsService.addTrack(user, playlistId, payload);
  }

  @Delete(':playlistId/tracks/:trackKey')
  removeTrack(
    @CurrentUser() user: User,
    @Param('playlistId') playlistId: string,
    @Param('trackKey') trackKey: string,
  ) {
    return this.playlistsService.removeTrack(user, playlistId, trackKey);
  }

  @Delete(':playlistId')
  delete(@CurrentUser() user: User, @Param('playlistId') playlistId: string) {
    return this.playlistsService.delete(user, playlistId);
  }
}
