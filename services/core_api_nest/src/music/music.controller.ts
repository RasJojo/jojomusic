import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { MusicService } from './music.service';
import {
  AlbumDetailsDto,
  ArtistDetailsDto,
  LyricsDto,
  PodcastSearchDto,
  ResolveTrackRequestDto,
  SearchQueryDto,
  SimilarTracksRequestDto,
} from './dto/music.dto';

@Controller('api/v1')
export class MusicController {
  constructor(private readonly musicService: MusicService) {}

  @Get('search')
  search(@Query() query: SearchQueryDto) {
    return this.musicService.search(query.query, query.limit ?? 20);
  }

  @Get('artists/details')
  artistDetails(@Query() query: ArtistDetailsDto) {
    return this.musicService.artistDetails(query.name);
  }

  @Get('albums/details')
  albumDetails(@Query() query: AlbumDetailsDto) {
    return this.musicService.albumDetails(query.artist, query.title, query.external_id);
  }

  @Get('browse/categories')
  browseCategories() {
    return this.musicService.browseCategories();
  }

  @Get('browse/categories/:categoryId')
  browseCategory(@Param('categoryId') categoryId: string) {
    return this.musicService.browseCategory(categoryId);
  }

  @Get('podcasts/search')
  podcastsSearch(@Query() query: PodcastSearchDto) {
    return this.musicService.searchPodcasts(query.query, query.limit ?? 12);
  }

  @Get('podcasts/:podcastKey')
  podcastDetails(@Param('podcastKey') podcastKey: string) {
    return this.musicService.podcastDetails(podcastKey);
  }

  @Get('lyrics')
  lyrics(@Query() query: LyricsDto) {
    return this.musicService.lyrics(query.artist, query.title);
  }

  @Post('tracks/resolve')
  resolveTrack(@Body() payload: ResolveTrackRequestDto) {
    return this.musicService.resolveTrack(payload);
  }

  @Post('tracks/similar')
  similarTracks(@Body() payload: SimilarTracksRequestDto) {
    return this.musicService.similarTracks(
      payload.track,
      payload.exclude_track_keys ?? [],
      payload.limit ?? 12,
    );
  }
}
