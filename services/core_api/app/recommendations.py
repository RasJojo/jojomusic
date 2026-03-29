from collections import Counter, OrderedDict
import asyncio

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.metadata import ITunesProvider, LastFmProvider
from app.models import PlaybackEvent, SavedTrack, User
from app.schemas import GeneratedPlaylistPayload, TrackPayload

EDITORIAL_TRACK_QUERIES = [
    "new music friday",
    "pop hits",
    "rap francais",
    "hip hop hits",
    "afrobeats hits",
    "chill hits",
]


def _best_track_visual(tracks: list[TrackPayload]) -> str | None:
    return next(
        (
            track.artwork_url or track.artist_image_url
            for track in tracks
            if track.artwork_url or track.artist_image_url
        ),
        None,
    )


async def build_recommendations(
    db: Session,
    user: User,
    provider: ITunesProvider,
    lastfm_provider: LastFmProvider,
    limit: int = 20,
) -> list[TrackPayload]:
    liked_rows = db.scalars(
        select(SavedTrack)
        .where(SavedTrack.user_id == user.id)
        .order_by(SavedTrack.created_at.desc())
        .limit(64)
    ).all()
    history_rows = db.scalars(
        select(PlaybackEvent)
        .where(PlaybackEvent.user_id == user.id)
        .order_by(PlaybackEvent.created_at.desc())
        .limit(100)
    ).all()

    artist_weights: Counter[str] = Counter()
    for like in liked_rows:
        artist = like.track_payload.get("artist")
        if artist:
            artist_weights[artist] += 4

    for event in history_rows:
        artist = event.track_payload.get("artist")
        if not artist:
            continue
        if event.event_type == "track_completed":
            artist_weights[artist] += 3
        elif event.event_type == "play_started":
            artist_weights[artist] += 1
        elif event.event_type.startswith("skip"):
            artist_weights[artist] -= 1

    excluded_keys = {
        *[row.track_key for row in liked_rows],
        *[row.track_key for row in history_rows],
    }
    track_map: "OrderedDict[str, TrackPayload]" = OrderedDict()

    if not artist_weights:
        return await _editorial_tracks(
            provider=provider,
            excluded_keys=excluded_keys,
            queries=EDITORIAL_TRACK_QUERIES,
            limit=limit,
        )

    if lastfm_provider.enabled:
        seed_tracks = [
            *[TrackPayload.model_validate(row.track_payload) for row in liked_rows[:2]],
            *[
                TrackPayload.model_validate(row.track_payload)
                for row in history_rows
                if row.event_type in {"play_started", "track_completed"}
            ][:2],
        ]
        similar_batches = await asyncio.gather(
            *[
                lastfm_provider.similar_tracks(seed.artist, seed.title, limit=6)
                for seed in seed_tracks
            ],
            return_exceptions=True,
        )
        for batch in similar_batches:
            if isinstance(batch, Exception):
                continue
            for track in batch:
                if track.track_key in excluded_keys or track.track_key in track_map:
                    continue
                track_map[track.track_key] = track
                if len(track_map) >= limit:
                    return list(track_map.values())

    top_artists = [artist for artist, _ in artist_weights.most_common(2)]
    lastfm_artist_batches: list[list[TrackPayload]] = []
    provider_artist_batches: list[list[TrackPayload]] = []
    if top_artists:
        if lastfm_provider.enabled:
            batches = await asyncio.gather(
                *[
                    lastfm_provider.top_tracks_for_artist(artist, limit=6)
                    for artist in top_artists
                ],
                return_exceptions=True,
            )
            lastfm_artist_batches = [
                batch for batch in batches if not isinstance(batch, Exception)
            ]
        batches = await asyncio.gather(
            *[
                provider.top_for_artist(artist, limit=8)
                for artist in top_artists
            ],
            return_exceptions=True,
        )
        provider_artist_batches = [
            batch for batch in batches if not isinstance(batch, Exception)
        ]

    for batch in [*lastfm_artist_batches, *provider_artist_batches]:
        for track in batch:
            if track.track_key in excluded_keys or track.track_key in track_map:
                continue
            track_map[track.track_key] = track
            if len(track_map) >= limit:
                return list(track_map.values())

    return list(track_map.values())


async def build_generated_playlists(
    db: Session,
    user: User,
    provider: ITunesProvider,
    lastfm_provider: LastFmProvider,
    recommendations_seed: list[TrackPayload] | None = None,
) -> list[GeneratedPlaylistPayload]:
    liked_rows = db.scalars(
        select(SavedTrack)
        .where(SavedTrack.user_id == user.id)
        .limit(24)
    ).all()
    history_rows = db.scalars(
        select(PlaybackEvent)
        .where(PlaybackEvent.user_id == user.id)
        .order_by(PlaybackEvent.created_at.desc())
        .limit(40)
    ).all()

    liked_tracks = [TrackPayload.model_validate(row.track_payload) for row in liked_rows]
    history_tracks = [TrackPayload.model_validate(row.track_payload) for row in history_rows]
    recommendations = recommendations_seed
    if recommendations is None:
        recommendations = await build_recommendations(
            db=db,
            user=user,
            provider=provider,
            lastfm_provider=lastfm_provider,
            limit=24,
        )
    excluded_keys = {
        *[track.track_key for track in liked_tracks],
        *[track.track_key for track in history_tracks],
    }

    playlists: list[GeneratedPlaylistPayload] = []
    if recommendations:
        playlists.append(
            GeneratedPlaylistPayload(
                playlist_key="discover-weekly",
                title="Découvertes de la semaine",
                subtitle="Une sélection fraîche construite autour de ce que tu écoutes déjà",
                artwork_url=_best_track_visual(recommendations),
                tracks=recommendations[:12],
            )
        )

    if liked_tracks or history_tracks:
        rewind_tracks = _dedupe_payload_tracks([*history_tracks[:6], *liked_tracks[:6]])[:12]
        playlists.append(
            GeneratedPlaylistPayload(
                playlist_key="on-repeat",
                title="On Repeat",
                subtitle="Les titres que tu rejoues le plus en ce moment",
                artwork_url=_best_track_visual(rewind_tracks),
                tracks=rewind_tracks,
            )
        )

    top_artists = Counter(track.artist for track in [*liked_tracks, *history_tracks] if track.artist)
    top_artist_names = [artist for artist, _ in top_artists.most_common(2)]

    for index, artist in enumerate(top_artist_names, start=1):
        local_artist_tracks = _dedupe_payload_tracks(
            [
                *[track for track in liked_tracks if track.artist == artist],
                *[track for track in history_tracks if track.artist == artist],
                *[track for track in recommendations if track.artist == artist],
            ]
        )[:12]
        artist_tracks = local_artist_tracks
        if len(artist_tracks) < 8:
            fetched_tracks = await provider.top_for_artist(artist, limit=8)
            if lastfm_provider.enabled:
                fetched_tracks = _dedupe_payload_tracks(
                    [*await lastfm_provider.top_tracks_for_artist(artist, limit=6), *fetched_tracks]
                )[:12]
            artist_tracks = _dedupe_payload_tracks([*artist_tracks, *fetched_tracks])[:12]
        if artist_tracks:
            playlists.append(
                GeneratedPlaylistPayload(
                    playlist_key=f"daily-mix-{index}-{artist.lower().replace(' ', '-')}",
                    title=f"Daily Mix {index}",
                    subtitle=f"Un mix centré sur {artist} et les artistes qui gravitent autour",
                    artwork_url=_best_track_visual(artist_tracks),
                    tracks=artist_tracks,
                )
            )

    if top_artist_names:
        artist = top_artist_names[0]
        artist_tracks = _dedupe_payload_tracks(
            [
                *[track for track in recommendations if track.artist == artist],
                *[track for track in liked_tracks if track.artist == artist],
                *[track for track in history_tracks if track.artist == artist],
            ]
        )[:12]
        if len(artist_tracks) < 8:
            fetched_tracks = await provider.top_for_artist(artist, limit=8)
            if lastfm_provider.enabled:
                fetched_tracks = _dedupe_payload_tracks(
                    [*await lastfm_provider.top_tracks_for_artist(artist, limit=6), *fetched_tracks]
                )[:12]
            artist_tracks = _dedupe_payload_tracks([*artist_tracks, *fetched_tracks])[:12]
        if artist_tracks:
            playlists.append(
                GeneratedPlaylistPayload(
                    playlist_key=f"artist-radio-{artist.lower().replace(' ', '-')}",
                    title=f"Radio {artist}",
                    subtitle="Une station auto-générée à partir de ton artiste dominant",
                    artwork_url=_best_track_visual(artist_tracks),
                    tracks=artist_tracks,
                )
            )

    if not playlists:
        editorial_playlists = [
            (
                "daily-mix-1",
                "Daily Mix 1",
                "Une base polyvalente pour démarrer l’écoute",
                "pop hits",
            ),
            (
                "discover-weekly",
                "Découvertes de la semaine",
                "Des sorties et titres frais pour lancer ton profil",
                "new music friday",
            ),
            (
                "afro-mix",
                "Afro Mix",
                "Afrobeats, amapiano et chaleur immédiate",
                "afrobeats hits",
            ),
            (
                "chill-mix",
                "Chill Mix",
                "Textures calmes, pop nocturne et morceaux posés",
                "chill hits",
            ),
        ]
        for playlist_key, title, subtitle, query in editorial_playlists:
            tracks = await _editorial_tracks(
                provider=provider,
                excluded_keys=excluded_keys,
                queries=[query],
                limit=12,
            )
            if not tracks:
                continue
            playlists.append(
                GeneratedPlaylistPayload(
                    playlist_key=playlist_key,
                    title=title,
                    subtitle=subtitle,
                    artwork_url=next((track.artwork_url for track in tracks if track.artwork_url), None),
                    tracks=tracks,
                )
            )

    return playlists[:5]


async def build_similar_tracks(
    *,
    seed_track: TrackPayload,
    provider: ITunesProvider,
    lastfm_provider: LastFmProvider,
    exclude_keys: set[str] | None = None,
    limit: int = 12,
) -> list[TrackPayload]:
    excluded = set(exclude_keys or set())
    excluded.add(seed_track.track_key)
    track_map: "OrderedDict[str, TrackPayload]" = OrderedDict()

    if lastfm_provider.enabled:
        for track in await lastfm_provider.similar_tracks(
            seed_track.artist,
            seed_track.title,
            limit=max(limit * 2, 10),
        ):
            if track.track_key in excluded or track.track_key in track_map:
                continue
            track_map[track.track_key] = track
            if len(track_map) >= limit:
                return list(track_map.values())

    for track in await provider.top_for_artist(
        seed_track.artist,
        limit=max(limit * 2, 10),
    ):
        if track.track_key in excluded or track.track_key in track_map:
            continue
        track_map[track.track_key] = track
        if len(track_map) >= limit:
            return list(track_map.values())

    if lastfm_provider.enabled:
        for track in await lastfm_provider.top_tracks_for_artist(
            seed_track.artist,
            limit=max(limit, 8),
        ):
            if track.track_key in excluded or track.track_key in track_map:
                continue
            track_map[track.track_key] = track
            if len(track_map) >= limit:
                return list(track_map.values())

    search_queries = [
        f"{seed_track.artist} {seed_track.title}",
        seed_track.artist,
        seed_track.title,
    ]
    for query in search_queries:
        for track in await provider.search_tracks(query, limit=max(limit * 2, 12)):
            if track.track_key in excluded or track.track_key in track_map:
                continue
            track_map[track.track_key] = track
            if len(track_map) >= limit:
                return list(track_map.values())

    return list(track_map.values())[:limit]


async def _editorial_tracks(
    *,
    provider: ITunesProvider,
    excluded_keys: set[str],
    queries: list[str],
    limit: int,
) -> list[TrackPayload]:
    track_map: "OrderedDict[str, TrackPayload]" = OrderedDict()
    for query in queries:
        for track in await provider.search_tracks(query, limit=12):
            if track.track_key in excluded_keys or track.track_key in track_map:
                continue
            track_map[track.track_key] = track
            if len(track_map) >= limit:
                return list(track_map.values())
    return list(track_map.values())


def _dedupe_payload_tracks(tracks: list[TrackPayload]) -> list[TrackPayload]:
    ordered: "OrderedDict[str, TrackPayload]" = OrderedDict()
    for track in tracks:
        if track.track_key not in ordered:
            ordered[track.track_key] = track
    return list(ordered.values())
