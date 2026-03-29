from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(120))
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    playlists: Mapped[list["Playlist"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    liked_tracks: Mapped[list["SavedTrack"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    playback_events: Mapped[list["PlaybackEvent"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    spotify_link: Mapped["SpotifyAccountLink | None"] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        uselist=False,
    )
    saved_podcast_shows: Mapped[list["SavedPodcastShow"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )
    saved_podcast_episodes: Mapped[list["SavedPodcastEpisode"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )


class Playlist(Base):
    __tablename__ = "playlists"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(Text, default="")
    artwork_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user: Mapped["User"] = relationship(back_populates="playlists")
    tracks: Mapped[list["PlaylistTrack"]] = relationship(
        back_populates="playlist",
        cascade="all, delete-orphan",
        order_by="PlaylistTrack.position",
    )


class PlaylistTrack(Base):
    __tablename__ = "playlist_tracks"
    __table_args__ = (UniqueConstraint("playlist_id", "track_key", name="uq_playlist_track"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    playlist_id: Mapped[str] = mapped_column(ForeignKey("playlists.id", ondelete="CASCADE"), index=True)
    track_key: Mapped[str] = mapped_column(String(255), index=True)
    position: Mapped[int] = mapped_column(Integer)
    track_payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    playlist: Mapped["Playlist"] = relationship(back_populates="tracks")


class SavedTrack(Base):
    __tablename__ = "saved_tracks"
    __table_args__ = (UniqueConstraint("user_id", "track_key", name="uq_saved_track"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    track_key: Mapped[str] = mapped_column(String(255), index=True)
    track_payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped["User"] = relationship(back_populates="liked_tracks")


class PlaybackEvent(Base):
    __tablename__ = "playback_events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    track_key: Mapped[str] = mapped_column(String(255), index=True)
    event_type: Mapped[str] = mapped_column(String(40), index=True)
    listened_ms: Mapped[int] = mapped_column(Integer, default=0)
    completion_ratio: Mapped[float] = mapped_column(Float, default=0.0)
    track_payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)

    user: Mapped["User"] = relationship(back_populates="playback_events")


class SpotifyAccountLink(Base):
    __tablename__ = "spotify_account_links"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        index=True,
    )
    spotify_user_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    country: Mapped[str | None] = mapped_column(String(12), nullable=True)
    product: Mapped[str | None] = mapped_column(String(50), nullable=True)
    access_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    refresh_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    token_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    imported_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    liked_tracks_imported: Mapped[int] = mapped_column(Integer, default=0)
    saved_shows_imported: Mapped[int] = mapped_column(Integer, default=0)
    saved_episodes_imported: Mapped[int] = mapped_column(Integer, default=0)
    recent_tracks_imported: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utcnow,
        onupdate=utcnow,
    )

    user: Mapped["User"] = relationship(back_populates="spotify_link")


class SavedPodcastShow(Base):
    __tablename__ = "saved_podcast_shows"
    __table_args__ = (UniqueConstraint("user_id", "podcast_key", name="uq_saved_podcast_show"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    podcast_key: Mapped[str] = mapped_column(String(255), index=True)
    podcast_payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped["User"] = relationship(back_populates="saved_podcast_shows")


class SavedPodcastEpisode(Base):
    __tablename__ = "saved_podcast_episodes"
    __table_args__ = (UniqueConstraint("user_id", "episode_key", name="uq_saved_podcast_episode"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    episode_key: Mapped[str] = mapped_column(String(255), index=True)
    episode_payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped["User"] = relationship(back_populates="saved_podcast_episodes")
