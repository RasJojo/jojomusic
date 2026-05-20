import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  users: defineTable({
    email: v.string(),
    name: v.string(),
    passwordHash: v.string(),
    externalId: v.optional(v.string()), // NestJS UUID
  })
    .index("by_email", ["email"])
    .index("by_external_id", ["externalId"]),

  playlists: defineTable({
    userId: v.id("users"),
    name: v.string(),
    description: v.string(),
    artworkUrl: v.optional(v.string()),
  }).index("by_user", ["userId"]),

  playlistTracks: defineTable({
    playlistId: v.id("playlists"),
    trackKey: v.string(),
    position: v.number(),
    trackPayload: v.any(),
  })
    .index("by_playlist", ["playlistId"])
    .index("by_playlist_track", ["playlistId", "trackKey"]),

  savedTracks: defineTable({
    userId: v.id("users"),
    trackKey: v.string(),
    trackPayload: v.any(),
  })
    .index("by_user", ["userId"])
    .index("by_user_track", ["userId", "trackKey"]),

  playbackEvents: defineTable({
    userId: v.id("users"),
    trackKey: v.string(),
    eventType: v.string(),
    listenedMs: v.number(),
    completionRatio: v.number(),
    trackPayload: v.any(),
  })
    .index("by_user", ["userId"])
    .index("by_track", ["trackKey"]),

  // Nouvel état de lecture temps réel — cross-device sync
  playbackState: defineTable({
    userId: v.id("users"),
    trackKey: v.string(),
    trackPayload: v.any(),
    isPlaying: v.boolean(),
    positionMs: v.number(),
    deviceId: v.optional(v.string()),
    updatedAt: v.number(),
  }).index("by_user", ["userId"]),

  audioAssets: defineTable({
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
    .index("by_lookup_key", ["lookupKey"])
    .index("by_asset_key", ["assetKey"])
    .index("by_track_key", ["trackKey"])
    .index("by_status", ["status"]),

  imageAssets: defineTable({
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
    .index("by_lookup_key", ["lookupKey"])
    .index("by_entity", ["entityType", "entityKey"])
    .index("by_status", ["status"]),

  spotifyLinks: defineTable({
    userId: v.id("users"),
    spotifyUserId: v.string(),
    displayName: v.optional(v.string()),
    email: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    country: v.optional(v.string()),
    product: v.optional(v.string()),
    accessToken: v.optional(v.string()),
    refreshToken: v.optional(v.string()),
    tokenExpiresAt: v.optional(v.number()),
    importedAt: v.optional(v.number()),
    likedTracksImported: v.number(),
    savedShowsImported: v.number(),
    savedEpisodesImported: v.number(),
    recentTracksImported: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_spotify_user", ["spotifyUserId"]),

  savedPodcastShows: defineTable({
    userId: v.id("users"),
    podcastKey: v.string(),
    podcastPayload: v.any(),
  })
    .index("by_user", ["userId"])
    .index("by_user_podcast", ["userId", "podcastKey"]),

  savedPodcastEpisodes: defineTable({
    userId: v.id("users"),
    episodeKey: v.string(),
    episodePayload: v.any(),
  })
    .index("by_user", ["userId"])
    .index("by_user_episode", ["userId", "episodeKey"]),
});
