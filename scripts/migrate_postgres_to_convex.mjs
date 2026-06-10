#!/usr/bin/env node
/**
 * Migration script: PostgreSQL → Convex (jojomusic)
 * Reads exported JSON files from /tmp/jojomusic_*.json and imports to Convex.
 */

import { readFileSync } from "fs";

const CONVEX_URL = "https://convex.jojoserv.com";
const ADMIN_KEY =
  "convex-self-hosted|0109ec82a1c77dc4ed33ecc93393d6ae855c5b4cd66e3ed4f14fb68755964e38efa7723782";
const BATCH_SIZE = 50;

// ── Helpers ───────────────────────────────────────────────────────────────────

async function callMutation(path, args) {
  const res = await fetch(`${CONVEX_URL}/api/mutation`, {
    method: "POST",
    headers: {
      Authorization: `Convex ${ADMIN_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ path, args, format: "json" }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Mutation ${path} failed (${res.status}): ${text}`);
  }
  const json = JSON.parse(text);
  if (json.status === "error") {
    throw new Error(`Mutation ${path} error: ${json.errorMessage}`);
  }
  return json.value;
}

function readJson(path) {
  const raw = readFileSync(path, "utf-8").trim();
  if (!raw || raw === "null") return [];
  return JSON.parse(raw);
}

function chunk(arr, size) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

function toMs(ts) {
  if (!ts) return undefined;
  return new Date(ts).getTime();
}

function normalizeStatus(s) {
  if (!s) return "queued";
  const map = { QUEUED: "queued", PROCESSING: "processing", READY: "ready", FAILED: "failed" };
  return map[s.toUpperCase()] ?? "queued";
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log("=== JojoMusic PostgreSQL → Convex Migration ===\n");

  // 1. Load all data
  const pgUsers = readJson("/tmp/jojomusic_users.json");
  const pgPlaylists = readJson("/tmp/jojomusic_playlists.json");
  const pgPlaylistTracks = readJson("/tmp/jojomusic_playlist_tracks.json");
  const pgSavedTracks = readJson("/tmp/jojomusic_saved_tracks.json");
  const pgPlaybackEvents = readJson("/tmp/jojomusic_playback_events.json");
  const pgSavedAlbums = readJson("/tmp/jojomusic_saved_albums.json");
  const pgSavedPodcastShows = readJson("/tmp/jojomusic_saved_podcast_shows.json");
  const pgAudioAssets = readJson("/tmp/jojomusic_audio_assets.json");
  const pgImageAssets = readJson("/tmp/jojomusic_image_assets.json");

  console.log(`Users: ${pgUsers.length}`);
  console.log(`Playlists: ${pgPlaylists.length}`);
  console.log(`Playlist tracks: ${pgPlaylistTracks.length}`);
  console.log(`Saved tracks: ${pgSavedTracks.length}`);
  console.log(`Playback events: ${pgPlaybackEvents.length}`);
  console.log(`Saved albums: ${pgSavedAlbums.length}`);
  console.log(`Saved podcast shows: ${pgSavedPodcastShows.length}`);
  console.log(`Audio assets: ${pgAudioAssets.length}`);
  console.log(`Image assets: ${pgImageAssets.length}\n`);

  // 2. Migrate users — build pgId → convexId map
  console.log("── Migrating users...");
  const userIdMap = new Map(); // pgId → convexId
  for (const u of pgUsers) {
    const convexId = await callMutation("migration:importUser", {
      externalId: u.id,
      email: u.email,
      name: u.name,
      passwordHash: u.password_hash,
    });
    userIdMap.set(u.id, convexId);
    console.log(`  ✓ ${u.email} → ${convexId}`);
  }
  console.log(`  Done: ${userIdMap.size} users\n`);

  // 3. Migrate playlists — build pgPlaylistId → convexPlaylistId map
  console.log("── Migrating playlists...");
  const playlistIdMap = new Map();
  for (const p of pgPlaylists) {
    const convexUserId = userIdMap.get(p.user_id);
    if (!convexUserId) {
      console.warn(`  SKIP playlist ${p.id}: user ${p.user_id} not found`);
      continue;
    }
    const convexId = await callMutation("migration:importPlaylist", {
      convexUserId,
      name: p.name,
      description: p.description ?? "",
      artworkUrl: p.artwork_url ?? undefined,
    });
    playlistIdMap.set(p.id, convexId);
    console.log(`  ✓ "${p.name}" (${p.id.slice(0, 8)}) → ${convexId}`);
  }
  console.log(`  Done: ${playlistIdMap.size} playlists\n`);

  // 4. Migrate playlist tracks (batched)
  console.log("── Migrating playlist tracks...");
  const mappedTracks = pgPlaylistTracks
    .map((t) => {
      const convexPlaylistId = playlistIdMap.get(t.playlist_id);
      if (!convexPlaylistId) return null;
      return {
        convexPlaylistId,
        trackKey: t.track_key,
        position: t.position,
        trackPayload: t.track_payload,
      };
    })
    .filter(Boolean);

  let imported = 0;
  for (const batch of chunk(mappedTracks, BATCH_SIZE)) {
    await callMutation("migration:importPlaylistTrackBatch", { tracks: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedTracks.length}`);
  }
  console.log(`\n  Done: ${imported} playlist tracks\n`);

  // 5. Migrate saved tracks (batched)
  console.log("── Migrating saved tracks...");
  const mappedSavedTracks = pgSavedTracks
    .map((t) => {
      const convexUserId = userIdMap.get(t.user_id);
      if (!convexUserId) return null;
      return {
        convexUserId,
        trackKey: t.track_key,
        trackPayload: t.track_payload,
      };
    })
    .filter(Boolean);

  imported = 0;
  for (const batch of chunk(mappedSavedTracks, BATCH_SIZE)) {
    await callMutation("migration:importSavedTrackBatch", { tracks: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedSavedTracks.length}`);
  }
  console.log(`\n  Done: ${imported} saved tracks\n`);

  // 6. Migrate playback events (batched)
  console.log("── Migrating playback events...");
  const mappedEvents = pgPlaybackEvents
    .map((e) => {
      const convexUserId = userIdMap.get(e.user_id);
      if (!convexUserId) return null;
      return {
        convexUserId,
        trackKey: e.track_key,
        eventType: e.event_type,
        listenedMs: e.listened_ms ?? 0,
        completionRatio: e.completion_ratio ?? 0,
        trackPayload: e.track_payload,
      };
    })
    .filter(Boolean);

  imported = 0;
  for (const batch of chunk(mappedEvents, BATCH_SIZE)) {
    await callMutation("migration:importPlaybackEventBatch", { events: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedEvents.length}`);
  }
  console.log(`\n  Done: ${imported} playback events\n`);

  // 7. Migrate saved albums (batched)
  console.log("── Migrating saved albums...");
  const mappedAlbums = pgSavedAlbums
    .map((a) => {
      const convexUserId = userIdMap.get(a.user_id);
      if (!convexUserId) return null;
      return {
        convexUserId,
        albumKey: a.album_key,
        albumPayload: a.album_payload,
      };
    })
    .filter(Boolean);

  imported = 0;
  for (const batch of chunk(mappedAlbums, BATCH_SIZE)) {
    await callMutation("migration:importSavedAlbumBatch", { albums: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedAlbums.length}`);
  }
  console.log(`\n  Done: ${imported} saved albums\n`);

  // 8. Migrate saved podcast shows (batched)
  console.log("── Migrating saved podcast shows...");
  const mappedShows = pgSavedPodcastShows
    .map((s) => {
      const convexUserId = userIdMap.get(s.user_id);
      if (!convexUserId) return null;
      return {
        convexUserId,
        podcastKey: s.podcast_key,
        podcastPayload: s.podcast_payload,
      };
    })
    .filter(Boolean);

  imported = 0;
  for (const batch of chunk(mappedShows, BATCH_SIZE)) {
    await callMutation("migration:importSavedPodcastShowBatch", { shows: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedShows.length}`);
  }
  console.log(`\n  Done: ${imported} podcast shows\n`);

  // 9. Migrate audio assets (batched — 2403 rows)
  console.log("── Migrating audio assets...");
  const mappedAudio = pgAudioAssets.map((a) => ({
    lookupKey: a.lookup_key,
    trackKey: a.track_key,
    query: a.query,
    title: a.title,
    artist: a.artist,
    assetKey: a.asset_key,
    status: normalizeStatus(a.status),
    filePath: a.file_path ?? undefined,
    publicPath: a.public_path ?? undefined,
    thumbnailUrl: a.thumbnail_url ?? undefined,
    durationMs: a.duration_ms ?? undefined,
    source: a.source ?? "youtube",
    sourceWebpageUrl: a.source_webpage_url ?? undefined,
    sourceStreamUrl: a.source_stream_url ?? undefined,
    failureReason: a.failure_reason ?? undefined,
    lastQueuedAt: toMs(a.last_queued_at),
    processedAt: toMs(a.processed_at),
    expiresAt: toMs(a.expires_at),
  }));

  imported = 0;
  for (const batch of chunk(mappedAudio, BATCH_SIZE)) {
    await callMutation("migration:importAudioAssetBatch", { assets: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedAudio.length}`);
  }
  console.log(`\n  Done: ${imported} audio assets\n`);

  // 10. Migrate image assets (batched — 7707 rows)
  console.log("── Migrating image assets...");
  const mappedImages = pgImageAssets.map((a) => ({
    lookupKey: a.lookup_key,
    entityType: a.entity_type,
    entityKey: a.entity_key,
    sourceUrl: a.source_url,
    assetKey: a.asset_key,
    status: normalizeStatus(a.status),
    filePath: a.file_path ?? undefined,
    publicPath: a.public_path ?? undefined,
    contentType: a.content_type ?? undefined,
    failureReason: a.failure_reason ?? undefined,
    lastQueuedAt: toMs(a.last_queued_at),
    processedAt: toMs(a.processed_at),
  }));

  imported = 0;
  for (const batch of chunk(mappedImages, BATCH_SIZE)) {
    await callMutation("migration:importImageAssetBatch", { assets: batch });
    imported += batch.length;
    process.stdout.write(`\r  ${imported}/${mappedImages.length}`);
  }
  console.log(`\n  Done: ${imported} image assets\n`);

  console.log("✅ Migration complete!\n");
  console.log("User ID map (PostgreSQL → Convex):");
  for (const [pg, cx] of userIdMap) {
    console.log(`  ${pg} → ${cx}`);
  }
}

main().catch((err) => {
  console.error("\n❌ Migration failed:", err.message);
  process.exit(1);
});
