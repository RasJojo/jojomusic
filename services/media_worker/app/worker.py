from __future__ import annotations

import hashlib
import json
import logging
import mimetypes
import os
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import Request, urlopen

import psycopg
import redis
from yt_dlp import YoutubeDL

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("jojomusic.media_worker")

DATABASE_URL = os.environ["DATABASE_URL"]
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379")
MEDIA_QUEUE_KEY = os.getenv("MEDIA_QUEUE_KEY", "media:ingest")
IMAGE_QUEUE_KEY = os.getenv("IMAGE_QUEUE_KEY", "image:ingest")
MEDIA_CACHE_DIR = Path(os.getenv("MEDIA_CACHE_DIR", "/data/audio_cache")).resolve()
IMAGE_CACHE_DIR = Path(os.getenv("IMAGE_CACHE_DIR", "/data/image_cache")).resolve()
TEMP_DIR = MEDIA_CACHE_DIR / ".tmp"
IMAGE_TEMP_DIR = IMAGE_CACHE_DIR / ".tmp"
USER_AGENT = "JojoMusic/1.0 (+https://jojomusicapi.jojoserv.com)"


def redis_client() -> redis.Redis:
    return redis.Redis.from_url(REDIS_URL, decode_responses=True)


def db_connection() -> psycopg.Connection:
    return psycopg.connect(DATABASE_URL, autocommit=True)


def first_entry(info: dict[str, Any]) -> dict[str, Any]:
    entries = info.get("entries")
    if isinstance(entries, list) and entries:
        return entries[0]
    return info


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def clean_previous_outputs(base_dir: Path, base_name: str) -> None:
    for path in base_dir.glob(f"{base_name}.*"):
        if path.is_file():
            path.unlink(missing_ok=True)


def find_output_path(base_name: str) -> Path:
    preferred = MEDIA_CACHE_DIR / f"{base_name}.m4a"
    if preferred.exists():
        return preferred
    matches = sorted(
        path
        for path in MEDIA_CACHE_DIR.glob(f"{base_name}.*")
        if path.is_file() and not path.name.endswith(".part")
    )
    if not matches:
        raise FileNotFoundError(f"no output file produced for {base_name}")
    return matches[0]


def download_audio_asset(query: str, base_name: str) -> tuple[Path, dict[str, Any]]:
    ensure_dir(MEDIA_CACHE_DIR)
    ensure_dir(TEMP_DIR)
    clean_previous_outputs(MEDIA_CACHE_DIR, base_name)
    output_template = str(MEDIA_CACHE_DIR / f"{base_name}.%(ext)s")
    ydl_opts: dict[str, Any] = {
        "format": "bestaudio[ext=m4a]/bestaudio[acodec*=aac]/bestaudio",
        "default_search": "ytsearch1",
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "cachedir": False,
        "outtmpl": output_template,
        "paths": {"home": str(MEDIA_CACHE_DIR), "temp": str(TEMP_DIR)},
        "socket_timeout": 20,
        "retries": 5,
        "fragment_retries": 5,
        "concurrent_fragment_downloads": 4,
        "prefer_ffmpeg": True,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "m4a",
                "preferredquality": "192",
            }
        ],
    }
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(f"ytsearch1:{query}", download=True)
        entry = first_entry(info)
    return find_output_path(base_name), entry


def infer_image_extension(content_type: str | None, source_url: str) -> str:
    normalized = (content_type or "").split(";", 1)[0].strip().lower()
    if normalized:
        guessed = mimetypes.guess_extension(normalized)
        if guessed:
            if guessed == ".jpe":
                return ".jpg"
            return guessed
    suffix = Path(urlparse(source_url).path).suffix.lower()
    if suffix in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif"}:
        return ".jpg" if suffix == ".jpeg" else suffix
    return ".jpg"


def download_image_asset(source_url: str, base_name: str) -> tuple[Path, str]:
    ensure_dir(IMAGE_CACHE_DIR)
    ensure_dir(IMAGE_TEMP_DIR)
    clean_previous_outputs(IMAGE_CACHE_DIR, base_name)

    request = Request(
        source_url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        },
    )
    with urlopen(request, timeout=20) as response:  # noqa: S310
        content_type = response.headers.get_content_type()
        if not content_type.startswith("image/"):
            raise ValueError(f"unexpected content-type {content_type}")
        payload = response.read()
    extension = infer_image_extension(content_type, source_url)
    output_path = IMAGE_CACHE_DIR / f"{base_name}{extension}"
    tmp_path = IMAGE_TEMP_DIR / f"{base_name}{extension}.tmp"
    tmp_path.write_bytes(payload)
    tmp_path.replace(output_path)
    return output_path, content_type


def mark_audio_processing(conn: psycopg.Connection, lookup_key: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE audio_assets
            SET status = 'PROCESSING',
                failure_reason = NULL,
                updated_at = NOW()
            WHERE lookup_key = %s
            """,
            (lookup_key,),
        )


def mark_audio_ready(
    conn: psycopg.Connection,
    lookup_key: str,
    *,
    file_path: Path,
    duration_ms: int | None,
    thumbnail_url: str | None,
    source_webpage_url: str | None,
    source_stream_url: str | None,
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE audio_assets
            SET status = 'READY',
                file_path = %s,
                duration_ms = %s,
                thumbnail_url = %s,
                source_webpage_url = %s,
                source_stream_url = %s,
                processed_at = NOW(),
                failure_reason = NULL,
                updated_at = NOW()
            WHERE lookup_key = %s
            """,
            (
                str(file_path),
                duration_ms,
                thumbnail_url,
                source_webpage_url,
                source_stream_url,
                lookup_key,
            ),
        )


def mark_audio_failed(conn: psycopg.Connection, lookup_key: str, reason: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE audio_assets
            SET status = 'FAILED',
                failure_reason = %s,
                processed_at = NOW(),
                updated_at = NOW()
            WHERE lookup_key = %s
            """,
            (reason[:4000], lookup_key),
        )


def mark_image_processing(conn: psycopg.Connection, lookup_key: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE image_assets
            SET status = 'PROCESSING',
                failure_reason = NULL,
                updated_at = NOW()
            WHERE lookup_key = %s
            """,
            (lookup_key,),
        )


def mark_image_ready(
    conn: psycopg.Connection,
    lookup_key: str,
    *,
    file_path: Path,
    content_type: str,
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE image_assets
            SET status = 'READY',
                file_path = %s,
                content_type = %s,
                processed_at = NOW(),
                failure_reason = NULL,
                updated_at = NOW()
            WHERE lookup_key = %s
            """,
            (
                str(file_path),
                content_type,
                lookup_key,
            ),
        )


def mark_image_failed(conn: psycopg.Connection, lookup_key: str, reason: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE image_assets
            SET status = 'FAILED',
                failure_reason = %s,
                processed_at = NOW(),
                updated_at = NOW()
            WHERE lookup_key = %s
            """,
            (reason[:4000], lookup_key),
        )


def push_image_job(
    redis_conn: redis.Redis,
    *,
    entity_type: str,
    entity_key: str,
    source_url: str,
) -> None:
    lookup_key = hashlib.sha1(f"image:{entity_type}:{entity_key}".encode("utf-8")).hexdigest()
    redis_conn.lpush(
        IMAGE_QUEUE_KEY,
        json.dumps(
            {
                "lookup_key": lookup_key,
                "asset_key": lookup_key,
                "entity_type": entity_type,
                "entity_key": entity_key,
                "source_url": source_url,
            }
        ),
    )


def process_audio_job(conn: psycopg.Connection, redis_conn: redis.Redis, job: dict[str, Any]) -> None:
    lookup_key = str(job["lookup_key"])
    asset_key = str(job["asset_key"])
    query = str(job["query"])
    track_key = str(job.get("track_key") or "")
    logger.info("processing audio asset %s for %s", lookup_key, query)
    mark_audio_processing(conn, lookup_key)
    try:
        output_path, entry = download_audio_asset(query, asset_key)
        duration_seconds = entry.get("duration")
        duration_ms = int(duration_seconds * 1000) if duration_seconds else None
        thumbnail_url = entry.get("thumbnail")
        mark_audio_ready(
            conn,
            lookup_key,
            file_path=output_path,
            duration_ms=duration_ms,
            thumbnail_url=thumbnail_url,
            source_webpage_url=entry.get("webpage_url") or entry.get("original_url"),
            source_stream_url=entry.get("url"),
        )
        if track_key and thumbnail_url:
            push_image_job(
                redis_conn,
                entity_type="track",
                entity_key=track_key,
                source_url=thumbnail_url,
            )
        logger.info("audio asset ready %s -> %s", lookup_key, output_path.name)
    except Exception as exc:  # noqa: BLE001
        logger.exception("audio asset failed %s", lookup_key)
        mark_audio_failed(conn, lookup_key, str(exc))


def process_image_job(conn: psycopg.Connection, job: dict[str, Any]) -> None:
    lookup_key = str(job["lookup_key"])
    asset_key = str(job["asset_key"])
    source_url = str(job["source_url"])
    logger.info("processing image asset %s from %s", lookup_key, source_url)
    mark_image_processing(conn, lookup_key)
    try:
        output_path, content_type = download_image_asset(source_url, asset_key)
        mark_image_ready(
            conn,
            lookup_key,
            file_path=output_path,
            content_type=content_type,
        )
        logger.info("image asset ready %s -> %s", lookup_key, output_path.name)
    except Exception as exc:  # noqa: BLE001
        logger.exception("image asset failed %s", lookup_key)
        mark_image_failed(conn, lookup_key, str(exc))


def main() -> None:
    ensure_dir(MEDIA_CACHE_DIR)
    ensure_dir(TEMP_DIR)
    ensure_dir(IMAGE_CACHE_DIR)
    ensure_dir(IMAGE_TEMP_DIR)
    redis_conn = redis_client()
    conn = db_connection()
    logger.info(
        "media worker started audio_queue=%s image_queue=%s audio_dir=%s image_dir=%s",
        MEDIA_QUEUE_KEY,
        IMAGE_QUEUE_KEY,
        MEDIA_CACHE_DIR,
        IMAGE_CACHE_DIR,
    )

    while True:
        try:
            job = redis_conn.brpop([MEDIA_QUEUE_KEY, IMAGE_QUEUE_KEY], timeout=5)
            if not job:
                continue
            queue_name, payload = job
            parsed = json.loads(payload)
            if queue_name == MEDIA_QUEUE_KEY:
                process_audio_job(conn, redis_conn, parsed)
            else:
                process_image_job(conn, parsed)
        except (psycopg.Error, redis.RedisError) as exc:
            logger.warning("transient infra error: %s", exc)
            time.sleep(2)
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = db_connection()
            redis_conn = redis_client()
        except KeyboardInterrupt:
            break


if __name__ == "__main__":
    main()
