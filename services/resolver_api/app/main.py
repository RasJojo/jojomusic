from __future__ import annotations

import re
import unicodedata
from difflib import SequenceMatcher

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from yt_dlp import YoutubeDL


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    resolver_timeout_seconds: int = 25


settings = Settings()
app = FastAPI(title="JojoMusic Resolver API", version="0.1.0")


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


_NEGATIVE_HINTS = (
    "karaoke",
    "instrumental",
    "nightcore",
    "slowed",
    "sped up",
    "lyrics",
    "lyric video",
    "8d",
    "bass boosted",
    "fanmade",
    "amv",
)


def _normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode(
        "ascii",
        "ignore",
    ).decode("ascii")
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized.lower())
    return " ".join(normalized.split())


def _token_overlap_score(query_text: str, candidate_text: str) -> float:
    query_tokens = set(_normalize_text(query_text).split())
    candidate_tokens = set(_normalize_text(candidate_text).split())
    if not query_tokens:
        return 0.0
    return len(query_tokens & candidate_tokens) / len(query_tokens)


def _candidate_score(query: str, entry: dict) -> float:
    query_text = _normalize_text(query)
    title = entry.get("title") or ""
    artist = entry.get("artist") or entry.get("uploader") or ""
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

    if "official" in combined_text:
        score += 0.03
    if "topic" in _normalize_text(artist):
        score += 0.02

    return score


def _is_viable_candidate(query: str, entry: dict) -> bool:
    if not entry or not entry.get("url"):
        return False

    title = _normalize_text(entry.get("title") or "")
    artist = _normalize_text(entry.get("artist") or entry.get("uploader") or "")
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


def _pick_best_entry(query: str, info: dict) -> dict:
    entries = info["entries"] if "entries" in info else [info]
    candidates = [entry for entry in entries if entry and entry.get("url")]
    if not candidates:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No stream found",
        )
    return max(candidates, key=lambda entry: _candidate_score(query, entry))


def search_candidates(query: str, limit: int) -> SearchResponse:
    options = {
        "quiet": True,
        "noplaylist": True,
        "socket_timeout": settings.resolver_timeout_seconds,
        "extract_flat": False,
        "ignoreerrors": True,
    }
    search_size = max(limit + 2, 8)
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"ytsearch{search_size}:{query}", download=False)

    entries = info["entries"] if "entries" in info else [info]
    candidates: list[SearchCandidate] = []
    for index, entry in enumerate(entries):
        if not _is_viable_candidate(query, entry):
            continue
        artist = entry.get("artist") or entry.get("uploader") or "Unknown artist"
        duration = entry.get("duration")
        candidates.append(
            SearchCandidate(
                title=entry.get("title") or query,
                artist=artist,
                webpage_url=entry.get("webpage_url"),
                thumbnail_url=entry.get("thumbnail"),
                duration_ms=duration * 1000 if duration else None,
                youtube_rank=index,
                score=round(_candidate_score(query, entry), 4),
            )
        )
        if len(candidates) >= limit:
            break

    if not candidates:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No search results found",
        )

    return SearchResponse(query=query, results=candidates)


def extract_stream(query: str) -> ResolveResponse:
    options = {
        "quiet": True,
        "noplaylist": True,
        "format": "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio[acodec^=mp4a]/bestaudio/best",
        "socket_timeout": settings.resolver_timeout_seconds,
        "extract_flat": False,
        "ignoreerrors": True,
    }
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"ytsearch8:{query}", download=False)

    entry = _pick_best_entry(query, info)

    artist = entry.get("artist") or entry.get("uploader") or "Unknown artist"
    duration = entry.get("duration")
    return ResolveResponse(
        stream_url=entry["url"],
        webpage_url=entry.get("webpage_url"),
        thumbnail_url=entry.get("thumbnail"),
        title=entry.get("title") or query,
        artist=artist,
        duration_ms=duration * 1000 if duration else None,
    )


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/api/v1/resolve", response_model=ResolveResponse)
def resolve(payload: ResolveRequest) -> ResolveResponse:
    try:
        return extract_stream(payload.query)
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.post("/api/v1/search", response_model=SearchResponse)
def search(payload: SearchRequest) -> SearchResponse:
    try:
        return search_candidates(payload.query, payload.limit)
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
# Resolver
# Sources
