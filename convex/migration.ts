import { mutation } from "./_generated/server";
import { v } from "convex/values";

// ── Users ─────────────────────────────────────────────────────────────────────

export const importUser = mutation({
  args: {
    externalId: v.string(),
    email: v.string(),
    name: v.string(),
    passwordHash: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_external_id", (q) => q.eq("externalId", args.externalId))
      .unique();
    if (existing) return existing._id;
    return ctx.db.insert("users", {
      externalId: args.externalId,
      email: args.email.toLowerCase(),
      name: args.name,
      passwordHash: args.passwordHash,
    });
  },
});

// ── Playlists ─────────────────────────────────────────────────────────────────

export const importPlaylist = mutation({
  args: {
    convexUserId: v.id("users"),
    name: v.string(),
    description: v.string(),
    artworkUrl: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert("playlists", {
      userId: args.convexUserId,
      name: args.name,
      description: args.description,
      artworkUrl: args.artworkUrl,
    });
  },
});

export const importPlaylistTrackBatch = mutation({
  args: {
    tracks: v.array(
      v.object({
        convexPlaylistId: v.id("playlists"),
        trackKey: v.string(),
        position: v.number(),
        trackPayload: v.any(),
      })
    ),
  },
  handler: async (ctx, { tracks }) => {
    for (const t of tracks) {
      const existing = await ctx.db
        .query("playlistTracks")
        .withIndex("by_playlist_track", (q) =>
          q.eq("playlistId", t.convexPlaylistId).eq("trackKey", t.trackKey)
        )
        .unique();
      if (!existing) {
        await ctx.db.insert("playlistTracks", {
          playlistId: t.convexPlaylistId,
          trackKey: t.trackKey,
          position: t.position,
          trackPayload: t.trackPayload,
        });
      }
    }
  },
});

// ── Saved Tracks ──────────────────────────────────────────────────────────────

export const importSavedTrackBatch = mutation({
  args: {
    tracks: v.array(
      v.object({
        convexUserId: v.id("users"),
        trackKey: v.string(),
        trackPayload: v.any(),
      })
    ),
  },
  handler: async (ctx, { tracks }) => {
    for (const t of tracks) {
      const existing = await ctx.db
        .query("savedTracks")
        .withIndex("by_user_track", (q) =>
          q.eq("userId", t.convexUserId).eq("trackKey", t.trackKey)
        )
        .unique();
      if (!existing) {
        await ctx.db.insert("savedTracks", {
          userId: t.convexUserId,
          trackKey: t.trackKey,
          trackPayload: t.trackPayload,
        });
      }
    }
  },
});

// ── Playback Events ───────────────────────────────────────────────────────────

export const importPlaybackEventBatch = mutation({
  args: {
    events: v.array(
      v.object({
        convexUserId: v.id("users"),
        trackKey: v.string(),
        eventType: v.string(),
        listenedMs: v.number(),
        completionRatio: v.number(),
        trackPayload: v.any(),
      })
    ),
  },
  handler: async (ctx, { events }) => {
    for (const e of events) {
      await ctx.db.insert("playbackEvents", {
        userId: e.convexUserId,
        trackKey: e.trackKey,
        eventType: e.eventType,
        listenedMs: e.listenedMs,
        completionRatio: e.completionRatio,
        trackPayload: e.trackPayload,
      });
    }
  },
});

// ── Saved Albums ──────────────────────────────────────────────────────────────

export const importSavedAlbumBatch = mutation({
  args: {
    albums: v.array(
      v.object({
        convexUserId: v.id("users"),
        albumKey: v.string(),
        albumPayload: v.any(),
      })
    ),
  },
  handler: async (ctx, { albums }) => {
    for (const a of albums) {
      const existing = await ctx.db
        .query("savedAlbums")
        .withIndex("by_user_album", (q) =>
          q.eq("userId", a.convexUserId).eq("albumKey", a.albumKey)
        )
        .unique();
      if (!existing) {
        await ctx.db.insert("savedAlbums", {
          userId: a.convexUserId,
          albumKey: a.albumKey,
          albumPayload: a.albumPayload,
        });
      }
    }
  },
});

// ── Saved Podcast Shows ───────────────────────────────────────────────────────

export const importSavedPodcastShowBatch = mutation({
  args: {
    shows: v.array(
      v.object({
        convexUserId: v.id("users"),
        podcastKey: v.string(),
        podcastPayload: v.any(),
      })
    ),
  },
  handler: async (ctx, { shows }) => {
    for (const s of shows) {
      const existing = await ctx.db
        .query("savedPodcastShows")
        .withIndex("by_user_podcast", (q) =>
          q.eq("userId", s.convexUserId).eq("podcastKey", s.podcastKey)
        )
        .unique();
      if (!existing) {
        await ctx.db.insert("savedPodcastShows", {
          userId: s.convexUserId,
          podcastKey: s.podcastKey,
          podcastPayload: s.podcastPayload,
        });
      }
    }
  },
});

// ── Audio Assets ──────────────────────────────────────────────────────────────

export const importAudioAssetBatch = mutation({
  args: {
    assets: v.array(
      v.object({
        lookupKey: v.string(),
        trackKey: v.string(),
        query: v.string(),
        title: v.string(),
        artist: v.string(),
        assetKey: v.string(),
        status: v.union(
          v.literal("queued"),
          v.literal("processing"),
          v.literal("ready"),
          v.literal("failed")
        ),
        filePath: v.optional(v.string()),
        publicPath: v.optional(v.string()),
        thumbnailUrl: v.optional(v.string()),
        durationMs: v.optional(v.number()),
        source: v.string(),
        sourceWebpageUrl: v.optional(v.string()),
        sourceStreamUrl: v.optional(v.string()),
        failureReason: v.optional(v.string()),
        lastQueuedAt: v.optional(v.number()),
        processedAt: v.optional(v.number()),
        expiresAt: v.optional(v.number()),
      })
    ),
  },
  handler: async (ctx, { assets }) => {
    for (const a of assets) {
      const existing = await ctx.db
        .query("audioAssets")
        .withIndex("by_lookup_key", (q) => q.eq("lookupKey", a.lookupKey))
        .unique();
      if (!existing) {
        await ctx.db.insert("audioAssets", a);
      }
    }
  },
});

// ── Image Assets ──────────────────────────────────────────────────────────────

export const importImageAssetBatch = mutation({
  args: {
    assets: v.array(
      v.object({
        lookupKey: v.string(),
        entityType: v.string(),
        entityKey: v.string(),
        sourceUrl: v.string(),
        assetKey: v.string(),
        status: v.union(
          v.literal("queued"),
          v.literal("processing"),
          v.literal("ready"),
          v.literal("failed")
        ),
        filePath: v.optional(v.string()),
        publicPath: v.optional(v.string()),
        contentType: v.optional(v.string()),
        failureReason: v.optional(v.string()),
        lastQueuedAt: v.optional(v.number()),
        processedAt: v.optional(v.number()),
      })
    ),
  },
  handler: async (ctx, { assets }) => {
    for (const a of assets) {
      const existing = await ctx.db
        .query("imageAssets")
        .withIndex("by_lookup_key", (q) => q.eq("lookupKey", a.lookupKey))
        .unique();
      if (!existing) {
        await ctx.db.insert("imageAssets", a);
      }
    }
  },
});
