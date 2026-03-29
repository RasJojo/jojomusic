import { Allow, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import type { TrackPayload } from '../../common/payloads';

export class PlaylistCreateDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  artwork_url?: string;
}

export class PlaylistTrackCreateDto {
  @Allow()
  track!: TrackPayload;
}
