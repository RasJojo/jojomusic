import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const getByLookupKey = query({
  args: { lookupKey: v.string() },
  handler: async (ctx, args) => {
    return ctx.db
      .query("imageAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
  },
});

export const upsert = mutation({
  args: {
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
    publicPath: v.optional(v.string()),
    contentType: v.optional(v.string()),
    failureReason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("imageAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, args);
      return existing._id;
    }
    return ctx.db.insert("imageAssets", args);
  },
});

export const listQueued = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    return ctx.db
      .query("imageAssets")
      .withIndex("by_status", (q) => q.eq("status", "queued"))
      .take(args.limit ?? 10);
  },
});

// Claim atomique d'un job image queued
export const claimQueued = mutation({
  args: {},
  handler: async (ctx) => {
    const job = await ctx.db
      .query("imageAssets")
      .withIndex("by_status", (q) => q.eq("status", "queued"))
      .first();
    if (!job) return null;
    await ctx.db.patch(job._id, {
      status: "processing",
      lastQueuedAt: Date.now(),
    });
    return job;
  },
});

// Enqueue un nouveau job image (idempotent)
export const enqueue = mutation({
  args: {
    lookupKey: v.string(),
    assetKey: v.string(),
    entityType: v.string(),
    entityKey: v.string(),
    sourceUrl: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("imageAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
    if (existing) {
      if (existing.status !== "ready" || existing.sourceUrl !== args.sourceUrl) {
        await ctx.db.patch(existing._id, {
          ...args,
          status: "queued",
          failureReason: undefined,
          processedAt: undefined,
          lastQueuedAt: Date.now(),
        });
      }
      return existing._id;
    }
    return ctx.db.insert("imageAssets", {
      ...args,
      status: "queued",
      lastQueuedAt: Date.now(),
    });
  },
});

// Marque un asset image comme ready
export const markReady = mutation({
  args: {
    lookupKey: v.string(),
    filePath: v.string(),
    contentType: v.string(),
  },
  handler: async (ctx, args) => {
    const asset = await ctx.db
      .query("imageAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
    if (!asset) throw new Error("ASSET_NOT_FOUND");
    await ctx.db.patch(asset._id, {
      status: "ready",
      filePath: args.filePath,
      contentType: args.contentType,
      failureReason: undefined,
      processedAt: Date.now(),
    });
  },
});

// Marque un asset image comme failed
export const markFailed = mutation({
  args: {
    lookupKey: v.string(),
    reason: v.string(),
  },
  handler: async (ctx, args) => {
    const asset = await ctx.db
      .query("imageAssets")
      .withIndex("by_lookup_key", (q) => q.eq("lookupKey", args.lookupKey))
      .unique();
    if (!asset) throw new Error("ASSET_NOT_FOUND");
    await ctx.db.patch(asset._id, {
      status: "failed",
      failureReason: args.reason.slice(0, 4000),
      processedAt: Date.now(),
    });
  },
});
