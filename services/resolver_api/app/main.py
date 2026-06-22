from __future__ import annotations

import logging
import os
import re
import time
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from yt_dlp import YoutubeDL

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("jojomusic.resolver")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    resolver_timeout_seconds: int = 25
    piped_instances: str = ""
    tor_proxy: str | None = None
    youtube_pot_provider_url: str | None = None


settings = Settings()
app = FastAPI(title="JojoMusic Resolver API", version="0.2.0")

COOKIES_PATH = Path("/tmp/cookies.txt")
COOKIE_SOURCE_PATH = Path("/app/cookies.txt")
YOUTUBE_PLAYER_CLIENTS = ["mweb", "web_safari", "web", "android", "ios"]


def _has_cookie_source() -> bool:
    return COOKIE_SOURCE_PATH.exists() and COOKIE_SOURCE_PATH.stat().st_size > 0


def _ensure_cookies() -> str | None:
    """Copy validated cookies from the read-only mount to /tmp, return path or None."""
    if _has_cookie_source():
        import shutil
        shutil.copy2(COOKIE_SOURCE_PATH, COOKIES_PATH)
        return str(COOKIES_PATH)
    return None


def _youtube_extractor_args() -> dict:
    args: dict = {
        "youtube": {
            "player_client": YOUTUBE_PLAYER_CLIENTS,
        },
    }
    if settings.youtube_pot_provider_url:
        args["youtubepot-bgutilhttp"] = {
            "base_url": [settings.youtube_pot_provider_url.rstrip("/")],
        }
    return args
PIPED_INSTANCES = [i.strip() for i in settings.piped_instances.split(",") if i.strip()]

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class ResolveRequest(BaseModel):
    query: str = Field(min_length=2, max_length=300)


class ResolveResponse(BaseModel):
    stream_url: str
    webpage_url: str | None = None
    thumbnail_url: str | None = None
    title: str
    artist: str
    duration_ms: int | None = None
    source: str = "youtube"


class SearchRequest(BaseModel):
    query: str = Field(min_length=2, max_length=300)
    limit: int = Field(default=6, ge=1, le=12)


class SearchCandidate(BaseModel):
    title: str
    artist: str
    webpage_url: str | None = None
    thumbnail_url: str | None = None
    duration_ms: int | None = None
    youtube_rank: int
    score: float
    source: str = "youtube"


class SearchResponse(BaseModel):
    query: str
    results: list[SearchCandidate]


# ---------------------------------------------------------------------------
# Text scoring helpers
# ---------------------------------------------------------------------------

_NEGATIVE_HINTS = (
    "karaoke", "instrumental", "nightcore", "slowed", "sped up",
    "lyrics", "lyric video", "8d", "bass boosted", "fanmade", "amv",
    "reaction", "react", "review", "analyse", "critique", "interview",
    "podcast", "documentaire", "chronique", "debrief", "type beat",
    "free beat",
)

_BLOCKED_NON_MUSIC_HINTS = (
    "du rap en mieux", "reaction", "react", "review", "analyse", "critique",
    "interview", "podcast", "documentaire", "chronique", "debrief",
    "le rab en mieux", "le rap en mieux", "type beat", "free beat",
)


def _normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized.lower())
    return " ".join(normalized.split())


def _token_overlap_score(query_text: str, candidate_text: str) -> float:
    query_tokens = set(_normalize_text(query_text).split())
    candidate_tokens = set(_normalize_text(candidate_text).split())
    if not query_tokens:
        return 0.0
    return len(query_tokens & candidate_tokens) / len(query_tokens)


def _entry_artist(entry: dict) -> str:
    return (
        entry.get("artist")
        or entry.get("uploader")
        or entry.get("uploaderName")
        or entry.get("channel")
        or ""
    )


def _has_blocked_non_music_hint(query: str, entry: dict) -> bool:
    query_text = _normalize_text(query)
    combined = _normalize_text(
        " ".join(
            str(entry.get(key) or "")
            for key in ("title", "artist", "uploader", "uploaderName", "channel")
        )
    )
    return any(hint in combined and hint not in query_text for hint in _BLOCKED_NON_MUSIC_HINTS)


def _candidate_score(query: str, entry: dict) -> float:
    query_text = _normalize_text(query)
    title = entry.get("title") or ""
    artist = _entry_artist(entry)
    combined = f"{artist} {title}"
    combined_text = _normalize_text(combined)

    ratio = SequenceMatcher(None, query_text, combined_text).ratio()
    overlap = _token_overlap_score(query, combined)
    title_overlap = _token_overlap_score(query, title)
    artist_overlap = _token_overlap_score(query, artist)

    score = ratio * 0.42 + overlap * 0.33 + title_overlap * 0.17 + artist_overlap * 0.08

    for hint in _NEGATIVE_HINTS:
        if hint in combined_text and hint not in query_text:
            score -= 0.15
    if _has_blocked_non_music_hint(query, entry):
        score -= 0.55
    if "official" in combined_text:
        score += 0.03
    if "topic" in _normalize_text(artist):
        score += 0.02
    return score


def _is_viable_candidate(query: str, entry: dict) -> bool:
    if not entry or not _entry_video_url(entry):
        return False
    if _has_blocked_non_music_hint(query, entry):
        return False
    title = _normalize_text(entry.get("title") or "")
    artist = _normalize_text(_entry_artist(entry))
    combined = f"{artist} {title}".strip()
    if not combined:
        return False
    query_text = _normalize_text(query)
    score = _candidate_score(query, entry)
    overlap = _token_overlap_score(query, combined)
    if score >= 0.58:
        return True
    if overlap >= 0.55:
        return True
    if query_text and query_text in combined:
        return True
    return False


def _query_variants(query: str) -> list[str]:
    base = query.strip()
    unwrapped = re.sub(r"[\[\]().]+", " ", base)
    without_punct = re.sub(r"[^a-zA-Z0-9\u00C0-\u017F]+", " ", unwrapped)
    feat_variant = re.sub(r"\bavec\b", "feat", without_punct, flags=re.IGNORECASE)
    return list(
        dict.fromkeys(
            v.strip()
            for v in (
                base,
                unwrapped,
                feat_variant,
                without_punct,
                f"{without_punct} audio",
                f"{feat_variant} official audio",
            )
            if v.strip()
        )
    )


def _entry_video_url(entry: dict) -> str | None:
    raw = entry.get("webpage_url") or entry.get("url") or entry.get("id")
    if not raw:
        return None
    raw = str(raw)
    if raw.startswith("/watch?v="):
        return f"https://www.youtube.com{raw}"
    if re.fullmatch(r"[a-zA-Z0-9_-]{11}", raw):
        return f"https://www.youtube.com/watch?v={raw}"
    return raw


def _select_best_entry(query: str, entries: list[dict]) -> dict | None:
    viable = [entry for entry in entries if _is_viable_candidate(query, entry)]
    if not viable:
        return None
    return max(viable, key=lambda entry: _candidate_score(query, entry))


# ---------------------------------------------------------------------------
# Thumbnail helper
# ---------------------------------------------------------------------------

def _best_thumbnail(entry: dict) -> str | None:
    thumbnails = entry.get("thumbnails")
    if isinstance(thumbnails, list) and thumbnails:
        best = max(thumbnails, key=lambda t: t.get("width", 0) or 0)
        return best.get("url")
    thumb = entry.get("thumbnail")
    if thumb:
        return thumb
    video_id = entry.get("id")
    if video_id:
        return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
    return None


# ---------------------------------------------------------------------------
# Video ID extraction
# ---------------------------------------------------------------------------

def _extract_video_id(url: str) -> str | None:
    value = url.strip()
    if re.fullmatch(r"[a-zA-Z0-9_-]{11}", value):
        return value
    patterns = [
        r"(?:v=|/v/|youtu\.be/)([a-zA-Z0-9_-]{11})",
        r"/embed/([a-zA-Z0-9_-]{11})",
        r"/shorts/([a-zA-Z0-9_-]{11})",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None


def _youtube_url_from_query(query: str) -> str | None:
    video_id = _extract_video_id(query)
    if not video_id:
        return None
    return f"https://www.youtube.com/watch?v={video_id}"


# ---------------------------------------------------------------------------
# Piped API client (primary source for stream resolution)
# ---------------------------------------------------------------------------

def _fetch_json(url: str, timeout: int = 10) -> dict | None:
    """Fetch JSON from a URL, returns None on failure."""
    try:
        req = Request(url, headers={
            "User-Agent": "JojoMusic/1.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                import json
                return json.loads(resp.read())
    except Exception as exc:
        logger.debug("Piped request failed url=%s error=%s", url, exc)
    return None


def _piped_search(query: str, limit: int = 6) -> list[dict]:
    """Search YouTube via Piped API, returns list of result dicts."""
    import json
    from urllib.parse import quote
    for instance in PIPED_INSTANCES:
        url = f"https://{instance}/search?q={quote(query)}&filter=music_songs"
        data = _fetch_json(url, timeout=8)
        if data and data.get("items"):
            return data["items"][:limit]
        # Fallback to videos filter
        url = f"https://{instance}/search?q={quote(query)}&filter=videos"
        data = _fetch_json(url, timeout=8)
        if data and data.get("items"):
            return data["items"][:limit]
    return []


def _piped_streams(video_id: str) -> dict | None:
    """Get stream URLs from Piped API for a video ID."""
    for instance in PIPED_INSTANCES:
        url = f"https://{instance}/streams/{video_id}"
        data = _fetch_json(url, timeout=12)
        if data and (data.get("audioStreams") or data.get("videoStreams")):
            return data
    return None


def _piped_resolve(query: str) -> ResolveResponse | None:
    """Resolve a stream via Piped: search then get stream URL."""
    best = None
    for variant in _query_variants(query):
        results = _piped_search(variant, limit=8)
        if not results:
            continue
        candidates = []
        for item in results:
            artist = item.get("uploaderName") or ""
            candidates.append({
                **item,
                "artist": artist,
                "uploader": artist,
                "url": _entry_video_url(item),
            })
        best = _select_best_entry(query, candidates)
        if best:
            break

    if not best:
        return None

    webpage_url = _entry_video_url(best)
    video_id = _extract_video_id(webpage_url or "")
    if not video_id:
        return None

    title = best.get("title") or query
    artist = best.get("uploaderName") or "Unknown artist"
    duration = best.get("duration")
    thumbnail = best.get("thumbnail") or best.get("uploaderAvatar")
    webpage_url = f"https://www.youtube.com/watch?v={video_id}"

    # Step 2: Get stream URLs
    stream_data = _piped_streams(video_id)
    if not stream_data:
        return None

    # Pick the best audio stream (prefer m4a/aac, highest bitrate)
    audio_streams = stream_data.get("audioStreams", [])
    if not audio_streams:
        # Fallback to video stream (will have audio)
        video_streams = stream_data.get("videoStreams", [])
        if not video_streams:
            return None
        audio_streams = video_streams

    # Sort by bitrate descending, prefer m4a
    def stream_sort_key(s: dict) -> tuple:
        mime = s.get("mimeType", "")
        is_m4a = 1 if "mp4" in mime or "m4a" in mime else 0
        bitrate = s.get("bitrate", 0) or 0
        return (is_m4a, bitrate)

    audio_streams.sort(key=stream_sort_key, reverse=True)
    stream_url = audio_streams[0].get("url")
    if not stream_url:
        return None

    # Use stream data thumbnail if better
    if stream_data.get("thumbnailUrl"):
        thumbnail = stream_data["thumbnailUrl"]

    return ResolveResponse(
        stream_url=stream_url,
        webpage_url=webpage_url,
        thumbnail_url=thumbnail,
        title=stream_data.get("title") or title,
        artist=stream_data.get("uploader") or artist,
        duration_ms=(duration * 1000) if duration else None,
        source="piped",
    )


# ---------------------------------------------------------------------------
# yt-dlp helpers (fallback with cookies)
# ---------------------------------------------------------------------------

def _ydl_options(*, use_proxy: bool = False, use_cookies: bool = True, **overrides) -> dict:
    opts = {
        "quiet": True,
        "noplaylist": True,
        "socket_timeout": settings.resolver_timeout_seconds,
        "extract_flat": True,
        "ignoreerrors": True,
        "cachedir": False,
        "remote_components": ["ejs:github"],
        "extractor_args": _youtube_extractor_args(),
    }
    if use_proxy and settings.tor_proxy:
        opts["proxy"] = settings.tor_proxy
    # Only inject cookies for full extraction (stream resolve), not search
    use_flat = overrides.get("extract_flat", opts.get("extract_flat", True))
    if use_cookies and not use_flat:
        cookie_path = _ensure_cookies()
        if cookie_path:
            opts["cookiefile"] = cookie_path
    opts.update(overrides)
    return opts


def _find_best_video_url(query: str, *, use_proxy: bool = False) -> tuple[str, str, str | None, float | None, str | None]:
    """Use flat search to find the best matching video URL."""
    options = _ydl_options(use_proxy=use_proxy, use_cookies=False)
    all_entries: list[dict] = []
    with YoutubeDL(options) as ydl:
        for variant in _query_variants(query):
            info = ydl.extract_info(f"ytsearch12:{variant}", download=False)
            all_entries.extend([e for e in (info.get("entries") or []) if e])

    if not all_entries:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No search results found")

    best = _select_best_entry(query, all_entries)
    video_url = _entry_video_url(best or {})
    if not best or not video_url:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No viable search result")

    title = best.get("title") or query
    artist = _entry_artist(best) or "Unknown artist"
    duration = best.get("duration")
    thumbnail_url = _best_thumbnail(best)
    return video_url, title, artist, duration, thumbnail_url


def _ytdlp_resolve(query: str, *, use_proxy: bool = False, use_cookies: bool = True) -> ResolveResponse:
    """Resolve stream via yt-dlp with cookies fallback."""
    direct_video_url = _youtube_url_from_query(query)
    if direct_video_url:
        video_url = direct_video_url
        title = query
        artist = "YouTube"
        search_duration = None
        thumbnail_url = None
    else:
        video_url, title, artist, search_duration, thumbnail_url = _find_best_video_url(
            query,
            use_proxy=use_proxy,
        )

    options = _ydl_options(
        use_proxy=use_proxy,
        use_cookies=use_cookies,
        extract_flat=False,
        format="bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio[acodec^=mp4a]/bestaudio/best",
    )
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(video_url, download=False)

    if info and info.get("url"):
        entry = info
    elif info and info.get("entries"):
        entries = [e for e in info["entries"] if e and e.get("url")]
        if not entries:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No stream found for video")
        entry = entries[0]
    else:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No stream found for video")

    duration = entry.get("duration") or search_duration
    return ResolveResponse(
        stream_url=entry["url"],
        webpage_url=entry.get("webpage_url") or video_url,
        thumbnail_url=_best_thumbnail(entry) or thumbnail_url,
        title=entry.get("title") or title,
        artist=entry.get("artist") or entry.get("uploader") or entry.get("channel") or artist,
        duration_ms=duration * 1000 if duration else None,
        source="youtube",
    )


# ---------------------------------------------------------------------------
# Combined extract_stream: Piped first, yt-dlp fallback
# ---------------------------------------------------------------------------

def extract_stream(query: str) -> ResolveResponse:
    # Try Piped first (no cookies needed, fast, no bot detection)
    try:
        result = _piped_resolve(query)
        if result and result.stream_url:
            logger.info("Resolved via Piped: %s", result.title)
            return result
    except Exception as exc:
        logger.warning("Piped resolve failed: %s", exc)

    errors: list[Exception] = []
    if _has_cookie_source():
        try:
            logger.info("Piped failed, trying yt-dlp with cookies for: %s", query)
            return _ytdlp_resolve(query, use_cookies=True)
        except Exception as exc:
            errors.append(exc)
            logger.warning("yt-dlp cookie resolve failed: %s", exc)

    if not _has_cookie_source():
        logger.warning("No validated YouTube cookies; skipping yt-dlp resolve for: %s", query)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="YOUTUBE_COOKIES_NOT_READY",
        )

    if errors:
        raise errors[-1]
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No resolver path available")


# ---------------------------------------------------------------------------
# Search: yt-dlp flat search (fast, works without cookies)
# ---------------------------------------------------------------------------

def search_candidates(query: str, limit: int) -> SearchResponse:
    options = _ydl_options(extract_flat=True)
    search_size = max(limit + 4, 10)
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"ytsearch{search_size}:{query}", download=False)

    entries = info["entries"] if "entries" in info else [info]
    candidates: list[SearchCandidate] = []
    for index, entry in enumerate(entries):
        if not _is_viable_candidate(query, entry):
            continue
        artist = _entry_artist(entry) or "Unknown artist"
        duration = entry.get("duration")
        candidates.append(
            SearchCandidate(
                title=entry.get("title") or query,
                artist=artist,
                webpage_url=_entry_video_url(entry),
                thumbnail_url=_best_thumbnail(entry),
                duration_ms=duration * 1000 if duration else None,
                youtube_rank=index,
                score=round(_candidate_score(query, entry), 4),
            )
        )
        if len(candidates) >= limit:
            break

    if not candidates:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No search results found")

    return SearchResponse(query=query, results=candidates)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "cookies_loaded": _has_cookie_source(),
        "pot_provider_configured": bool(settings.youtube_pot_provider_url),
        "pot_provider_url": settings.youtube_pot_provider_url,
        "piped_instances": PIPED_INSTANCES,
    }


@app.post("/api/v1/resolve", response_model=ResolveResponse)
def resolve(payload: ResolveRequest) -> ResolveResponse:
    try:
        return extract_stream(payload.query)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.post("/api/v1/search", response_model=SearchResponse)
def search(payload: SearchRequest) -> SearchResponse:
    try:
        return search_candidates(payload.query, payload.limit)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
