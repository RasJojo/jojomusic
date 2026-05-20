import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    return ctx.db
      .query("savedTracks")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .collect();
  },
});

export const save = mutation({
  args: {
    userId: v.id("users"),
    trackKey: v.string(),
    trackPayload: v.any(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedTracks")
      .withIndex("by_user_track", (q) =>
        q.eq("userId", args.userId).eq("trackKey", args.trackKey)
      )
      .unique();
    if (existing) return existing._id;

    return ctx.db.insert("savedTracks", {
      userId: args.userId,
      trackKey: args.trackKey,
      trackPayload: args.trackPayload,
    });
  },
});

export const unsave = mutation({
  args: { userId: v.id("users"), trackKey: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedTracks")
      .withIndex("by_user_track", (q) =>
        q.eq("userId", args.userId).eq("trackKey", args.trackKey)
      )
      .unique();
    if (existing) await ctx.db.delete(existing._id);
  },
});

export const isSaved = query({
  args: { userId: v.id("users"), trackKey: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedTracks")
      .withIndex("by_user_track", (q) =>
        q.eq("userId", args.userId).eq("trackKey", args.trackKey)
      )
      .unique();
    return existing !== null;
  },
});
