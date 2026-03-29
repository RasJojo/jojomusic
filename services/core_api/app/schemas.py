from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=6, max_length=120)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    email: str
    created_at: datetime


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class SpotifyConnectResponse(BaseModel):
    authorize_url: str


class SpotifyIntegrationStatus(BaseModel):
    configured: bool = False
    connected: bool = False
    configuration_hint: str | None = None
    spotify_user_id: str | None = None
    display_name: str | None = None
    email: str | None = None
    avatar_url: str | None = None
    country: str | None = None
    product: str | None = None
    imported_at: datetime | None = None
    liked_tracks_imported: int = 0
    saved_shows_imported: int = 0
    saved_episodes_imported: int = 0
    recent_tracks_imported: int = 0
    saved_shows: list["PodcastPayload"] = Field(default_factory=list)


class TrackPayload(BaseModel):
    track_key: str
    title: str
    artist: str
    album: str | None = None
    artwork_url: str | None = None
    artist_image_url: str | None = None
    duration_ms: int | None = None
    provider: str = "internal"
    external_id: str | None = None
    preview_url: str | None = None
    lyrics_synced_available: bool = False


class ArtistPayload(BaseModel):
    artist_key: str
    name: str
    image_url: str | None = None
    provider: str = "internal"
    external_id: str | None = None
    url: str | None = None
    listeners: int | None = None
    summary: str | None = None


class AlbumPayload(BaseModel):
    album_key: str
    title: str
    artist: str
    artwork_url: str | None = None
    provider: str = "internal"
    external_id: str | None = None
    summary: str | None = None
    release_date: datetime | None = None
    track_count: int | None = None


class PodcastPayload(BaseModel):
    podcast_key: str
    title: str
    publisher: str
    description: str | None = None
    artwork_url: str | None = None
    feed_url: str | None = None
    external_url: str | None = None
    episode_count: int | None = None
    release_date: datetime | None = None


class PodcastEpisodePayload(BaseModel):
    episode_key: str
    podcast_title: str
    title: str
    publisher: str | None = None
    description: str | None = None
    artwork_url: str | None = None
    audio_url: str | None = None
    external_url: str | None = None
    duration_seconds: int | None = None
    published_at: datetime | None = None


class BrowseCategoryPayload(BaseModel):
    category_id: str
    title: str
    subtitle: str
    color_hex: str
    search_seed: str
    artwork_url: str | None = None


class GeneratedPlaylistPayload(BaseModel):
    playlist_key: str
    title: str
    subtitle: str
    artwork_url: str | None = None
    tracks: list["TrackPayload"] = Field(default_factory=list)


class SearchResponse(BaseModel):
    query: str
    artists: list[ArtistPayload] = Field(default_factory=list)
    tracks: list[TrackPayload] = Field(default_factory=list)
    albums: list[AlbumPayload] = Field(default_factory=list)
    podcasts: list[PodcastPayload] = Field(default_factory=list)


class ResolveTrackRequest(BaseModel):
    track: TrackPayload | None = None
    query: str | None = None


class SimilarTracksRequest(BaseModel):
    track: TrackPayload
    limit: int = 12
    exclude_track_keys: list[str] = Field(default_factory=list)


class ResolvedStream(BaseModel):
    stream_url: str
    webpage_url: str | None = None
    thumbnail_url: str | None = None
    title: str
    artist: str
    duration_ms: int | None = None
    source: str = "youtube"


class PlaybackEventCreate(BaseModel):
    event_type: str
    listened_ms: int = 0
    completion_ratio: float = 0.0
    track: TrackPayload


class PlaybackEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    track_key: str
    event_type: str
    listened_ms: int
    completion_ratio: float
    track_payload: dict
    created_at: datetime


class PlaylistCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str = ""
    artwork_url: str | None = None


class PlaylistTrackCreate(BaseModel):
    track: TrackPayload


class PlaylistTrackOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    track_key: str
    position: int
    track_payload: dict
    created_at: datetime


class PlaylistOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    description: str
    artwork_url: str | None = None
    created_at: datetime
    updated_at: datetime
    tracks: list[PlaylistTrackOut]


class LyricsResponse(BaseModel):
    artist: str
    title: str
    plain_lyrics: str | None = None
    synced_lyrics: str | None = None
    provider: str = "lrclib"


class HomeResponse(BaseModel):
    recently_played: list[TrackPayload]
    liked_tracks: list[TrackPayload]
    recommendations: list[TrackPayload]
    generated_playlists: list[GeneratedPlaylistPayload] = Field(default_factory=list)
    browse_categories: list[BrowseCategoryPayload] = Field(default_factory=list)
    featured_podcasts: list[PodcastPayload] = Field(default_factory=list)


class ArtistDetailsResponse(BaseModel):
    artist: ArtistPayload
    top_tracks: list[TrackPayload] = Field(default_factory=list)
    top_albums: list[AlbumPayload] = Field(default_factory=list)
    similar_artists: list[ArtistPayload] = Field(default_factory=list)


class AlbumDetailsResponse(BaseModel):
    album: AlbumPayload
    tracks: list[TrackPayload] = Field(default_factory=list)


class BrowseCategoryResponse(BaseModel):
    category: BrowseCategoryPayload
    tracks: list[TrackPayload] = Field(default_factory=list)
    artists: list[ArtistPayload] = Field(default_factory=list)
    albums: list[AlbumPayload] = Field(default_factory=list)
    podcasts: list[PodcastPayload] = Field(default_factory=list)


class PodcastDetailsResponse(BaseModel):
    podcast: PodcastPayload
    episodes: list[PodcastEpisodePayload] = Field(default_factory=list)


SpotifyIntegrationStatus.model_rebuild()
