from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime, timedelta
from difflib import SequenceMatcher
from uuid import uuid4

import httpx
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.responses import HTMLResponse
from sqlalchemy import delete, desc, select
from sqlalchemy.orm import Session, selectinload

from app.config import settings
from app.db import Base, engine, get_db
from app.deps import get_current_user
from app.metadata import (
    ITunesProvider,
    LastFmProvider,
    MusicBrainzProvider,
    build_album_key,
    build_artist_key,
    build_track_key,
)
from app.models import PlaybackEvent, Playlist, PlaylistTrack, SavedTrack, User, utcnow
from app.models import SavedPodcastEpisode, SavedPodcastShow, SpotifyAccountLink
from app.recommendations import build_generated_playlists, build_recommendations
from app.schemas import (
    AlbumPayload,
    AlbumDetailsResponse,
    BrowseCategoryPayload,
    BrowseCategoryResponse,
    ArtistDetailsResponse,
    ArtistPayload,
    AuthResponse,
    GeneratedPlaylistPayload,
    HomeResponse,
    LyricsResponse,
    PlaybackEventCreate,
    PlaybackEventOut,
    PlaylistCreate,
    PlaylistOut,
    PlaylistTrackCreate,
    PodcastDetailsResponse,
    PodcastEpisodePayload,
    PodcastPayload,
    ResolveTrackRequest,
    ResolvedStream,
    SearchResponse,
    SpotifyConnectResponse,
    SpotifyIntegrationStatus,
    TrackPayload,
    UserCreate,
    UserLogin,
    UserOut,
)
from app.security import create_access_token, create_token, decode_access_token, hash_password, verify_password
from app.spotify import SpotifyImportBundle, SpotifyProvider

app = FastAPI(title=settings.app_name, version="0.1.0")
logger = logging.getLogger(__name__)
metadata_provider = ITunesProvider()
lastfm_provider = LastFmProvider()
musicbrainz_provider = MusicBrainzProvider()
spotify_provider = SpotifyProvider()
browse_artwork_cache: dict[str, str | None] = {}
resolved_stream_cache: dict[str, tuple[datetime, ResolvedStream]] = {}

BROWSE_CATEGORIES = [
    BrowseCategoryPayload(
        category_id="new-releases",
        title="Nouveautés",
        subtitle="Dernières sorties, singles frais et nouveautés à lancer",
        color_hex="#C04A23",
        search_seed="new music friday",
    ),
    BrowseCategoryPayload(
        category_id="pop-hits",
        title="Pop",
        subtitle="Hits immédiats, refrains massifs et grosses sorties",
        color_hex="#8B2877",
        search_seed="pop hits",
    ),
    BrowseCategoryPayload(
        category_id="rap-hiphop",
        title="Rap & Hip-Hop",
        subtitle="Rap FR, US, trap et gros titres du moment",
        color_hex="#B1591E",
        search_seed="rap hip hop",
    ),
    BrowseCategoryPayload(
        category_id="afro-vibes",
        title="Afro",
        subtitle="Afrobeats, amapiano et chaleur instantanée",
        color_hex="#7A5A00",
        search_seed="afrobeats amapiano",
    ),
    BrowseCategoryPayload(
        category_id="mada-vibes",
        title="Madagascar",
        subtitle="Mada vibes, rap local, salegy et scène malgache",
        color_hex="#007A62",
        search_seed="music malagasy",
    ),
    BrowseCategoryPayload(
        category_id="chill-mood",
        title="Chill",
        subtitle="Calme, focus, late night et textures douces",
        color_hex="#274A9A",
        search_seed="chill hits",
    ),
    BrowseCategoryPayload(
        category_id="workout-energy",
        title="Workout",
        subtitle="Énergie, cardio, motivation et percussions lourdes",
        color_hex="#1E8554",
        search_seed="workout mix",
    ),
    BrowseCategoryPayload(
        category_id="love-songs",
        title="Love",
        subtitle="Slow jams, pop sentimentale et titres à émotions",
        color_hex="#A02458",
        search_seed="love songs rnb",
    ),
    BrowseCategoryPayload(
        category_id="podcasts-editorial",
        title="Podcasts musicaux",
        subtitle="Culture, interviews, société et épisodes longs",
        color_hex="#5A276F",
        search_seed="podcast francais",
    ),
]

BROWSE_ARTWORK_QUERIES = {
    "new-releases": "new music friday playlist cover",
    "pop-hits": "pop hits playlist cover",
    "rap-hiphop": "rap hip hop playlist cover",
    "afro-vibes": "afrobeats playlist cover",
    "mada-vibes": "music malagasy cover",
    "chill-mood": "chill mix playlist cover",
    "workout-energy": "workout playlist cover",
    "love-songs": "love songs playlist cover",
    "podcasts-editorial": "podcast microphone studio",
}


def _merge_track(existing: TrackPayload, incoming: TrackPayload) -> TrackPayload:
    data = existing.model_dump()
    other = incoming.model_dump()
    for key in ("album", "artwork_url", "artist_image_url", "duration_ms", "preview_url", "external_id"):
        if not data.get(key) and other.get(key):
            data[key] = other[key]
    if data.get("provider") == "lastfm" and other.get("provider") != "lastfm":
        data["provider"] = other["provider"]
    return TrackPayload.model_validate(data)


def _merge_artist(existing: ArtistPayload, incoming: ArtistPayload) -> ArtistPayload:
    data = existing.model_dump()
    other = incoming.model_dump()
    for key in ("image_url", "external_id", "url", "listeners", "summary"):
        if not data.get(key) and other.get(key):
            data[key] = other[key]
    if data.get("provider") == "lastfm" and other.get("provider") != "lastfm":
        data["provider"] = other["provider"]
    return ArtistPayload.model_validate(data)


def _merge_album(existing: AlbumPayload, incoming: AlbumPayload) -> AlbumPayload:
    data = existing.model_dump()
    other = incoming.model_dump()
    for key in ("artwork_url", "external_id", "summary", "release_date", "track_count"):
        if not data.get(key) and other.get(key):
            data[key] = other[key]
    if data.get("provider") == "lastfm" and other.get("provider") != "lastfm":
        data["provider"] = other["provider"]
    return AlbumPayload.model_validate(data)


def _dedupe_tracks(tracks: list[TrackPayload], limit: int) -> list[TrackPayload]:
    merged: dict[str, TrackPayload] = {}
    ordered_keys: list[str] = []
    for track in tracks:
        if track.track_key in merged:
            merged[track.track_key] = _merge_track(merged[track.track_key], track)
        else:
            merged[track.track_key] = track
            ordered_keys.append(track.track_key)
        if len(ordered_keys) >= limit and track.track_key not in merged:
            break
    return [merged[key] for key in ordered_keys][:limit]


def _dedupe_artists(artists: list[ArtistPayload], limit: int) -> list[ArtistPayload]:
    merged: dict[str, ArtistPayload] = {}
    ordered_keys: list[str] = []
    for artist in artists:
        if artist.artist_key in merged:
            merged[artist.artist_key] = _merge_artist(merged[artist.artist_key], artist)
        else:
            merged[artist.artist_key] = artist
            ordered_keys.append(artist.artist_key)
    return [merged[key] for key in ordered_keys][:limit]


def _dedupe_albums(albums: list[AlbumPayload], limit: int) -> list[AlbumPayload]:
    merged: dict[str, AlbumPayload] = {}
    ordered_keys: list[str] = []
    for album in albums:
        if album.album_key in merged:
            merged[album.album_key] = _merge_album(merged[album.album_key], album)
        else:
            merged[album.album_key] = album
            ordered_keys.append(album.album_key)
    return [merged[key] for key in ordered_keys][:limit]


async def _hydrate_track_visuals(
    tracks: list[TrackPayload],
    *,
    artist_lookup: dict[str, ArtistPayload] | None = None,
    fallback_artist_image: str | None = None,
    thumbnail_limit: int = 4,
) -> list[TrackPayload]:
    if not tracks:
        return tracks

    hydrated: list[TrackPayload] = []
    thumbnail_queries: list[tuple[int, str]] = []
    for index, track in enumerate(tracks):
        artist_image_url = track.artist_image_url
        if not artist_image_url and artist_lookup is not None:
            matched_artist = artist_lookup.get(build_artist_key(track.artist))
            if matched_artist is not None and matched_artist.image_url:
                artist_image_url = matched_artist.image_url
        if not artist_image_url and fallback_artist_image:
            artist_image_url = fallback_artist_image

        hydrated_track = (
            track.model_copy(update={"artist_image_url": artist_image_url})
            if artist_image_url and artist_image_url != track.artist_image_url
            else track
        )
        hydrated.append(hydrated_track)

        if (
            index < thumbnail_limit
            and not hydrated_track.artwork_url
            and not hydrated_track.artist_image_url
        ):
            thumbnail_queries.append((index, f"{track.artist} - {track.title}"))

    if thumbnail_queries:
        thumbnails = await asyncio.gather(
            *[_resolve_thumbnail(query) for _, query in thumbnail_queries]
        )
        for (index, _), thumbnail in zip(thumbnail_queries, thumbnails, strict=False):
            if thumbnail:
                hydrated[index] = hydrated[index].model_copy(update={"artwork_url": thumbnail})

    return hydrated


def _resolved_stream_cache_key(payload: ResolveTrackRequest, query: str) -> str:
    if payload.track is not None:
        return payload.track.track_key
    return "query:" + re.sub(r"\s+", " ", query.strip().lower())


def _find_best_artist_match(query: str, artists: list[ArtistPayload]) -> ArtistPayload | None:
    query_key = build_artist_key(query)
    for artist in artists:
        if artist.artist_key == query_key:
            return artist
    for artist in artists:
        if query_key and query_key in artist.artist_key:
            return artist
    return artists[0] if artists else None


def _artist_match_score(query: str, artist: ArtistPayload) -> tuple[int, int, int, int, int, int]:
    best = max((_single_artist_match_score(candidate, artist) for candidate in _artist_query_variants(query)), default=(0, 0, 0, 0))
    return (*best, artist.listeners or 0, -len(artist.name))


def _artist_query_variants(query: str) -> list[str]:
    variants: list[str] = []
    seen: set[str] = set()
    parts = [query.strip()]
    parts.extend(
        part.strip(" -")
        for part in re.split(r"\s+(?:feat\.?|ft\.?|with|x)\s+|,|&|/", query, flags=re.IGNORECASE)
    )
    for part in parts:
        normalized = part.strip()
        if len(normalized) < 2:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        variants.append(normalized)
    return variants


def _single_artist_match_score(query: str, artist: ArtistPayload) -> tuple[int, int, int, int]:
    query_key = build_artist_key(query)
    if not query_key:
        return (0, 0, 0, 0)

    exact = 1 if artist.artist_key == query_key else 0
    prefix = 1 if artist.artist_key.startswith(query_key) else 0
    contains = 1 if query_key in artist.artist_key else 0
    similarity = int(SequenceMatcher(None, query_key, artist.artist_key).ratio() * 1000)
    return (exact, prefix, contains, similarity)


def _artist_matches_query(query: str, artist: ArtistPayload) -> bool:
    exact, prefix, contains, similarity = max(
        (_single_artist_match_score(candidate, artist) for candidate in _artist_query_variants(query)),
        default=(0, 0, 0, 0),
    )
    return bool(exact or prefix or contains or similarity >= 820)


async def _resolve_thumbnail(query: str) -> str | None:
    try:
        async with httpx.AsyncClient(timeout=settings.resolver_timeout_seconds) as client:
            response = await client.post(
                f"{settings.resolver_api_url}/api/v1/resolve",
                json={"query": query},
            )
            if response.status_code >= 400:
                return None
            return response.json().get("thumbnail_url")
    except Exception:
        return None


def _browse_category_by_id(category_id: str) -> BrowseCategoryPayload | None:
    return next((category for category in BROWSE_CATEGORIES if category.category_id == category_id), None)


async def _build_browse_categories() -> list[BrowseCategoryPayload]:
    categories = list(BROWSE_CATEGORIES)
    missing = [category for category in categories if category.category_id not in browse_artwork_cache]
    if missing:
        thumbnails = await asyncio.gather(
            *[
                _resolve_thumbnail(BROWSE_ARTWORK_QUERIES.get(category.category_id, category.search_seed))
                for category in missing
            ]
        )
        for category, thumbnail in zip(missing, thumbnails, strict=False):
            browse_artwork_cache[category.category_id] = thumbnail

    return [
        category.model_copy(update={"artwork_url": browse_artwork_cache.get(category.category_id)})
        if browse_artwork_cache.get(category.category_id)
        else category
        for category in categories
    ]


async def _build_featured_podcasts(limit: int = 6) -> list[PodcastPayload]:
    podcasts: dict[str, PodcastPayload] = {}
    seeds = [
        "podcast musique",
        "rap podcast",
        "interview artiste podcast",
        "comedy podcast",
        "business podcast",
        "society podcast",
    ]
    for seed in seeds:
        try:
            results = await metadata_provider.search_podcasts(seed, limit=3)
        except Exception:
            logger.exception("featured podcasts lookup failed for seed %s", seed)
            continue
        for podcast in results:
            if podcast.podcast_key not in podcasts:
                podcasts[podcast.podcast_key] = podcast
            if len(podcasts) >= limit:
                return list(podcasts.values())
    return list(podcasts.values())


async def _safe_async(label: str, awaitable, default):
    try:
        return await awaitable
    except Exception:
        logger.exception("%s failed", label)
        return default


def _spotify_status_payload(link: SpotifyAccountLink | None, shows: list[SavedPodcastShow]) -> SpotifyIntegrationStatus:
    if link is None:
        return SpotifyIntegrationStatus(
            configured=spotify_provider.enabled,
            configuration_hint=spotify_provider.configuration_hint,
        )
    return SpotifyIntegrationStatus(
        configured=spotify_provider.enabled,
        configuration_hint=spotify_provider.configuration_hint,
        connected=True,
        spotify_user_id=link.spotify_user_id,
        display_name=link.display_name,
        email=link.email,
        avatar_url=link.avatar_url,
        country=link.country,
        product=link.product,
        imported_at=link.imported_at,
        liked_tracks_imported=link.liked_tracks_imported,
        saved_shows_imported=link.saved_shows_imported,
        saved_episodes_imported=link.saved_episodes_imported,
        recent_tracks_imported=link.recent_tracks_imported,
        saved_shows=[PodcastPayload.model_validate(row.podcast_payload) for row in shows],
    )


async def _ensure_spotify_access_token(link: SpotifyAccountLink) -> tuple[str, str | None, datetime | None]:
    if (
        link.access_token
        and link.token_expires_at
        and link.token_expires_at > utcnow() + timedelta(minutes=2)
    ):
        return link.access_token, link.refresh_token, link.token_expires_at

    if not link.refresh_token:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Spotify refresh token missing",
        )

    tokens = await spotify_provider.refresh_access_token(link.refresh_token)
    return tokens.access_token, tokens.refresh_token, tokens.expires_at


def _spotify_callback_html(success: bool, message: str) -> HTMLResponse:
    accent = "#61F5B9" if success else "#FF6B6B"
    title = "Spotify import termine" if success else "Spotify import impossible"
    html = f"""
    <!doctype html>
    <html lang="fr">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{title}</title>
        <style>
          body {{
            margin: 0;
            background: linear-gradient(180deg, #132d2b 0%, #081717 60%, #041010 100%);
            color: #f4fffc;
            font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }}
          .card {{
            width: min(560px, calc(100vw - 48px));
            margin: 10vh auto;
            padding: 28px;
            border-radius: 28px;
            background: rgba(12, 23, 24, 0.86);
            border: 1px solid rgba(255, 255, 255, 0.1);
            box-shadow: 0 20px 50px rgba(0,0,0,0.35);
          }}
          .badge {{
            display: inline-block;
            padding: 8px 12px;
            border-radius: 999px;
            background: rgba(0,0,0,0.2);
            color: {accent};
            border: 1px solid rgba(255,255,255,0.08);
            font-weight: 700;
          }}
          h1 {{ margin: 18px 0 12px; font-size: 32px; }}
          p {{ line-height: 1.5; color: #c9ddd8; }}
        </style>
      </head>
      <body>
        <div class="card">
          <div class="badge">JojoMusique × Spotify</div>
          <h1>{title}</h1>
          <p>{message}</p>
          <p>Tu peux fermer cette page et revenir dans JojoMusique.</p>
        </div>
      </body>
    </html>
    """
    return HTMLResponse(content=html)


def _spotify_http_error_message(error: httpx.HTTPError) -> str:
    if isinstance(error, httpx.HTTPStatusError):
        status_code = error.response.status_code
        request_url = str(error.request.url)
        if status_code == 403 and request_url.endswith("/me"):
            return (
                "Spotify a bien autorisé la connexion, mais la Web API refuse encore ce compte. "
                "Vérifie dans Spotify Developer Dashboard > User Management que le compte Spotify utilisé "
                "est bien ajouté aux utilisateurs autorisés en Development Mode. Vérifie aussi que le compte "
                "Spotify utilisé et le compte propriétaire de l'app sont bien Premium, et que l'app a été "
                "créée avec l'API \"Web API\" sélectionnée dans le dashboard Spotify."
            )
        if status_code == 403:
            return (
                "Spotify a refusé une partie des données demandées. Vérifie les autorisations du compte "
                "utilisé et les restrictions Development Mode dans le dashboard Spotify."
            )
    return f"Impossible d'importer les données Spotify: {error}."


def _upsert_saved_track(
    db: Session,
    *,
    user_id: str,
    track: TrackPayload,
    created_at: datetime | None,
) -> None:
    existing = db.scalar(
        select(SavedTrack).where(
            SavedTrack.user_id == user_id,
            SavedTrack.track_key == track.track_key,
        )
    )
    if existing is not None:
        existing.track_payload = track.model_dump()
        if created_at is not None:
            existing.created_at = created_at
        return

    db.add(
        SavedTrack(
            id=str(uuid4()),
            user_id=user_id,
            track_key=track.track_key,
            track_payload=track.model_dump(),
            created_at=created_at or utcnow(),
        )
    )


def _import_spotify_bundle(
    db: Session,
    *,
    user: User,
    link: SpotifyAccountLink,
    bundle: SpotifyImportBundle,
    access_token: str,
    refresh_token: str | None,
    token_expires_at: datetime | None,
) -> None:
    link.spotify_user_id = bundle.profile["id"]
    link.display_name = bundle.profile.get("display_name")
    link.email = bundle.profile.get("email")
    link.avatar_url = next((image.get("url") for image in bundle.profile.get("images") or [] if image.get("url")), None)
    link.country = bundle.profile.get("country")
    link.product = bundle.profile.get("product")
    link.access_token = access_token
    if refresh_token:
        link.refresh_token = refresh_token
    link.token_expires_at = token_expires_at
    link.imported_at = utcnow()
    link.liked_tracks_imported = len(bundle.liked_tracks)
    link.saved_shows_imported = len(bundle.saved_shows)
    link.saved_episodes_imported = len(bundle.saved_episodes)
    link.recent_tracks_imported = len(bundle.recent_tracks)

    for track, added_at in bundle.liked_tracks:
        _upsert_saved_track(db, user_id=user.id, track=track, created_at=added_at)

    db.execute(delete(SavedPodcastShow).where(SavedPodcastShow.user_id == user.id))
    for podcast, added_at in bundle.saved_shows:
        db.add(
            SavedPodcastShow(
                id=str(uuid4()),
                user_id=user.id,
                podcast_key=podcast.podcast_key,
                podcast_payload=podcast.model_dump(),
                created_at=added_at or utcnow(),
            )
        )

    db.execute(delete(SavedPodcastEpisode).where(SavedPodcastEpisode.user_id == user.id))
    for episode, added_at in bundle.saved_episodes:
        db.add(
            SavedPodcastEpisode(
                id=str(uuid4()),
                user_id=user.id,
                episode_key=episode.episode_key,
                episode_payload=episode.model_dump(),
                created_at=added_at or utcnow(),
            )
        )

    db.execute(
        delete(PlaybackEvent).where(
            PlaybackEvent.user_id == user.id,
            PlaybackEvent.event_type == "spotify_import_recent",
        )
    )
    for track, played_at in bundle.recent_tracks:
        db.add(
            PlaybackEvent(
                id=str(uuid4()),
                user_id=user.id,
                track_key=track.track_key,
                event_type="spotify_import_recent",
                listened_ms=track.duration_ms or 0,
                completion_ratio=1.0,
                track_payload=track.model_dump(),
                created_at=played_at or utcnow(),
            )
        )

    db.add(link)
    db.commit()


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/api/v1/auth/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(payload: UserCreate, db: Session = Depends(get_db)) -> AuthResponse:
    existing = db.scalar(select(User).where(User.email == payload.email.lower()))
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already in use")

    user = User(
        id=str(uuid4()),
        email=payload.email.lower(),
        name=payload.name.strip(),
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id)
    return AuthResponse(access_token=token, user=UserOut.model_validate(user))


@app.post("/api/v1/auth/login", response_model=AuthResponse)
def login(payload: UserLogin, db: Session = Depends(get_db)) -> AuthResponse:
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    token = create_access_token(user.id)
    return AuthResponse(access_token=token, user=UserOut.model_validate(user))


@app.get("/api/v1/auth/me", response_model=UserOut)
def me(current_user: User = Depends(get_current_user)) -> UserOut:
    return UserOut.model_validate(current_user)


@app.get("/api/v1/me/integrations/spotify", response_model=SpotifyIntegrationStatus)
def spotify_integration_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SpotifyIntegrationStatus:
    link = db.scalar(select(SpotifyAccountLink).where(SpotifyAccountLink.user_id == current_user.id))
    shows = db.scalars(
        select(SavedPodcastShow)
        .where(SavedPodcastShow.user_id == current_user.id)
        .order_by(desc(SavedPodcastShow.created_at))
        .limit(6)
    ).all()
    return _spotify_status_payload(link, shows)


@app.get("/api/v1/me/integrations/spotify/connect", response_model=SpotifyConnectResponse)
def spotify_connect(
    current_user: User = Depends(get_current_user),
) -> SpotifyConnectResponse:
    if not spotify_provider.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Spotify integration is not configured",
        )
    state = create_token({"sub": current_user.id, "kind": "spotify_link"}, 15)
    return SpotifyConnectResponse(authorize_url=spotify_provider.build_authorize_url(state))


@app.post("/api/v1/me/integrations/spotify/sync", response_model=SpotifyIntegrationStatus)
async def spotify_sync(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SpotifyIntegrationStatus:
    if not spotify_provider.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Spotify integration is not configured",
        )

    link = db.scalar(select(SpotifyAccountLink).where(SpotifyAccountLink.user_id == current_user.id))
    if link is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Spotify account not linked")

    access_token, refresh_token, token_expires_at = await _ensure_spotify_access_token(link)
    bundle = await spotify_provider.fetch_import_bundle(access_token)
    _import_spotify_bundle(
        db,
        user=current_user,
        link=link,
        bundle=bundle,
        access_token=access_token,
        refresh_token=refresh_token,
        token_expires_at=token_expires_at,
    )

    db.refresh(link)
    shows = db.scalars(
        select(SavedPodcastShow)
        .where(SavedPodcastShow.user_id == current_user.id)
        .order_by(desc(SavedPodcastShow.created_at))
        .limit(6)
    ).all()
    return _spotify_status_payload(link, shows)


@app.delete("/api/v1/me/integrations/spotify", status_code=status.HTTP_204_NO_CONTENT)
def spotify_disconnect(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    link = db.scalar(select(SpotifyAccountLink).where(SpotifyAccountLink.user_id == current_user.id))
    if link is not None:
        db.delete(link)
    db.execute(delete(SavedPodcastShow).where(SavedPodcastShow.user_id == current_user.id))
    db.execute(delete(SavedPodcastEpisode).where(SavedPodcastEpisode.user_id == current_user.id))
    db.commit()


@app.get("/api/v1/integrations/spotify/callback", response_class=HTMLResponse)
async def spotify_callback(
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    db: Session = Depends(get_db),
) -> HTMLResponse:
    if error:
        return _spotify_callback_html(False, f"Spotify a refusé la connexion: {error}.")
    if not spotify_provider.enabled:
        return _spotify_callback_html(False, "Le backend JojoMusique n'est pas configuré pour Spotify.")
    if not code or not state:
        return _spotify_callback_html(False, "Le callback Spotify est incomplet.")

    try:
        payload = decode_access_token(state)
    except Exception:
        return _spotify_callback_html(False, "Le state Spotify est invalide ou expiré.")

    if payload.get("kind") != "spotify_link":
        return _spotify_callback_html(False, "Le state Spotify ne correspond pas à une liaison valide.")

    user = db.get(User, payload.get("sub"))
    if user is None:
        return _spotify_callback_html(False, "Le compte JojoMusique lié à cette importation est introuvable.")

    try:
        tokens = await spotify_provider.exchange_code(code)
        bundle = await spotify_provider.fetch_import_bundle(tokens.access_token)
    except httpx.HTTPError as exc:
        return _spotify_callback_html(False, _spotify_http_error_message(exc))

    existing_same_spotify = db.scalar(
        select(SpotifyAccountLink).where(
            SpotifyAccountLink.spotify_user_id == bundle.profile["id"],
            SpotifyAccountLink.user_id != user.id,
        )
    )
    if existing_same_spotify is not None:
        return _spotify_callback_html(
            False,
            "Ce compte Spotify est déjà lié à un autre compte JojoMusique.",
        )

    link = db.scalar(select(SpotifyAccountLink).where(SpotifyAccountLink.user_id == user.id))
    if link is None:
        link = SpotifyAccountLink(
            id=str(uuid4()),
            user_id=user.id,
            spotify_user_id=bundle.profile["id"],
        )

    _import_spotify_bundle(
        db,
        user=user,
        link=link,
        bundle=bundle,
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        token_expires_at=tokens.expires_at,
    )
    return _spotify_callback_html(
        True,
        (
            f'Import terminé: {len(bundle.liked_tracks)} titres likés, '
            f'{len(bundle.saved_shows)} shows et {len(bundle.saved_episodes)} épisodes sauvegardés.'
        ),
    )


@app.get("/api/v1/search", response_model=SearchResponse)
async def search(query: str, limit: int = 20) -> SearchResponse:
    artist_queries = _artist_query_variants(query)
    tracks, lastfm_artist_batches, itunes_artist_batches, musicbrainz_artists, albums, musicbrainz_albums, podcasts = await asyncio.gather(
        metadata_provider.search_tracks(query, limit=limit),
        asyncio.gather(*[lastfm_provider.search_artists(candidate, limit=min(limit, 5)) for candidate in artist_queries]),
        asyncio.gather(*[metadata_provider.search_artists(candidate, limit=min(limit, 5)) for candidate in artist_queries]),
        musicbrainz_provider.search_artists(query, limit=min(limit, 6)),
        metadata_provider.search_albums(query, limit=min(limit, 8)),
        musicbrainz_provider.search_albums(query, limit=min(limit, 8)),
        metadata_provider.search_podcasts(query, limit=min(limit, 6)),
    )

    lastfm_artists = [artist for batch in lastfm_artist_batches for artist in batch]
    itunes_artists = [artist for batch in itunes_artist_batches for artist in batch]
    artists = [
        artist
        for artist in _dedupe_artists([*lastfm_artists, *itunes_artists, *musicbrainz_artists], limit=min(limit * 3, 24))
        if _artist_matches_query(query, artist)
    ]
    artists = sorted(
        artists,
        key=lambda artist: _artist_match_score(query, artist),
        reverse=True,
    )[: min(limit, 6)]
    artists_missing_images = [artist for artist in artists[:4] if not artist.image_url]
    if artists_missing_images:
        enriched_artists = await asyncio.gather(
            *[musicbrainz_provider.artist_info(artist.name) for artist in artists_missing_images]
        )
        enriched_by_key = {
            artist.artist_key: artist
            for artist in enriched_artists
            if artist is not None
        }
        artists = [
            _merge_artist(artist, enriched_by_key[artist.artist_key])
            if artist.artist_key in enriched_by_key
            else artist
            for artist in artists
        ]
    thumbnail_missing = [artist for artist in artists[:3] if not artist.image_url]
    if thumbnail_missing:
        thumbnails = await asyncio.gather(
            *[_resolve_thumbnail(f"{artist.name} official music") for artist in thumbnail_missing]
        )
        thumbnail_by_key = {
            artist.artist_key: thumbnail
            for artist, thumbnail in zip(thumbnail_missing, thumbnails, strict=False)
            if thumbnail
        }
        artists = [
            artist.model_copy(update={"image_url": thumbnail_by_key[artist.artist_key]})
            if artist.artist_key in thumbnail_by_key
            else artist
            for artist in artists
        ]
    artist_lookup = {artist.artist_key: artist for artist in artists}
    best_artist = _find_best_artist_match(query, artists)
    if best_artist is not None:
        artist_tracks, artist_albums, artist_specific_itunes_albums = await asyncio.gather(
            lastfm_provider.top_tracks_for_artist(best_artist.name, limit=min(limit, 8)),
            musicbrainz_provider.albums_for_artist(best_artist.name, limit=min(limit, 8)),
            metadata_provider.albums_for_artist(best_artist.name, limit=min(limit, 8)),
        )
        tracks = _dedupe_tracks([*artist_tracks, *tracks], limit=limit)
        specific_albums = _dedupe_albums(
            [*artist_albums, *artist_specific_itunes_albums],
            limit=min(limit, 10),
        )
        if specific_albums:
            albums = specific_albums
        else:
            albums = []
    else:
        tracks = _dedupe_tracks(tracks, limit=limit)
        albums = _dedupe_albums([*musicbrainz_albums, *albums], limit=min(limit, 10))
    tracks = await _hydrate_track_visuals(
        tracks,
        artist_lookup=artist_lookup,
        fallback_artist_image=best_artist.image_url if best_artist is not None else None,
        thumbnail_limit=min(6, limit),
    )
    return SearchResponse(
        query=query,
        artists=artists,
        tracks=tracks,
        albums=albums,
        podcasts=podcasts,
    )


@app.get("/api/v1/artists/details", response_model=ArtistDetailsResponse)
async def artist_details(name: str) -> ArtistDetailsResponse:
    info, musicbrainz_info, lastfm_tracks, itunes_tracks, similar_artists, musicbrainz_albums, lastfm_albums, itunes_albums = await asyncio.gather(
        lastfm_provider.artist_info(name),
        musicbrainz_provider.artist_info(name),
        lastfm_provider.top_tracks_for_artist(name, limit=10),
        metadata_provider.top_for_artist(name, limit=10),
        lastfm_provider.similar_artists(name, limit=8),
        musicbrainz_provider.albums_for_artist(name, limit=8),
        lastfm_provider.top_albums_for_artist(name, limit=8),
        metadata_provider.albums_for_artist(name, limit=8),
    )

    artist = None
    if info is not None and musicbrainz_info is not None:
        artist = _merge_artist(info, musicbrainz_info)
    else:
        artist = info or musicbrainz_info
    if artist is None:
        fallback_artists = await lastfm_provider.search_artists(name, limit=3)
        artist = _find_best_artist_match(name, fallback_artists)
    if artist is None:
        fallback_artists = await musicbrainz_provider.search_artists(name, limit=3)
        artist = _find_best_artist_match(name, fallback_artists)
    if artist is None:
        artist = ArtistPayload(
            artist_key=build_artist_key(name),
            name=name,
            provider="internal",
        )

    top_tracks = _dedupe_tracks([*lastfm_tracks, *itunes_tracks], limit=12)
    top_albums = _dedupe_albums(
        [*itunes_albums, *musicbrainz_albums, *lastfm_albums],
        limit=32,
    )
    top_albums.sort(
        key=lambda album: (
            album.release_date is not None,
            album.release_date or utcnow().replace(year=1900),
        ),
        reverse=True,
    )
    top_albums = top_albums[:8]
    similar_artists = _dedupe_artists(similar_artists, limit=8)

    if artist.image_url is None and top_tracks:
        fallback_queries = [
            f"{top_tracks[0].artist} - {top_tracks[0].title}",
            f"{artist.name} official music",
            artist.name,
        ]
        for fallback_query in fallback_queries:
            thumbnail_url = await _resolve_thumbnail(fallback_query)
            if thumbnail_url:
                artist = artist.model_copy(update={"image_url": thumbnail_url})
                break
        else:
            artist = artist.model_copy(update={"image_url": top_tracks[0].artwork_url})
    top_tracks = await _hydrate_track_visuals(
        top_tracks,
        artist_lookup={artist.artist_key: artist},
        fallback_artist_image=artist.image_url,
        thumbnail_limit=6,
    )

    return ArtistDetailsResponse(
        artist=artist,
        top_tracks=top_tracks,
        top_albums=top_albums,
        similar_artists=similar_artists,
    )


@app.get("/api/v1/albums/details", response_model=AlbumDetailsResponse)
async def album_details(
    artist: str,
    title: str,
    external_id: str | None = None,
) -> AlbumDetailsResponse:
    musicbrainz_album, lastfm_result, itunes_result = await asyncio.gather(
        musicbrainz_provider.album_details(artist, title),
        lastfm_provider.album_details(artist, title),
        metadata_provider.album_details(
            artist=artist,
            title=title,
            external_id=external_id,
        ),
    )

    resolved_lastfm_album, resolved_lastfm_tracks = lastfm_result
    resolved_itunes_album, resolved_itunes_tracks = itunes_result

    combined_albums = [
        album
        for album in (musicbrainz_album, resolved_lastfm_album, resolved_itunes_album)
        if album is not None
    ]
    if combined_albums:
        album = _dedupe_albums(combined_albums, limit=1)[0]
    else:
        album = AlbumPayload(
            album_key=build_album_key(artist, title),
            title=title,
            artist=artist,
        )

    tracks = _dedupe_tracks(
        [*resolved_lastfm_tracks, *resolved_itunes_tracks],
        limit=20,
    )
    if album.artwork_url is None and tracks:
        album = album.model_copy(update={"artwork_url": tracks[0].artwork_url})
    if album.track_count is None and tracks:
        album = album.model_copy(update={"track_count": len(tracks)})

    return AlbumDetailsResponse(album=album, tracks=tracks)


@app.get("/api/v1/browse/categories", response_model=list[BrowseCategoryPayload])
async def browse_categories() -> list[BrowseCategoryPayload]:
    return await _build_browse_categories()


@app.get("/api/v1/browse/categories/{category_id}", response_model=BrowseCategoryResponse)
async def browse_category(category_id: str) -> BrowseCategoryResponse:
    categories = await _build_browse_categories()
    category = next((item for item in categories if item.category_id == category_id), None)
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Browse category not found")

    search_results = await search(category.search_seed, limit=12)
    return BrowseCategoryResponse(
        category=category,
        tracks=search_results.tracks[:12],
        artists=search_results.artists[:8],
        albums=search_results.albums[:8],
        podcasts=search_results.podcasts[:6],
    )


@app.get("/api/v1/podcasts/search", response_model=list[PodcastPayload])
async def podcasts_search(query: str, limit: int = 12) -> list[PodcastPayload]:
    return await metadata_provider.search_podcasts(query, limit=limit)


@app.get("/api/v1/podcasts/{podcast_key}", response_model=PodcastDetailsResponse)
async def podcast_details(podcast_key: str) -> PodcastDetailsResponse:
    podcast = await metadata_provider.lookup_podcast(podcast_key)
    if podcast is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Podcast not found")
    episodes = await metadata_provider.podcast_episodes(podcast, limit=16)
    return PodcastDetailsResponse(podcast=podcast, episodes=episodes)


@app.get("/api/v1/lyrics", response_model=LyricsResponse | None)
async def lyrics(artist: str, title: str) -> LyricsResponse | None:
    return await metadata_provider.lyrics(artist=artist, title=title)


@app.post("/api/v1/tracks/resolve", response_model=ResolvedStream)
async def resolve_track(payload: ResolveTrackRequest) -> ResolvedStream:
    query = payload.query
    if payload.track is not None:
        query = f"{payload.track.artist} - {payload.track.title}"
    if not query:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Missing query")

    cache_key = _resolved_stream_cache_key(payload, query)
    cached = resolved_stream_cache.get(cache_key)
    if cached is not None and cached[0] > utcnow():
        return cached[1]

    async with httpx.AsyncClient(timeout=settings.resolver_timeout_seconds) as client:
        response = await client.post(
            f"{settings.resolver_api_url}/api/v1/resolve",
            json={"query": query},
        )
        response.raise_for_status()
    resolved = ResolvedStream.model_validate(response.json())
    resolved_stream_cache[cache_key] = (
        utcnow() + timedelta(minutes=18),
        resolved,
    )
    return resolved


@app.get("/api/v1/me/likes", response_model=list[TrackPayload])
def get_likes(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[TrackPayload]:
    rows = db.scalars(
        select(SavedTrack)
        .where(SavedTrack.user_id == current_user.id)
        .order_by(desc(SavedTrack.created_at))
    ).all()
    return [TrackPayload.model_validate(row.track_payload) for row in rows]


@app.post("/api/v1/me/likes", response_model=TrackPayload, status_code=status.HTTP_201_CREATED)
def like_track(
    track: TrackPayload,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> TrackPayload:
    existing = db.scalar(
        select(SavedTrack).where(
            SavedTrack.user_id == current_user.id,
            SavedTrack.track_key == track.track_key,
        )
    )
    if existing:
        return TrackPayload.model_validate(existing.track_payload)

    row = SavedTrack(
        id=str(uuid4()),
        user_id=current_user.id,
        track_key=track.track_key,
        track_payload=track.model_dump(),
    )
    db.add(row)
    db.commit()
    return track


@app.delete("/api/v1/me/likes/{track_key}", status_code=status.HTTP_204_NO_CONTENT)
def unlike_track(
    track_key: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    row = db.scalar(
        select(SavedTrack).where(
            SavedTrack.user_id == current_user.id,
            SavedTrack.track_key == track_key,
        )
    )
    if row is None:
        return
    db.delete(row)
    db.commit()


@app.get("/api/v1/me/history", response_model=list[PlaybackEventOut])
def get_history(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[PlaybackEventOut]:
    rows = db.scalars(
        select(PlaybackEvent)
        .where(PlaybackEvent.user_id == current_user.id)
        .order_by(desc(PlaybackEvent.created_at))
        .limit(100)
    ).all()
    return [PlaybackEventOut.model_validate(row) for row in rows]


@app.post("/api/v1/me/history", response_model=PlaybackEventOut, status_code=status.HTTP_201_CREATED)
def add_history(
    payload: PlaybackEventCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PlaybackEventOut:
    event = PlaybackEvent(
        id=str(uuid4()),
        user_id=current_user.id,
        track_key=payload.track.track_key or build_track_key(payload.track.artist, payload.track.title),
        event_type=payload.event_type,
        listened_ms=payload.listened_ms,
        completion_ratio=payload.completion_ratio,
        track_payload=payload.track.model_dump(),
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return PlaybackEventOut.model_validate(event)


@app.get("/api/v1/playlists", response_model=list[PlaylistOut])
def list_playlists(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[PlaylistOut]:
    rows = db.scalars(
        select(Playlist)
        .where(Playlist.user_id == current_user.id)
        .options(selectinload(Playlist.tracks))
        .order_by(desc(Playlist.updated_at))
    ).all()
    return [PlaylistOut.model_validate(row) for row in rows]


@app.post("/api/v1/playlists", response_model=PlaylistOut, status_code=status.HTTP_201_CREATED)
def create_playlist(
    payload: PlaylistCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PlaylistOut:
    playlist = Playlist(
        id=str(uuid4()),
        user_id=current_user.id,
        name=payload.name.strip(),
        description=payload.description.strip(),
        artwork_url=payload.artwork_url,
    )
    db.add(playlist)
    db.commit()
    db.refresh(playlist)
    return PlaylistOut.model_validate(playlist)


@app.post("/api/v1/playlists/{playlist_id}/tracks", response_model=PlaylistOut)
def add_track_to_playlist(
    playlist_id: str,
    payload: PlaylistTrackCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PlaylistOut:
    playlist = db.scalar(
        select(Playlist)
        .where(Playlist.id == playlist_id, Playlist.user_id == current_user.id)
        .options(selectinload(Playlist.tracks))
    )
    if playlist is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Playlist not found")

    existing = next((item for item in playlist.tracks if item.track_key == payload.track.track_key), None)
    if existing is None:
        playlist_track = PlaylistTrack(
            id=str(uuid4()),
            playlist_id=playlist.id,
            track_key=payload.track.track_key,
            position=len(playlist.tracks),
            track_payload=payload.track.model_dump(),
        )
        db.add(playlist_track)
        playlist.updated_at = utcnow()
        if not playlist.artwork_url and payload.track.artwork_url:
            playlist.artwork_url = payload.track.artwork_url
        db.commit()

    playlist = db.scalar(
        select(Playlist)
        .where(Playlist.id == playlist_id, Playlist.user_id == current_user.id)
        .options(selectinload(Playlist.tracks))
    )
    return PlaylistOut.model_validate(playlist)


@app.delete("/api/v1/playlists/{playlist_id}/tracks/{track_key}", response_model=PlaylistOut)
def remove_track_from_playlist(
    playlist_id: str,
    track_key: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PlaylistOut:
    playlist = db.scalar(
        select(Playlist)
        .where(Playlist.id == playlist_id, Playlist.user_id == current_user.id)
        .options(selectinload(Playlist.tracks))
    )
    if playlist is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Playlist not found")

    db.execute(delete(PlaylistTrack).where(PlaylistTrack.playlist_id == playlist.id, PlaylistTrack.track_key == track_key))
    db.commit()

    playlist = db.scalar(
        select(Playlist)
        .where(Playlist.id == playlist_id, Playlist.user_id == current_user.id)
        .options(selectinload(Playlist.tracks))
    )
    for index, item in enumerate(playlist.tracks):
        item.position = index
    playlist.updated_at = utcnow()
    playlist.artwork_url = next(
        (item.track_payload.get("artwork_url") for item in playlist.tracks if item.track_payload.get("artwork_url")),
        None,
    )
    db.commit()
    db.refresh(playlist)
    return PlaylistOut.model_validate(playlist)


@app.delete("/api/v1/playlists/{playlist_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_playlist(
    playlist_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    playlist = db.scalar(select(Playlist).where(Playlist.id == playlist_id, Playlist.user_id == current_user.id))
    if playlist is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Playlist not found")
    db.delete(playlist)
    db.commit()


@app.get("/api/v1/recommendations", response_model=list[TrackPayload])
async def recommendations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[TrackPayload]:
    return await build_recommendations(
        db=db,
        user=current_user,
        provider=metadata_provider,
        lastfm_provider=lastfm_provider,
    )


@app.get("/api/v1/me/home", response_model=HomeResponse)
async def home(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> HomeResponse:
    liked_rows = db.scalars(
        select(SavedTrack)
        .where(SavedTrack.user_id == current_user.id)
        .order_by(desc(SavedTrack.created_at))
        .limit(12)
    ).all()

    history_rows = db.scalars(
        select(PlaybackEvent)
        .where(PlaybackEvent.user_id == current_user.id)
        .order_by(desc(PlaybackEvent.created_at))
        .limit(20)
    ).all()

    deduped_history: dict[str, TrackPayload] = {}
    for row in history_rows:
        if row.track_key not in deduped_history:
            deduped_history[row.track_key] = TrackPayload.model_validate(row.track_payload)

    recommendations_rows, generated_playlists, browse_categories, featured_podcasts = await asyncio.gather(
        _safe_async(
            "home recommendations",
            build_recommendations(
                db=db,
                user=current_user,
                provider=metadata_provider,
                lastfm_provider=lastfm_provider,
                limit=16,
            ),
            [],
        ),
        _safe_async(
            "home generated playlists",
            build_generated_playlists(
                db=db,
                user=current_user,
                provider=metadata_provider,
                lastfm_provider=lastfm_provider,
            ),
            [],
        ),
        _safe_async("home browse categories", _build_browse_categories(), []),
        _safe_async("home featured podcasts", _build_featured_podcasts(limit=6), []),
    )
    liked_tracks = [TrackPayload.model_validate(row.track_payload) for row in liked_rows]
    recently_played = list(deduped_history.values())[:12]
    recommendations_rows, recently_played, liked_tracks = await asyncio.gather(
        _safe_async(
            "home recommendation visuals",
            _hydrate_track_visuals(recommendations_rows, thumbnail_limit=6),
            recommendations_rows,
        ),
        _safe_async(
            "home history visuals",
            _hydrate_track_visuals(recently_played, thumbnail_limit=6),
            recently_played,
        ),
        _safe_async(
            "home likes visuals",
            _hydrate_track_visuals(liked_tracks, thumbnail_limit=4),
            liked_tracks,
        ),
    )

    return HomeResponse(
        recently_played=recently_played,
        liked_tracks=liked_tracks,
        recommendations=recommendations_rows,
        generated_playlists=generated_playlists,
        browse_categories=browse_categories,
        featured_podcasts=featured_podcasts,
    )
