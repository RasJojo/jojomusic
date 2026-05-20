import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// Lecture en temps réel — tous les devices du même user voient ce state instantanément
export const get = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    return ctx.db
      .query("playbackState")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();
  },
});

export const sync = mutation({
  args: {
    userId: v.id("users"),
    trackKey: v.string(),
    trackPayload: v.any(),
    isPlaying: v.boolean(),
    positionMs: v.number(),
    deviceId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("playbackState")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();

    const data = {
      userId: args.userId,
      trackKey: args.trackKey,
      trackPayload: args.trackPayload,
      isPlaying: args.isPlaying,
      positionMs: args.positionMs,
      deviceId: args.deviceId,
      updatedAt: Date.now(),
    };

    if (existing) {
      await ctx.db.patch(existing._id, data);
      return existing._id;
    }
    return ctx.db.insert("playbackState", data);
  },
});

export const setPlaying = mutation({
  args: { userId: v.id("users"), isPlaying: v.boolean(), positionMs: v.number() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("playbackState")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();
    if (!existing) return;
    await ctx.db.patch(existing._id, {
      isPlaying: args.isPlaying,
      positionMs: args.positionMs,
      updatedAt: Date.now(),
    });
  },
});
