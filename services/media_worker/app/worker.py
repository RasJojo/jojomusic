from __future__ import annotations

import hashlib
import json
import logging
import mimetypes
import os
import re
import time
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from yt_dlp import YoutubeDL

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("jojomusic.media_worker")

CONVEX_URL = os.environ["CONVEX_URL"].rstrip("/")
CONVEX_ADMIN_KEY = os.environ["CONVEX_ADMIN_KEY"]
MEDIA_CACHE_DIR = Path(os.getenv("MEDIA_CACHE_DIR", "/data/audio_cache")).resolve()
IMAGE_CACHE_DIR = Path(os.getenv("IMAGE_CACHE_DIR", "/data/image_cache")).resolve()
TEMP_DIR = MEDIA_CACHE_DIR / ".tmp"
IMAGE_TEMP_DIR = IMAGE_CACHE_DIR / ".tmp"
TOR_PROXY = os.getenv("TOR_PROXY")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL_SECONDS", "3"))
USER_AGENT = "JojoMusic/1.0 (+https://jojomusicapi.jojoserv.com)"

NEGATIVE_HINTS = (
    "karaoke", "instrumental", "nightcore", "slowed", "sped up",
    "lyrics", "lyric video", "8d", "bass boosted", "fanmade", "amv",
    "reaction", "react", "review", "analyse", "critique", "interview",
    "podcast", "documentaire", "chronique", "debrief", "type beat",
    "free beat",
)
BLOCKED_NON_MUSIC_HINTS = (
    "du rap en mieux", "reaction", "react", "review", "analyse", "critique",
    "interview", "podcast", "documentaire", "chronique", "debrief",
    "le rab en mieux", "le rap en mieux", "type beat", "free beat",
)


# ── Convex HTTP helpers ───────────────────────────────────────────────────────

def _convex_call(kind: str, path: str, args: dict[str, Any]) -> Any:
    """Call a Convex query or mutation via HTTP API. Returns the value or None."""
    url = f"{CONVEX_URL}/api/{kind}"
    body = json.dumps({"path": path, "args": args, "format": "json"}).encode()
    req = Request(
        url,
        data=body,
        headers={
            "Authorization": f"Convex {CONVEX_ADMIN_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urlopen(req, timeout=15) as resp:  # noqa: S310
        data = json.loads(resp.read())
    if data.get("status") == "error":
        raise RuntimeError(f"Convex {kind} {path} failed: {data.get('errorMessage')}")
    return data.get("value")


def convex_mutation(path: str, args: dict[str, Any]) -> Any:
    return _convex_call("mutation", path, args)


def convex_query(path: str, args: dict[str, Any]) -> Any:
    return _convex_call("query", path, args)


# ── yt-dlp helpers ────────────────────────────────────────────────────────────

COOKIE_FILE = Path("/tmp/cookies.txt")


def _ensure_cookies() -> str | None:
    source = Path("/app/cookies.txt")
    if source.exists():
        import shutil
        shutil.copy2(source, COOKIE_FILE)
        return str(COOKIE_FILE)
    return None


def first_entry(info: dict[str, Any]) -> dict[str, Any]:
    entries = info.get("entries")
    if isinstance(entries, list) and entries:
        return entries[0]
    return info


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized.lower())
    return " ".join(normalized.split())


def token_overlap_score(query_text: str, candidate_text: str) -> float:
    query_tokens = set(normalize_text(query_text).split())
    candidate_tokens = set(normalize_text(candidate_text).split())
    if not query_tokens:
        return 0.0
    return len(query_tokens & candidate_tokens) / len(query_tokens)


def entry_artist(entry: dict[str, Any]) -> str:
    return str(
        entry.get("artist")
        or entry.get("uploader")
        or entry.get("uploaderName")
        or entry.get("channel")
        or ""
    )


def entry_video_url(entry: dict[str, Any]) -> str | None:
    raw = entry.get("webpage_url") or entry.get("url") or entry.get("id")
    if not raw:
        return None
    raw = str(raw)
    if raw.startswith("/watch?v="):
        return f"https://www.youtube.com{raw}"
    if re.fullmatch(r"[a-zA-Z0-9_-]{11}", raw):
        return f"https://www.youtube.com/watch?v={raw}"
    return raw


def has_blocked_non_music_hint(query: str, entry: dict[str, Any]) -> bool:
    query_text = normalize_text(query)
    combined = normalize_text(
        " ".join(
            str(entry.get(key) or "")
            for key in ("title", "artist", "uploader", "uploaderName", "channel")
        )
    )
    return any(hint in combined and hint not in query_text for hint in BLOCKED_NON_MUSIC_HINTS)


def candidate_score(query: str, entry: dict[str, Any]) -> float:
    query_text = normalize_text(query)
    title = str(entry.get("title") or "")
    artist = entry_artist(entry)
    combined = f"{artist} {title}"
    combined_text = normalize_text(combined)

    ratio = SequenceMatcher(None, query_text, combined_text).ratio()
    overlap = token_overlap_score(query, combined)
    title_overlap = token_overlap_score(query, title)
    artist_overlap = token_overlap_score(query, artist)
    score = ratio * 0.42 + overlap * 0.33 + title_overlap * 0.17 + artist_overlap * 0.08

    for hint in NEGATIVE_HINTS:
        if hint in combined_text and hint not in query_text:
            score -= 0.15
    if has_blocked_non_music_hint(query, entry):
        score -= 0.55
    if "official" in combined_text:
        score += 0.03
    if "topic" in normalize_text(artist):
        score += 0.02
    return score


def is_viable_candidate(query: str, entry: dict[str, Any]) -> bool:
    if not entry or not entry_video_url(entry) or has_blocked_non_music_hint(query, entry):
        return False
    combined = f"{entry_artist(entry)} {entry.get('title') or ''}".strip()
    if not combined:
        return False
    query_text = normalize_text(query)
    score = candidate_score(query, entry)
    overlap = token_overlap_score(query, combined)
    return score >= 0.58 or overlap >= 0.55 or (query_text and query_text in normalize_text(combined))


def query_variants(query: str) -> list[str]:
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


def select_best_entry(query: str, entries: list[dict[str, Any]]) -> dict[str, Any] | None:
    viable = [entry for entry in entries if is_viable_candidate(query, entry)]
    if not viable:
        return None
    return max(viable, key=lambda entry: candidate_score(query, entry))


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
        p for p in MEDIA_CACHE_DIR.glob(f"{base_name}.*")
        if p.is_file() and not p.name.endswith(".part")
    )
    if not matches:
        raise FileNotFoundError(f"no output file produced for {base_name}")
    return matches[0]


def find_best_audio_candidate(query: str, ydl_opts: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    search_opts = {
        key: value
        for key, value in ydl_opts.items()
        if key not in {"outtmpl", "paths", "postprocessors"}
    }
    search_opts.update({"extract_flat": True, "skip_download": True})
    entries: list[dict[str, Any]] = []
    with YoutubeDL(search_opts) as ydl:
        for variant in query_variants(query):
            info = ydl.extract_info(f"ytsearch12:{variant}", download=False)
            entries.extend([entry for entry in (info.get("entries") or []) if entry])

    best = select_best_entry(query, entries)
    best_url = entry_video_url(best or {})
    if not best or not best_url:
        raise RuntimeError(f"no viable YouTube result for {query}")
    logger.info(
        "selected audio candidate score=%.3f title=%s artist=%s",
        candidate_score(query, best),
        best.get("title") or query,
        entry_artist(best) or "unknown",
    )
    return best_url, best


def download_audio_asset(query: str, base_name: str) -> tuple[Path, dict[str, Any]]:
    ensure_dir(MEDIA_CACHE_DIR)
    ensure_dir(TEMP_DIR)
    clean_previous_outputs(MEDIA_CACHE_DIR, base_name)
    output_template = str(MEDIA_CACHE_DIR / f"{base_name}.%(ext)s")
    ydl_opts: dict[str, Any] = {
        "format": "bestaudio[ext=m4a]/bestaudio[acodec*=aac]/bestaudio/best",
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
        "concurrent_fragment_downloads": 1,
        "prefer_ffmpeg": True,
        "remote_components": ["ejs:github"],
        "extractor_args": {
            "youtube": {
                "player_client": ["android", "ios", "web"],
            },
        },
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "m4a",
                "preferredquality": "192",
            }
        ],
    }
    cookie_path = _ensure_cookies()
    if cookie_path:
        ydl_opts["cookiefile"] = cookie_path
    best_url, search_entry = find_best_audio_candidate(query, ydl_opts)
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(best_url, download=True)
        entry = first_entry(info)
    if search_entry.get("thumbnail") and not entry.get("thumbnail"):
        entry["thumbnail"] = search_entry.get("thumbnail")
    return find_output_path(base_name), entry


def infer_image_extension(content_type: str | None, source_url: str) -> str:
    normalized = (content_type or "").split(";", 1)[0].strip().lower()
    if normalized:
        guessed = mimetypes.guess_extension(normalized)
        if guessed:
            return ".jpg" if guessed == ".jpe" else guessed
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


# ── Job processors ────────────────────────────────────────────────────────────

def push_image_job(entity_type: str, entity_key: str, source_url: str) -> None:
    lookup_key = hashlib.sha1(
        f"image:{entity_type}:{entity_key}".encode()
    ).hexdigest()
    convex_mutation(
        "imageAssets:enqueue",
        {
            "lookupKey": lookup_key,
            "assetKey": lookup_key,
            "entityType": entity_type,
            "entityKey": entity_key,
            "sourceUrl": source_url,
        },
    )


def process_audio_job(job: dict[str, Any]) -> None:
    lookup_key = str(job["lookupKey"])
    asset_key = str(job["assetKey"])
    query = str(job["query"])
    track_key = str(job.get("trackKey") or "")
    logger.info("processing audio %s for %s", lookup_key, query)
    try:
        output_path, entry = download_audio_asset(query, asset_key)
        duration_seconds = entry.get("duration")
        duration_ms = int(duration_seconds * 1000) if duration_seconds else None
        thumbnail_url = entry.get("thumbnail")
        convex_mutation(
            "audioAssets:markReady",
            {
                "lookupKey": lookup_key,
                "filePath": str(output_path),
                "durationMs": duration_ms,
                "thumbnailUrl": thumbnail_url,
                "sourceWebpageUrl": entry.get("webpage_url") or entry.get("original_url"),
                "sourceStreamUrl": entry.get("url"),
            },
        )
        if track_key and thumbnail_url:
            push_image_job("track", track_key, thumbnail_url)
        logger.info("audio ready %s → %s", lookup_key, output_path.name)
    except Exception as exc:  # noqa: BLE001
        logger.exception("audio failed %s", lookup_key)
        convex_mutation(
            "audioAssets:markFailed",
            {"lookupKey": lookup_key, "reason": str(exc)},
        )


def process_image_job(job: dict[str, Any]) -> None:
    lookup_key = str(job["lookupKey"])
    asset_key = str(job["assetKey"])
    source_url = str(job["sourceUrl"])
    logger.info("processing image %s from %s", lookup_key, source_url)
    try:
        output_path, content_type = download_image_asset(source_url, asset_key)
        convex_mutation(
            "imageAssets:markReady",
            {
                "lookupKey": lookup_key,
                "filePath": str(output_path),
                "contentType": content_type,
            },
        )
        logger.info("image ready %s → %s", lookup_key, output_path.name)
    except Exception as exc:  # noqa: BLE001
        logger.exception("image failed %s", lookup_key)
        convex_mutation(
            "imageAssets:markFailed",
            {"lookupKey": lookup_key, "reason": str(exc)},
        )


# ── Main loop ─────────────────────────────────────────────────────────────────

def main() -> None:
    for d in [MEDIA_CACHE_DIR, TEMP_DIR, IMAGE_CACHE_DIR, IMAGE_TEMP_DIR]:
        ensure_dir(d)

    logger.info(
        "media worker started convex=%s audio_dir=%s image_dir=%s poll=%ss",
        CONVEX_URL,
        MEDIA_CACHE_DIR,
        IMAGE_CACHE_DIR,
        POLL_INTERVAL,
    )

    while True:
        try:
            # Try audio job first, then image job
            audio_job = convex_mutation("audioAssets:claimQueued", {})
            if audio_job:
                process_audio_job(audio_job)
                continue  # check again immediately

            image_job = convex_mutation("imageAssets:claimQueued", {})
            if image_job:
                process_image_job(image_job)
                continue  # check again immediately

            # Nothing queued — wait before polling again
            time.sleep(POLL_INTERVAL)

        except OSError as exc:
            logger.warning("transient error: %s — retrying in 5s", exc)
            time.sleep(5)
        except KeyboardInterrupt:
            break


if __name__ == "__main__":
    main()
