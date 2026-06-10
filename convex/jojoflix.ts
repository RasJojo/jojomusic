import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// ─── Profiles ────────────────────────────────────────────────────────────────

export const getProfilesByUser = query({
  args: { userId: v.string() },
  handler: async (ctx, { userId }) => {
    return ctx.db
      .query("jfProfiles")
      .withIndex("by_user_id", (q) => q.eq("userId", userId))
      .collect();
  },
});

export const getProfile = query({
  args: { profileId: v.id("jfProfiles") },
  handler: async (ctx, { profileId }) => {
    return ctx.db.get(profileId);
  },
});

export const getProfileOfUser = query({
  args: { profileId: v.id("jfProfiles"), userId: v.string() },
  handler: async (ctx, { profileId, userId }) => {
    const profile = await ctx.db.get(profileId);
    if (!profile || profile.userId !== userId) return null;
    return profile;
  },
});

export const countProfilesByUser = query({
  args: { userId: v.string() },
  handler: async (ctx, { userId }) => {
    const profiles = await ctx.db
      .query("jfProfiles")
      .withIndex("by_user_id", (q) => q.eq("userId", userId))
      .collect();
    return profiles.length;
  },
});

export const createProfile = mutation({
  args: {
    userId: v.string(),
    name: v.string(),
    avatarUrl: v.optional(v.string()),
    isKids: v.boolean(),
    preferences: v.any(),
    createdAtMs: v.optional(v.number()),
    updatedAtMs: v.optional(v.number()),
  },
  handler: async (ctx, { userId, name, avatarUrl, isKids, preferences, createdAtMs, updatedAtMs }) => {
    const now = Date.now();
    const id = await ctx.db.insert("jfProfiles", {
      userId,
      name,
      avatarUrl,
      isKids,
      preferences,
      createdAtMs: createdAtMs ?? now,
      updatedAtMs: updatedAtMs ?? now,
    });
    return ctx.db.get(id);
  },
});

export const updateProfile = mutation({
  args: {
    profileId: v.id("jfProfiles"),
    name: v.optional(v.string()),
    avatarUrl: v.optional(v.union(v.string(), v.null())),
    isKids: v.optional(v.boolean()),
    preferences: v.optional(v.any()),
  },
  handler: async (ctx, { profileId, name, avatarUrl, isKids, preferences }) => {
    const patch: Record<string, unknown> = { updatedAtMs: Date.now() };
    if (name !== undefined) patch.name = name;
    if (avatarUrl !== undefined) patch.avatarUrl = avatarUrl ?? undefined;
    if (isKids !== undefined) patch.isKids = isKids;
    if (preferences !== undefined) patch.preferences = preferences;
    await ctx.db.patch(profileId, patch);
    return ctx.db.get(profileId);
  },
});

export const deleteProfile = mutation({
  args: { profileId: v.id("jfProfiles") },
  handler: async (ctx, { profileId }) => {
    await ctx.db.delete(profileId);
  },
});

// ─── Watch History ────────────────────────────────────────────────────────────

export const getWatchHistory = query({
  args: {
    profileId: v.id("jfProfiles"),
    tmdbId: v.string(),
    mediaType: v.union(v.literal("movie"), v.literal("tv")),
    seasonNum: v.union(v.number(), v.null()),
    episodeNum: v.union(v.number(), v.null()),
  },
  handler: async (ctx, { profileId, tmdbId, mediaType, seasonNum, episodeNum }) => {
    const rows = await ctx.db
      .query("jfWatchHistories")
      .withIndex("by_profile_tmdb", (q) => q.eq("profileId", profileId).eq("tmdbId", tmdbId))
      .filter((q) =>
        q.and(
          q.eq(q.field("mediaType"), mediaType),
          q.eq(q.field("isFinished"), false),
          seasonNum !== null
            ? q.eq(q.field("seasonNum"), seasonNum)
            : q.eq(q.field("seasonNum"), undefined),
          episodeNum !== null
            ? q.eq(q.field("episodeNum"), episodeNum)
            : q.eq(q.field("episodeNum"), undefined)
        )
      )
      .order("desc")
      .first();
    return rows ?? null;
  },
});

export const getActiveWatchHistory = query({
  args: { profileId: v.id("jfProfiles") },
  handler: async (ctx, { profileId }) => {
    const rows = await ctx.db
      .query("jfWatchHistories")
      .withIndex("by_profile", (q) => q.eq("profileId", profileId))
      .filter((q) =>
        q.and(q.eq(q.field("isFinished"), false), q.gt(q.field("currentTime"), 0))
      )
      .order("desc")
      .take(100);
    return rows;
  },
});

export const getWatchHistoriesByTmdb = query({
  args: {
    profileId: v.id("jfProfiles"),
    tmdbId: v.string(),
    mediaType: v.union(v.literal("movie"), v.literal("tv")),
  },
  handler: async (ctx, { profileId, tmdbId, mediaType }) => {
    return ctx.db
      .query("jfWatchHistories")
      .withIndex("by_profile_tmdb", (q) => q.eq("profileId", profileId).eq("tmdbId", tmdbId))
      .filter((q) => q.eq(q.field("mediaType"), mediaType))
      .collect();
  },
});

export const getLastWatched = query({
  args: { profileId: v.id("jfProfiles") },
  handler: async (ctx, { profileId }) => {
    return ctx.db
      .query("jfWatchHistories")
      .withIndex("by_profile", (q) => q.eq("profileId", profileId))
      .order("desc")
      .first();
  },
});

export const upsertWatchHistory = mutation({
  args: {
    profileId: v.id("jfProfiles"),
    tmdbId: v.string(),
    mediaType: v.union(v.literal("movie"), v.literal("tv")),
    seasonNum: v.optional(v.union(v.number(), v.null())),
    episodeNum: v.optional(v.union(v.number(), v.null())),
    currentTime: v.number(),
    totalDuration: v.number(),
    isFinished: v.boolean(),
    createdAtMs: v.optional(v.number()),
    updatedAtMs: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { profileId, tmdbId, mediaType, seasonNum, episodeNum, currentTime, totalDuration, isFinished, createdAtMs, updatedAtMs } = args;
    const now = Date.now();

    const existing = await ctx.db
      .query("jfWatchHistories")
      .withIndex("by_profile_tmdb", (q) => q.eq("profileId", profileId).eq("tmdbId", tmdbId))
      .filter((q) => {
        const base = q.eq(q.field("mediaType"), mediaType);
        const sMatch = seasonNum != null
          ? q.eq(q.field("seasonNum"), seasonNum)
          : q.eq(q.field("seasonNum"), undefined);
        const eMatch = episodeNum != null
          ? q.eq(q.field("episodeNum"), episodeNum)
          : q.eq(q.field("episodeNum"), undefined);
        return q.and(base, sMatch, eMatch);
      })
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, { currentTime, totalDuration, isFinished, updatedAtMs: updatedAtMs ?? now });
      return ctx.db.get(existing._id);
    }

    const id = await ctx.db.insert("jfWatchHistories", {
      profileId,
      tmdbId,
      mediaType,
      seasonNum: seasonNum ?? undefined,
      episodeNum: episodeNum ?? undefined,
      currentTime,
      totalDuration,
      isFinished,
      createdAtMs: createdAtMs ?? now,
      updatedAtMs: updatedAtMs ?? now,
    });
    return ctx.db.get(id);
  },
});

// ─── Profile Interests ────────────────────────────────────────────────────────

export const getInterestsByProfile = query({
  args: { profileId: v.id("jfProfiles") },
  handler: async (ctx, { profileId }) => {
    return ctx.db
      .query("jfProfileInterests")
      .withIndex("by_profile", (q) => q.eq("profileId", profileId))
      .collect();
  },
});

export const getInterest = query({
  args: { profileId: v.id("jfProfiles"), genreId: v.number() },
  handler: async (ctx, { profileId, genreId }) => {
    return ctx.db
      .query("jfProfileInterests")
      .withIndex("by_profile_genre", (q) => q.eq("profileId", profileId).eq("genreId", genreId))
      .first();
  },
});

export const getTopInterests = query({
  args: { profileId: v.id("jfProfiles"), limit: v.number() },
  handler: async (ctx, { profileId, limit }) => {
    const all = await ctx.db
      .query("jfProfileInterests")
      .withIndex("by_profile", (q) => q.eq("profileId", profileId))
      .filter((q) => q.gt(q.field("affinityScore"), 0))
      .collect();
    return all.sort((a, b) => b.affinityScore - a.affinityScore).slice(0, limit);
  },
});

export const upsertInterest = mutation({
  args: {
    profileId: v.id("jfProfiles"),
    genreId: v.number(),
    affinityScore: v.number(),
    lastWatchedAtMs: v.optional(v.number()),
    createdAtMs: v.optional(v.number()),
    updatedAtMs: v.optional(v.number()),
  },
  handler: async (ctx, { profileId, genreId, affinityScore, lastWatchedAtMs, createdAtMs, updatedAtMs }) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("jfProfileInterests")
      .withIndex("by_profile_genre", (q) => q.eq("profileId", profileId).eq("genreId", genreId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, { affinityScore, lastWatchedAtMs, updatedAtMs: updatedAtMs ?? now });
    } else {
      await ctx.db.insert("jfProfileInterests", {
        profileId,
        genreId,
        affinityScore,
        lastWatchedAtMs,
        createdAtMs: createdAtMs ?? now,
        updatedAtMs: updatedAtMs ?? now,
      });
    }
  },
});

export const decrementStaleInterests = mutation({
  args: {
    profileId: v.id("jfProfiles"),
    excludeGenreIds: v.array(v.number()),
    decayCutoffMs: v.number(),
    amount: v.number(),
  },
  handler: async (ctx, { profileId, excludeGenreIds, decayCutoffMs, amount }) => {
    const interests = await ctx.db
      .query("jfProfileInterests")
      .withIndex("by_profile", (q) => q.eq("profileId", profileId))
      .collect();

    for (const interest of interests) {
      if (excludeGenreIds.includes(interest.genreId)) continue;
      const lastWatched = interest.lastWatchedAtMs;
      if (lastWatched !== undefined && lastWatched >= decayCutoffMs) continue;
      const newScore = Math.max(0, interest.affinityScore - amount);
      await ctx.db.patch(interest._id, { affinityScore: newScore, updatedAtMs: Date.now() });
    }
  },
});

// ─── Media Markers ────────────────────────────────────────────────────────────

export const getMarkersByTmdb = query({
  args: { tmdbId: v.string() },
  handler: async (ctx, { tmdbId }) => {
    return ctx.db
      .query("jfMediaMarkers")
      .withIndex("by_tmdb_id", (q) => q.eq("tmdbId", tmdbId))
      .collect();
  },
});

export const createMediaMarker = mutation({
  args: {
    tmdbId: v.string(),
    markerType: v.union(v.literal("intro"), v.literal("outro")),
    startTime: v.number(),
    endTime: v.number(),
    createdAtMs: v.optional(v.number()),
  },
  handler: async (ctx, { tmdbId, markerType, startTime, endTime, createdAtMs }) => {
    const id = await ctx.db.insert("jfMediaMarkers", {
      tmdbId,
      markerType,
      startTime,
      endTime,
      createdAtMs: createdAtMs ?? Date.now(),
    });
    return ctx.db.get(id);
  },
});

// ─── API Cache ────────────────────────────────────────────────────────────────

export const getCacheEntry = query({
  args: { key: v.string() },
  handler: async (ctx, { key }) => {
    const entry = await ctx.db
      .query("jfApiCache")
      .withIndex("by_key", (q) => q.eq("key", key))
      .first();
    if (!entry) return null;
    if (entry.expiresAtMs < Date.now()) return null;
    return entry.value;
  },
});

export const setCacheEntry = mutation({
  args: { key: v.string(), value: v.any(), expiresAtMs: v.number() },
  handler: async (ctx, { key, value, expiresAtMs }) => {
    const existing = await ctx.db
      .query("jfApiCache")
      .withIndex("by_key", (q) => q.eq("key", key))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, { value, expiresAtMs });
    } else {
      await ctx.db.insert("jfApiCache", { key, value, expiresAtMs });
    }
  },
});

export const deleteCacheEntry = mutation({
  args: { key: v.string() },
  handler: async (ctx, { key }) => {
    const existing = await ctx.db
      .query("jfApiCache")
      .withIndex("by_key", (q) => q.eq("key", key))
      .first();
    if (existing) {
      await ctx.db.delete(existing._id);
    }
  },
});
