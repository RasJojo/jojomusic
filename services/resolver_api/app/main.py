from __future__ import annotations

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


def extract_stream(query: str) -> ResolveResponse:
    options = {
        "quiet": True,
        "noplaylist": True,
        "default_search": "ytsearch1",
        "format": "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio[acodec^=mp4a]/bestaudio/best",
        "socket_timeout": settings.resolver_timeout_seconds,
        "extract_flat": False,
    }
    with YoutubeDL(options) as ydl:
        info = ydl.extract_info(query, download=False)

    entry = info["entries"][0] if "entries" in info else info
    if not entry or not entry.get("url"):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No stream found")

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
