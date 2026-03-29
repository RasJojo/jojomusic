from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlencode

import httpx

from app.config import settings
from app.metadata import build_track_key
from app.schemas import PodcastEpisodePayload, PodcastPayload, TrackPayload

_SPOTIFY_ACCOUNTS_BASE = "https://accounts.spotify.com"
_SPOTIFY_API_BASE = "https://api.spotify.com/v1"


@dataclass
class SpotifyAuthTokens:
    access_token: str
    refresh_token: str | None
    expires_at: datetime | None


@dataclass
class SpotifyImportBundle:
    profile: dict[str, Any]
    liked_tracks: list[tuple[TrackPayload, datetime | None]]
    saved_shows: list[tuple[PodcastPayload, datetime | None]]
    saved_episodes: list[tuple[PodcastEpisodePayload, datetime | None]]
    recent_tracks: list[tuple[TrackPayload, datetime | None]]


class SpotifyProvider:
    @property
    def missing_configuration(self) -> list[str]:
        missing: list[str] = []
        if not settings.spotify_client_id:
            missing.append("SPOTIFY_CLIENT_ID")
        if not settings.spotify_client_secret:
            missing.append("SPOTIFY_CLIENT_SECRET")
        if not settings.spotify_redirect_uri:
            missing.append("SPOTIFY_REDIRECT_URI")
        return missing

    @property
    def enabled(self) -> bool:
        return not self.missing_configuration

    @property
    def configuration_hint(self) -> str | None:
        if self.enabled:
            return None
        missing = self.missing_configuration
        if not missing:
            return None
        joined = ", ".join(missing)
        return f"Le serveur doit encore définir {joined}."

    def build_authorize_url(self, state: str) -> str:
        params = {
            "client_id": settings.spotify_client_id,
            "response_type": "code",
            "redirect_uri": settings.spotify_redirect_uri,
            "scope": settings.spotify_scopes,
            "state": state,
            "show_dialog": "true",
        }
        return f"{_SPOTIFY_ACCOUNTS_BASE}/authorize?{urlencode(params)}"

    async def exchange_code(self, code: str) -> SpotifyAuthTokens:
        payload = {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": settings.spotify_redirect_uri,
        }
        data = await self._accounts_token_request(payload)
        return SpotifyAuthTokens(
            access_token=data["access_token"],
            refresh_token=data.get("refresh_token"),
            expires_at=_expires_at_from_seconds(data.get("expires_in")),
        )

    async def refresh_access_token(self, refresh_token: str) -> SpotifyAuthTokens:
        payload = {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        }
        data = await self._accounts_token_request(payload)
        return SpotifyAuthTokens(
            access_token=data["access_token"],
            refresh_token=data.get("refresh_token") or refresh_token,
            expires_at=_expires_at_from_seconds(data.get("expires_in")),
        )

    async def fetch_import_bundle(self, access_token: str) -> SpotifyImportBundle:
        profile, liked_tracks, saved_shows, saved_episodes, recent_tracks = await asyncio_gather_dict(
            {
                "profile": self.fetch_profile(access_token),
                "liked_tracks": self._safe_optional_fetch(self.fetch_saved_tracks(access_token)),
                "saved_shows": self._safe_optional_fetch(self.fetch_saved_shows(access_token)),
                "saved_episodes": self._safe_optional_fetch(self.fetch_saved_episodes(access_token)),
                "recent_tracks": self._safe_optional_fetch(self.fetch_recent_tracks(access_token)),
            }
        )
        return SpotifyImportBundle(
            profile=profile,
            liked_tracks=liked_tracks,
            saved_shows=saved_shows,
            saved_episodes=saved_episodes,
            recent_tracks=recent_tracks,
        )

    async def fetch_profile(self, access_token: str) -> dict[str, Any]:
        return await self._api_get("/me", access_token)

    async def fetch_saved_tracks(
        self,
        access_token: str,
    ) -> list[tuple[TrackPayload, datetime | None]]:
        rows = await self._paginate("/me/tracks", access_token)
        tracks: list[tuple[TrackPayload, datetime | None]] = []
        for row in rows:
            track = row.get("track") or {}
            if not track:
                continue
            payload = self._map_track(track)
            if payload is None:
                continue
            tracks.append((payload, _parse_spotify_datetime(row.get("added_at"))))
        return tracks

    async def fetch_saved_shows(
        self,
        access_token: str,
    ) -> list[tuple[PodcastPayload, datetime | None]]:
        rows = await self._paginate("/me/shows", access_token)
        shows: list[tuple[PodcastPayload, datetime | None]] = []
        for row in rows:
            show = row.get("show") or {}
            payload = self._map_show(show)
            if payload is None:
                continue
            shows.append((payload, _parse_spotify_datetime(row.get("added_at"))))
        return shows

    async def fetch_saved_episodes(
        self,
        access_token: str,
    ) -> list[tuple[PodcastEpisodePayload, datetime | None]]:
        rows = await self._paginate("/me/episodes", access_token)
        episodes: list[tuple[PodcastEpisodePayload, datetime | None]] = []
        for row in rows:
            episode = row.get("episode") or {}
            payload = self._map_episode(episode)
            if payload is None:
                continue
            episodes.append((payload, _parse_spotify_datetime(row.get("added_at"))))
        return episodes

    async def fetch_recent_tracks(
        self,
        access_token: str,
    ) -> list[tuple[TrackPayload, datetime | None]]:
        data = await self._api_get("/me/player/recently-played", access_token, params={"limit": 50})
        rows = data.get("items") or []
        recent: list[tuple[TrackPayload, datetime | None]] = []
        for row in rows:
            track = row.get("track") or {}
            payload = self._map_track(track)
            if payload is None:
                continue
            recent.append((payload, _parse_spotify_datetime(row.get("played_at"))))
        return recent

    async def _paginate(self, path: str, access_token: str) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        offset = 0
        limit = 50
        while True:
            try:
                payload = await self._api_get(
                    path,
                    access_token,
                    params={"limit": limit, "offset": offset},
                )
            except httpx.HTTPStatusError as error:
                if error.response.status_code in {401, 403}:
                    break
                raise
            batch = payload.get("items") or []
            items.extend(batch)
            if not payload.get("next"):
                break
            offset += limit
        return items

    async def _safe_optional_fetch(self, coro: Any) -> Any:
        try:
            return await coro
        except httpx.HTTPStatusError as error:
            if error.response.status_code in {401, 403}:
                return []
            raise

    async def _accounts_token_request(self, payload: dict[str, str]) -> dict[str, Any]:
        credentials = f"{settings.spotify_client_id}:{settings.spotify_client_secret}".encode(
            "utf-8"
        )
        auth_header = base64.b64encode(credentials).decode("ascii")
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{_SPOTIFY_ACCOUNTS_BASE}/api/token",
                data=payload,
                headers={"Authorization": f"Basic {auth_header}"},
            )
            response.raise_for_status()
        return response.json()

    async def _api_get(
        self,
        path: str,
        access_token: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(
                f"{_SPOTIFY_API_BASE}{path}",
                params=params,
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
        return response.json()

    def _map_track(self, track: dict[str, Any]) -> TrackPayload | None:
        title = (track.get("name") or "").strip()
        artists = [
            artist.get("name", "").strip()
            for artist in track.get("artists") or []
            if artist.get("name")
        ]
        if not title or not artists:
            return None
        album = track.get("album") or {}
        artwork = _best_image_url(album.get("images"))
        artist_name = ", ".join(artists)
        return TrackPayload(
            track_key=build_track_key(artist_name, title),
            title=title,
            artist=artist_name,
            album=(album.get("name") or "").strip() or None,
            artwork_url=artwork,
            duration_ms=track.get("duration_ms"),
            provider="spotify",
            external_id=track.get("id"),
            preview_url=track.get("preview_url"),
        )

    def _map_show(self, show: dict[str, Any]) -> PodcastPayload | None:
        title = (show.get("name") or "").strip()
        if not title:
            return None
        return PodcastPayload(
            podcast_key=f"spotify-show-{show.get('id')}",
            title=title,
            publisher=(show.get("publisher") or "Spotify").strip(),
            description=(show.get("description") or "").strip() or None,
            artwork_url=_best_image_url(show.get("images")),
            external_url=(show.get("external_urls") or {}).get("spotify"),
            episode_count=show.get("total_episodes"),
        )

    def _map_episode(self, episode: dict[str, Any]) -> PodcastEpisodePayload | None:
        title = (episode.get("name") or "").strip()
        show = episode.get("show") or {}
        if not title:
            return None
        return PodcastEpisodePayload(
            episode_key=f"spotify-episode-{episode.get('id')}",
            podcast_title=(show.get("name") or "Spotify").strip(),
            title=title,
            publisher=(show.get("publisher") or "").strip() or None,
            description=(episode.get("description") or "").strip() or None,
            artwork_url=_best_image_url(episode.get("images") or show.get("images")),
            external_url=(episode.get("external_urls") or {}).get("spotify"),
            duration_seconds=_duration_ms_to_seconds(episode.get("duration_ms")),
            published_at=_parse_spotify_datetime(episode.get("release_date")),
        )


async def asyncio_gather_dict(tasks: dict[str, Any]) -> tuple[Any, ...]:
    import asyncio

    keys = list(tasks.keys())
    values = await asyncio.gather(*tasks.values())
    return tuple(values[keys.index(key)] for key in keys)


def _expires_at_from_seconds(value: Any) -> datetime | None:
    if value is None:
        return None
    try:
        seconds = int(value)
    except (TypeError, ValueError):
        return None
    return datetime.now(timezone.utc) + timedelta(seconds=seconds)


def _best_image_url(images: list[dict[str, Any]] | None) -> str | None:
    if not images:
        return None
    for image in images:
        url = image.get("url")
        if url:
            return url
    return None


def _parse_spotify_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    if len(value) == 4 and value.isdigit():
        return datetime(int(value), 1, 1, tzinfo=timezone.utc)
    if len(value) == 7 and value[4] == "-":
        try:
            return datetime(int(value[:4]), int(value[5:7]), 1, tzinfo=timezone.utc)
        except ValueError:
            return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _duration_ms_to_seconds(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return round(int(value) / 1000)
    except (TypeError, ValueError):
        return None
