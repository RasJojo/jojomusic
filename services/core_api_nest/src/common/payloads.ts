import { randomUUID } from 'node:crypto';

export interface UserOut {
  id: string;
  name: string;
  email: string;
  created_at: Date;
}

export interface AuthResponse {
  access_token: string;
  token_type: 'bearer';
  user: UserOut;
}

export interface SpotifyConnectResponse {
  authorize_url: string;
}

export interface TrackPayload {
  track_key: string;
  title: string;
  artist: string;
  album?: string | null;
  artwork_url?: string | null;
  artist_image_url?: string | null;
  duration_ms?: number | null;
  provider: string;
  external_id?: string | null;
  preview_url?: string | null;
  lyrics_synced_available: boolean;
}

export interface ArtistPayload {
  artist_key: string;
  name: string;
  image_url?: string | null;
  provider: string;
  external_id?: string | null;
  url?: string | null;
  listeners?: number | null;
  summary?: string | null;
}

export interface AlbumPayload {
  album_key: string;
  title: string;
  artist: string;
  artwork_url?: string | null;
  provider: string;
  external_id?: string | null;
  summary?: string | null;
  release_date?: Date | null;
  track_count?: number | null;
}

export interface PodcastPayload {
  podcast_key: string;
  title: string;
  publisher: string;
  description?: string | null;
  artwork_url?: string | null;
  feed_url?: string | null;
  external_url?: string | null;
  episode_count?: number | null;
  release_date?: Date | null;
}

export interface PodcastEpisodePayload {
  episode_key: string;
  podcast_title: string;
  title: string;
  publisher?: string | null;
  description?: string | null;
  artwork_url?: string | null;
  audio_url?: string | null;
  external_url?: string | null;
  duration_seconds?: number | null;
  published_at?: Date | null;
}

export interface BrowseCategoryPayload {
  category_id: string;
  title: string;
  subtitle: string;
  color_hex: string;
  search_seed: string;
  artwork_url?: string | null;
}

export interface BrowseCategoryResponse {
  category: BrowseCategoryPayload;
  tracks: TrackPayload[];
  artists: ArtistPayload[];
  albums: AlbumPayload[];
  podcasts: PodcastPayload[];
}

export interface GeneratedPlaylistPayload {
  playlist_key: string;
  title: string;
  subtitle: string;
  artwork_url?: string | null;
  tracks: TrackPayload[];
}

export interface SearchResponse {
  query: string;
  artists: ArtistPayload[];
  tracks: TrackPayload[];
  albums: AlbumPayload[];
  podcasts: PodcastPayload[];
}

export interface ResolvedStream {
  stream_url: string;
  webpage_url?: string | null;
  thumbnail_url?: string | null;
  title: string;
  artist: string;
  duration_ms?: number | null;
  source: string;
}

export interface LyricsResponse {
  artist: string;
  title: string;
  plain_lyrics?: string | null;
  synced_lyrics?: string | null;
  provider: string;
}

export interface PlaybackEventOut {
  id: string;
  track_key: string;
  event_type: string;
  listened_ms: number;
  completion_ratio: number;
  track_payload: Record<string, unknown>;
  created_at: Date;
}

export interface PlaylistTrackOut {
  id: string;
  track_key: string;
  position: number;
  track_payload: Record<string, unknown>;
  created_at: Date;
}

export interface PlaylistOut {
  id: string;
  name: string;
  description: string;
  artwork_url?: string | null;
  created_at: Date;
  updated_at: Date;
  tracks: PlaylistTrackOut[];
}

export interface HomeResponse {
  recently_played: TrackPayload[];
  liked_tracks: TrackPayload[];
  recommendations: TrackPayload[];
  generated_playlists: GeneratedPlaylistPayload[];
  browse_categories: BrowseCategoryPayload[];
  featured_podcasts: PodcastPayload[];
}

export interface ArtistDetailsResponse {
  artist: ArtistPayload;
  top_tracks: TrackPayload[];
  top_albums: AlbumPayload[];
  similar_artists: ArtistPayload[];
}

export interface AlbumDetailsResponse {
  album: AlbumPayload;
  tracks: TrackPayload[];
}

export interface PodcastDetailsResponse {
  podcast: PodcastPayload;
  episodes: PodcastEpisodePayload[];
}

export interface SpotifyIntegrationStatus {
  configured: boolean;
  connected: boolean;
  configuration_hint?: string | null;
  spotify_user_id?: string | null;
  display_name?: string | null;
  email?: string | null;
  avatar_url?: string | null;
  country?: string | null;
  product?: string | null;
  imported_at?: Date | null;
  liked_tracks_imported: number;
  saved_shows_imported: number;
  saved_episodes_imported: number;
  recent_tracks_imported: number;
  saved_shows: PodcastPayload[];
}

export const BROWSE_CATEGORIES: BrowseCategoryPayload[] = [
  {
    category_id: 'new-releases',
    title: 'Nouveautés',
    subtitle: 'Dernières sorties, singles frais et nouveautés à lancer',
    color_hex: '#C04A23',
    search_seed: 'new music friday',
  },
  {
    category_id: 'pop-hits',
    title: 'Pop',
    subtitle: 'Hits immédiats, refrains massifs et grosses sorties',
    color_hex: '#8B2877',
    search_seed: 'pop hits',
  },
  {
    category_id: 'rap-hiphop',
    title: 'Rap & Hip-Hop',
    subtitle: 'Rap FR, US, trap et gros titres du moment',
    color_hex: '#B1591E',
    search_seed: 'rap hip hop',
  },
  {
    category_id: 'afro-vibes',
    title: 'Afro',
    subtitle: 'Afrobeats, amapiano et chaleur instantanée',
    color_hex: '#7A5A00',
    search_seed: 'afrobeats amapiano',
  },
  {
    category_id: 'mada-vibes',
    title: 'Madagascar',
    subtitle: 'Mada vibes, rap local, salegy et scène malgache',
    color_hex: '#007A62',
    search_seed: 'music malagasy',
  },
  {
    category_id: 'chill-mood',
    title: 'Chill',
    subtitle: 'Calme, focus, late night et textures douces',
    color_hex: '#274A9A',
    search_seed: 'chill hits',
  },
  {
    category_id: 'workout-energy',
    title: 'Workout',
    subtitle: 'Énergie, cardio, motivation et percussions lourdes',
    color_hex: '#1E8554',
    search_seed: 'workout mix',
  },
  {
    category_id: 'love-songs',
    title: 'Love',
    subtitle: 'Slow jams, pop sentimentale et titres à émotions',
    color_hex: '#A02458',
    search_seed: 'love songs rnb',
  },
  {
    category_id: 'podcasts-editorial',
    title: 'Podcasts musicaux',
    subtitle: 'Culture, interviews, société et épisodes longs',
    color_hex: '#5A276F',
    search_seed: 'podcast francais',
  },
];

export function normalizeValue(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export function buildTrackKey(artist: string, title: string): string {
  return normalizeValue(`${artist}-${title}`);
}

export function buildArtistKey(name: string): string {
  return normalizeValue(name);
}

export function buildAlbumKey(artist: string, title: string): string {
  return normalizeValue(`${artist}-${title}`);
}

export function makeTrackPayload(partial: Partial<TrackPayload> & Pick<TrackPayload, 'title' | 'artist'>): TrackPayload {
  return {
    track_key: partial.track_key ?? buildTrackKey(partial.artist, partial.title),
    title: partial.title,
    artist: partial.artist,
    album: partial.album ?? null,
    artwork_url: partial.artwork_url ?? null,
    artist_image_url: partial.artist_image_url ?? null,
    duration_ms: partial.duration_ms ?? null,
    provider: partial.provider ?? 'internal',
    external_id: partial.external_id ?? null,
    preview_url: partial.preview_url ?? null,
    lyrics_synced_available: partial.lyrics_synced_available ?? false,
  };
}

export function toUserOut(user: {
  id: string;
  name: string;
  email: string;
  createdAt: Date;
}): UserOut {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    created_at: user.createdAt,
  };
}

export function generateId(): string {
  return randomUUID();
}
