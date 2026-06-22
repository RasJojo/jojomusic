from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from yt_dlp import YoutubeDL
from yt_dlp.cookies import extract_cookies_from_browser

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("jojomusic.youtube_cookie_refresher")


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        logger.warning("Invalid integer env %s=%r, using %s", name, raw, default)
        return default


BROWSER = os.getenv("YOUTUBE_COOKIE_BROWSER", "firefox")
PROFILE_ROOT = Path(os.getenv("YOUTUBE_COOKIE_PROFILE", "/browser-profile")).resolve()
OUTPUT_FILE = Path(os.getenv("YOUTUBE_COOKIE_OUTPUT", "/cookies/cookies.txt")).resolve()
STATUS_FILE = Path(os.getenv("YOUTUBE_COOKIE_STATUS", "/cookies/cookies.status.json")).resolve()
VALIDATE_URL = os.getenv(
    "YOUTUBE_COOKIE_VALIDATE_URL",
    "https://www.youtube.com/watch?v=d27gTrPPAyk",
)
VALIDATE_PROXY = os.getenv("YOUTUBE_COOKIE_VALIDATE_PROXY", "").strip() or None
POT_PROVIDER_URL = os.getenv("YOUTUBE_POT_PROVIDER_URL", "").strip() or None
REFRESH_INTERVAL_SECONDS = env_int("YOUTUBE_COOKIE_REFRESH_INTERVAL_SECONDS", 6 * 60 * 60)
INITIAL_DELAY_SECONDS = env_int("YOUTUBE_COOKIE_INITIAL_DELAY_SECONDS", 0)
MIN_YOUTUBE_COOKIES = env_int("YOUTUBE_COOKIE_MIN_COUNT", 4)
RUN_ONCE = env_bool("YOUTUBE_COOKIE_RUN_ONCE")


def now_iso() -> str:
    return datetime.now(UTC).isoformat()


def write_status(ok: bool, **extra: Any) -> None:
    STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "ok": ok,
        "checked_at": now_iso(),
        **extra,
    }
    tmp = STATUS_FILE.with_suffix(f"{STATUS_FILE.suffix}.tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(STATUS_FILE)


def locate_profile(browser: str, root: Path) -> Path:
    if not root.exists():
        raise FileNotFoundError(f"browser profile root does not exist: {root}")

    marker_names = {
        "firefox": {"cookies.sqlite"},
        "chromium": {"Cookies"},
        "chrome": {"Cookies"},
        "brave": {"Cookies"},
        "edge": {"Cookies"},
    }.get(browser.lower(), {"cookies.sqlite", "Cookies"})

    if any((root / marker).exists() for marker in marker_names):
        return root

    matches: list[Path] = []
    for marker in marker_names:
        matches.extend(root.rglob(marker))
    if not matches:
        raise FileNotFoundError(
            f"no browser cookie database found under {root} for browser={browser}",
        )
    matches.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return matches[0].parent


def export_cookie_file(candidate: Path) -> int:
    profile = locate_profile(BROWSER, PROFILE_ROOT)
    logger.info("Exporting cookies browser=%s profile=%s", BROWSER, profile)
    jar = extract_cookies_from_browser(BROWSER, profile=str(profile))
    youtube_cookie_count = sum(
        1
        for cookie in jar
        if "youtube" in cookie.domain.lower() or "google" in cookie.domain.lower()
    )
    if youtube_cookie_count < MIN_YOUTUBE_COOKIES:
        raise RuntimeError(
            f"not enough YouTube/Google cookies exported: {youtube_cookie_count}",
        )

    candidate.parent.mkdir(parents=True, exist_ok=True)
    jar.save(str(candidate), ignore_discard=True, ignore_expires=True)
    candidate.chmod(0o600)
    return youtube_cookie_count


def validate_cookie_file(candidate: Path) -> dict[str, Any]:
    extractor_args: dict[str, dict[str, list[str]]] = {
        "youtube": {
            "player_client": ["mweb", "web_safari", "web", "android", "ios"],
        },
    }
    if POT_PROVIDER_URL:
        extractor_args["youtubepot-bgutilhttp"] = {
            "base_url": [POT_PROVIDER_URL.rstrip("/")],
        }
    opts: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": env_int("YOUTUBE_COOKIE_VALIDATE_TIMEOUT_SECONDS", 25),
        "cachedir": False,
        "cookiefile": str(candidate),
        "format": "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio/best",
        "extractor_args": extractor_args,
    }
    if VALIDATE_PROXY:
        opts["proxy"] = VALIDATE_PROXY

    with YoutubeDL(opts) as ydl:
        info = ydl.extract_info(VALIDATE_URL, download=False)

    if not info:
        raise RuntimeError("yt-dlp returned no info during validation")
    if not info.get("url") and not info.get("formats"):
        raise RuntimeError("yt-dlp validation returned no playable formats")
    return {
        "title": info.get("title"),
        "duration": info.get("duration"),
        "extractor": info.get("extractor_key"),
    }


def install_cookie_file(candidate: Path) -> None:
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    backup = OUTPUT_FILE.with_suffix(f"{OUTPUT_FILE.suffix}.previous")
    if OUTPUT_FILE.exists() and OUTPUT_FILE.stat().st_size > 0:
        backup.write_bytes(OUTPUT_FILE.read_bytes())
        backup.chmod(0o600)
    candidate.replace(OUTPUT_FILE)
    OUTPUT_FILE.chmod(0o600)


def refresh_once() -> bool:
    candidate = OUTPUT_FILE.with_suffix(f"{OUTPUT_FILE.suffix}.next")
    candidate.unlink(missing_ok=True)
    try:
        cookie_count = export_cookie_file(candidate)
        validation = validate_cookie_file(candidate)
        install_cookie_file(candidate)
        write_status(
            True,
            installed_at=now_iso(),
            browser=BROWSER,
            profile=str(locate_profile(BROWSER, PROFILE_ROOT)),
            cookie_count=cookie_count,
            validate_url=VALIDATE_URL,
            pot_provider_configured=bool(POT_PROVIDER_URL),
            validation=validation,
            output=str(OUTPUT_FILE),
        )
        logger.info("Installed validated YouTube cookies count=%s", cookie_count)
        return True
    except Exception as exc:  # noqa: BLE001
        candidate.unlink(missing_ok=True)
        write_status(
            False,
            browser=BROWSER,
            profile_root=str(PROFILE_ROOT),
            validate_url=VALIDATE_URL,
            pot_provider_configured=bool(POT_PROVIDER_URL),
            output=str(OUTPUT_FILE),
            error=repr(exc),
        )
        logger.exception("Cookie refresh failed; existing cookie file left untouched")
        return False


def main() -> int:
    if INITIAL_DELAY_SECONDS > 0:
        time.sleep(INITIAL_DELAY_SECONDS)

    if RUN_ONCE:
        return 0 if refresh_once() else 1

    while True:
        refresh_once()
        time.sleep(max(60, REFRESH_INTERVAL_SECONDS))


if __name__ == "__main__":
    sys.exit(main())
