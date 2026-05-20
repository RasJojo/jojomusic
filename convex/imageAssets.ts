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
