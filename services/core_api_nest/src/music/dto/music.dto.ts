import { Type } from 'class-transformer';
import {
  Allow,
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import type { TrackPayload } from '../../common/payloads';

export class SearchQueryDto {
  @IsString()
  query!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;
}

export class ArtistDetailsDto {
  @IsString()
  name!: string;
}

export class AlbumDetailsDto {
  @IsString()
  artist!: string;

  @IsString()
  title!: string;

  @IsOptional()
  @IsString()
  external_id?: string;
}

export class BrowseCategoryDto {
  @IsString()
  category_id!: string;
}

export class PodcastSearchDto {
  @IsString()
  query!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(25)
  limit?: number;
}

export class PodcastDetailsDto {
  @IsString()
  podcast_key!: string;
}

export class LyricsDto {
  @IsString()
  artist!: string;

  @IsString()
  title!: string;
}

export class ResolveTrackRequestDto {
  @IsOptional()
  @Allow()
  track?: TrackPayload;

  @IsOptional()
  @IsString()
  query?: string;

  @IsOptional()
  @IsString()
  artist?: string;

  @IsOptional()
  @IsString()
  title?: string;
}

export class SimilarTracksRequestDto {
  @Allow()
  track!: TrackPayload;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(24)
  limit?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  exclude_track_keys?: string[];
}
