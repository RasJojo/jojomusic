import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const getByLookupKey = query({
  args: { lookupKey: v.string() },
  handler: async (ctx, args) => {
    return ctx.db
      .query("audioAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
  },
});

export const getByTrackKey = query({
  args: { trackKey: v.string() },
  handler: async (ctx, args) => {
    return ctx.db
      .query("audioAssets")
      .withIndex("by_track_key", (q) => q.eq("trackKey", args.trackKey))
      .first();
  },
});

export const upsert = mutation({
  args: {
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
    source: v.optional(v.string()),
    sourceWebpageUrl: v.optional(v.string()),
    sourceStreamUrl: v.optional(v.string()),
    failureReason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("audioAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }
    return ctx.db.insert("audioAssets", {
      ...args,
      source: args.source ?? "youtube",
    });
  },
});

export const updateStatus = mutation({
  args: {
    lookupKey: v.string(),
    status: v.union(
      v.literal("queued"),
      v.literal("processing"),
      v.literal("ready"),
      v.literal("failed")
    ),
    publicPath: v.optional(v.string()),
    durationMs: v.optional(v.number()),
    failureReason: v.optional(v.string()),
    processedAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const asset = await ctx.db
      .query("audioAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
    if (!asset) throw new Error("ASSET_NOT_FOUND");

    const { lookupKey: _, ...patch } = args;
    await ctx.db.patch(asset._id, patch);
  },
});

// Récupère les assets en attente de processing — appelé par le media_worker
export const listQueued = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    return ctx.db
      .query("audioAssets")
      .withIndex("by_status", (q) => q.eq("status", "queued"))
      .take(args.limit ?? 10);
  },
});
