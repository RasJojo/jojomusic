#!/usr/bin/env python3
"""
Migrate jojomusic data from PostgreSQL (NestJS) to Convex self-hosted.

Usage:
  python3 migrate_to_convex.py [--dry-run] [--only users,playlists,saved_tracks,podcasts,playback_events,audio_assets]

Environment variables:
  DATABASE_URL   PostgreSQL DSN  (default: postgresql://jojo:jojo@localhost:5432/jojomusic)
  CONVEX_URL     Convex API base (default: https://convex.jojoserv.com)
  CONVEX_ADMIN_KEY  Convex admin key (required for direct DB mutations bypassing auth)
"""
import argparse
import json
import os
import sys
import time
from typing import Any

import psycopg2
import psycopg2.extras
import requests

# ── Config ─────────────────────────────────────────────────────────────────────

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://jojo:jojo@localhost:5432/jojomusic"
)
CONVEX_URL = os.getenv("CONVEX_URL", "https://convex.jojoserv.com").rstrip("/")
CONVEX_ADMIN_KEY = os.getenv(
    "CONVEX_ADMIN_KEY",
    "convex-self-hosted|0109ec82a1c77dc4ed33ecc93393d6ae855c5b4cd66e3ed4f14fb68755964e38efa7723782",
)

MUTATION_URL = f"{CONVEX_URL}/api/mutation"
QUERY_URL = f"{CONVEX_URL}/api/query"

HEADERS = {
    "Content-Type": "application/json",
    "Authorization": f"Convex {CONVEX_ADMIN_KEY}",
}

# ── HTTP helpers ───────────────────────────────────────────────────────────────

def convex_mutation(name: str, args: dict[str, Any], dry_run: bool = False) -> Any:
    if dry_run:
        print(f"  [DRY] mutation {name} args={json.dumps(args)[:120]}")
        return "__dry_run__"
    resp = requests.post(
        MUTATION_URL,
        headers=HEADERS,
        json={"path": name, "args": args},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    if data.get("status") == "error":
        raise RuntimeError(f"Convex error on {name}: {data.get('errorMessage')}")
    return data.get("value")


def convex_query(name: str, args: dict[str, Any]) -> Any:
    resp = requests.post(
        QUERY_URL,
        headers=HEADERS,
        json={"path": name, "args": args},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    if data.get("status") == "error":
        raise RuntimeError(f"Convex query error on {name}: {data.get('errorMessage')}")
    return data.get("value")


# ── Progress helper ────────────────────────────────────────────────────────────

class Progress:
    def __init__(self, label: str, total: int):
        self.label = label
        self.total = total
        self.done = 0
        self.errors = 0
        self._t0 = time.time()

    def tick(self, ok: bool = True):
        self.done += 1
        if not ok:
            self.errors += 1
        if self.done % 50 == 0 or self.done == self.total:
            elapsed = time.time() - self._t0
            print(
                f"  {self.label}: {self.done}/{self.total} "
                f"({self.errors} errors) — {elapsed:.1f}s"
            )

    def summary(self):
        elapsed = time.time() - self._t0
        print(
            f"  ✓ {self.label} done: {self.done - self.errors}/{self.total} migrated, "
            f"{self.errors} errors — {elapsed:.1f}s"
        )


# ── Migration sections ─────────────────────────────────────────────────────────

def migrate_users(cur, dry_run: bool) -> dict[str, str]:
    """Upsert all users; return {postgres_uuid → convex_id} map."""
    cur.execute("SELECT id, email, name FROM users ORDER BY created_at")
    rows = cur.fetchall()
    print(f"\n[users] {len(rows)} rows")
    pg_to_convex: dict[str, str] = {}
    prog = Progress("users", len(rows))

    for row in rows:
        try:
            convex_id = convex_mutation(
                "auth:upsertByExternalId",
                {"externalId": row["id"], "name": row["name"], "email": row["email"]},
                dry_run=dry_run,
            )
            pg_to_convex[row["id"]] = convex_id if convex_id else "__dry__"
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR user {row['id']}: {exc}")
            prog.tick(False)

    prog.summary()
    return pg_to_convex


def migrate_playlists(cur, user_map: dict[str, str], dry_run: bool) -> dict[str, str]:
    """Create playlists (without tracks); return {pg_playlist_id → convex_playlist_id}."""
    cur.execute(
        "SELECT id, user_id, name, description, artwork_url "
        "FROM playlists ORDER BY created_at"
    )
    rows = cur.fetchall()
    print(f"\n[playlists] {len(rows)} rows")
    pl_map: dict[str, str] = {}
    prog = Progress("playlists", len(rows))

    for row in rows:
        convex_user_id = user_map.get(row["user_id"])
        if not convex_user_id:
            print(f"  SKIP playlist {row['id']}: unknown user {row['user_id']}")
            prog.tick(False)
            continue
        try:
            args: dict[str, Any] = {
                "userId": convex_user_id,
                "name": row["name"],
                "description": row["description"] or "",
            }
            if row["artwork_url"]:
                args["artworkUrl"] = row["artwork_url"]
            convex_pl_id = convex_mutation("playlists:create", args, dry_run=dry_run)
            pl_map[row["id"]] = convex_pl_id if convex_pl_id else "__dry__"
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR playlist {row['id']}: {exc}")
            prog.tick(False)

    prog.summary()
    return pl_map


def migrate_playlist_tracks(
    cur, user_map: dict[str, str], pl_map: dict[str, str], dry_run: bool
):
    """Add tracks to each migrated playlist, preserving position order."""
    cur.execute(
        "SELECT pt.playlist_id, pt.track_key, pt.track_payload, pt.position, "
        "       p.user_id "
        "FROM playlist_tracks pt "
        "JOIN playlists p ON p.id = pt.playlist_id "
        "ORDER BY pt.playlist_id, pt.position"
    )
    rows = cur.fetchall()
    print(f"\n[playlist_tracks] {len(rows)} rows")
    prog = Progress("playlist_tracks", len(rows))

    for row in rows:
        convex_pl_id = pl_map.get(row["playlist_id"])
        convex_user_id = user_map.get(row["user_id"])
        if not convex_pl_id or not convex_user_id:
            prog.tick(False)
            continue
        try:
            convex_mutation(
                "playlists:addTrack",
                {
                    "playlistId": convex_pl_id,
                    "userId": convex_user_id,
                    "trackKey": row["track_key"],
                    "trackPayload": row["track_payload"],
                },
                dry_run=dry_run,
            )
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR track {row['track_key']} in playlist {row['playlist_id']}: {exc}")
            prog.tick(False)

    prog.summary()


def migrate_saved_tracks(cur, user_map: dict[str, str], dry_run: bool):
    cur.execute(
        "SELECT user_id, track_key, track_payload FROM saved_tracks ORDER BY created_at"
    )
    rows = cur.fetchall()
    print(f"\n[saved_tracks] {len(rows)} rows")
    prog = Progress("saved_tracks", len(rows))

    for row in rows:
        convex_user_id = user_map.get(row["user_id"])
        if not convex_user_id:
            prog.tick(False)
            continue
        try:
            convex_mutation(
                "savedTracks:save",
                {
                    "userId": convex_user_id,
                    "trackKey": row["track_key"],
                    "trackPayload": row["track_payload"],
                },
                dry_run=dry_run,
            )
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR savedTrack {row['track_key']}: {exc}")
            prog.tick(False)

    prog.summary()


def migrate_podcast_shows(cur, user_map: dict[str, str], dry_run: bool):
    cur.execute(
        "SELECT user_id, podcast_key, podcast_payload FROM saved_podcast_shows ORDER BY created_at"
    )
    rows = cur.fetchall()
    print(f"\n[saved_podcast_shows] {len(rows)} rows")
    prog = Progress("podcast_shows", len(rows))

    for row in rows:
        convex_user_id = user_map.get(row["user_id"])
        if not convex_user_id:
            prog.tick(False)
            continue
        try:
            convex_mutation(
                "podcasts:saveShow",
                {
                    "userId": convex_user_id,
                    "podcastKey": row["podcast_key"],
                    "podcastPayload": row["podcast_payload"],
                },
                dry_run=dry_run,
            )
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR podcast {row['podcast_key']}: {exc}")
            prog.tick(False)

    prog.summary()


def migrate_podcast_episodes(cur, user_map: dict[str, str], dry_run: bool):
    cur.execute(
        "SELECT user_id, episode_key, episode_payload FROM saved_podcast_episodes ORDER BY created_at"
    )
    rows = cur.fetchall()
    print(f"\n[saved_podcast_episodes] {len(rows)} rows")
    prog = Progress("podcast_episodes", len(rows))

    for row in rows:
        convex_user_id = user_map.get(row["user_id"])
        if not convex_user_id:
            prog.tick(False)
            continue
        try:
            convex_mutation(
                "podcasts:saveEpisode",
                {
                    "userId": convex_user_id,
                    "episodeKey": row["episode_key"],
                    "episodePayload": row["episode_payload"],
                },
                dry_run=dry_run,
            )
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR episode {row['episode_key']}: {exc}")
            prog.tick(False)

    prog.summary()


def migrate_playback_events(cur, user_map: dict[str, str], dry_run: bool):
    cur.execute(
        "SELECT user_id, track_key, event_type, listened_ms, completion_ratio, "
        "       track_payload FROM playback_events ORDER BY created_at LIMIT 50000"
    )
    rows = cur.fetchall()
    print(f"\n[playback_events] {len(rows)} rows (capped at 50k most recent)")
    prog = Progress("playback_events", len(rows))

    for row in rows:
        convex_user_id = user_map.get(row["user_id"])
        if not convex_user_id:
            prog.tick(False)
            continue
        try:
            convex_mutation(
                "playbackEvents:record",
                {
                    "userId": convex_user_id,
                    "trackKey": row["track_key"],
                    "eventType": row["event_type"],
                    "listenedMs": row["listened_ms"],
                    "completionRatio": float(row["completion_ratio"]),
                    "trackPayload": row["track_payload"],
                },
                dry_run=dry_run,
            )
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR playbackEvent {row['track_key']}: {exc}")
            prog.tick(False)

    prog.summary()


def migrate_audio_assets(cur, dry_run: bool):
    cur.execute(
        "SELECT lookup_key, track_key, query, title, artist, asset_key, status, "
        "       file_path, public_path, thumbnail_url, duration_ms, source, "
        "       source_webpage_url, source_stream_url, failure_reason "
        "FROM audio_assets ORDER BY requested_at"
    )
    rows = cur.fetchall()
    print(f"\n[audio_assets] {len(rows)} rows")
    prog = Progress("audio_assets", len(rows))

    for row in rows:
        try:
            args: dict[str, Any] = {
                "lookupKey": row["lookup_key"],
                "trackKey": row["track_key"],
                "query": row["query"],
                "title": row["title"],
                "artist": row["artist"],
                "assetKey": row["asset_key"],
                "status": row["status"].lower(),
                "source": row["source"] or "youtube",
            }
            if row["file_path"]:
                args["filePath"] = row["file_path"]
            if row["public_path"]:
                args["publicPath"] = row["public_path"]
            if row["thumbnail_url"]:
                args["thumbnailUrl"] = row["thumbnail_url"]
            if row["duration_ms"] is not None:
                args["durationMs"] = row["duration_ms"]
            if row["source_webpage_url"]:
                args["sourceWebpageUrl"] = row["source_webpage_url"]
            if row["source_stream_url"]:
                args["sourceStreamUrl"] = row["source_stream_url"]
            if row["failure_reason"]:
                args["failureReason"] = row["failure_reason"]
            convex_mutation("audioAssets:upsert", args, dry_run=dry_run)
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR audioAsset {row['lookup_key']}: {exc}")
            prog.tick(False)

    prog.summary()


def migrate_spotify_links(cur, user_map: dict[str, str], dry_run: bool):
    cur.execute(
        "SELECT user_id, spotify_user_id, display_name, email, avatar_url, "
        "       country, product "
        "FROM spotify_account_links ORDER BY created_at"
    )
    rows = cur.fetchall()
    print(f"\n[spotify_account_links] {len(rows)} rows")
    prog = Progress("spotify_links", len(rows))

    for row in rows:
        convex_user_id = user_map.get(row["user_id"])
        if not convex_user_id:
            prog.tick(False)
            continue
        try:
            args: dict[str, Any] = {
                "userId": convex_user_id,
                "spotifyUserId": row["spotify_user_id"],
            }
            if row["display_name"]:
                args["displayName"] = row["display_name"]
            if row["email"]:
                args["email"] = row["email"]
            if row["avatar_url"]:
                args["avatarUrl"] = row["avatar_url"]
            if row["country"]:
                args["country"] = row["country"]
            if row["product"]:
                args["product"] = row["product"]
            convex_mutation("spotify:upsert", args, dry_run=dry_run)
            prog.tick(True)
        except Exception as exc:
            print(f"  ERROR spotify {row['spotify_user_id']}: {exc}")
            prog.tick(False)

    prog.summary()


# ── Entry point ────────────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be sent without making any Convex API calls",
    )
    parser.add_argument(
        "--only",
        default="",
        help="Comma-separated list of sections to run: users,playlists,saved_tracks,podcasts,playback_events,audio_assets,spotify",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    only = set(args.only.split(",")) if args.only else set()

    def should_run(section: str) -> bool:
        return not only or section in only

    print(f"Connecting to PostgreSQL: {DATABASE_URL.split('@')[-1]}")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    print(f"Convex URL: {CONVEX_URL}")
    if args.dry_run:
        print("⚠️  DRY RUN — no data will be written to Convex")

    user_map: dict[str, str] = {}
    pl_map: dict[str, str] = {}

    if should_run("users"):
        user_map = migrate_users(cur, args.dry_run)
    else:
        # Build the map from a quick query so dependent steps still work
        print("\n[users] skipped — building lookup map from Convex queries…")
        cur.execute("SELECT id, email, name FROM users")
        for row in cur.fetchall():
            try:
                result = convex_query(
                    "auth:getByExternalId", {"externalId": row["id"]}
                )
                if result and result.get("_id"):
                    user_map[row["id"]] = result["_id"]
            except Exception:
                pass
        print(f"  {len(user_map)} users found in Convex")

    if should_run("playlists"):
        pl_map = migrate_playlists(cur, user_map, args.dry_run)
        migrate_playlist_tracks(cur, user_map, pl_map, args.dry_run)

    if should_run("saved_tracks"):
        migrate_saved_tracks(cur, user_map, args.dry_run)

    if should_run("podcasts"):
        migrate_podcast_shows(cur, user_map, args.dry_run)
        migrate_podcast_episodes(cur, user_map, args.dry_run)

    if should_run("playback_events"):
        migrate_playback_events(cur, user_map, args.dry_run)

    if should_run("audio_assets"):
        migrate_audio_assets(cur, args.dry_run)

    if should_run("spotify"):
        migrate_spotify_links(cur, user_map, args.dry_run)

    cur.close()
    conn.close()
    print("\n🎉 Migration complete.")


if __name__ == "__main__":
    main()
