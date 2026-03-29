import { Type } from 'class-transformer';
import {
  Allow,
  IsArray,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import type { PodcastPayload, TrackPayload } from '../../common/payloads';

export class PlaybackEventCreateDto {
  @IsString()
  event_type!: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  listened_ms?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  completion_ratio?: number;

  @Allow()
  track!: TrackPayload;
}

export class FollowPodcastDto {
  @Allow()
  podcast!: PodcastPayload;
}
