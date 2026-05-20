import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const get = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    return ctx.db
      .query("spotifyLinks")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();
  },
});

export const upsert = mutation({
  args: {
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
    likedTracksImported: v.optional(v.number()),
    savedShowsImported: v.optional(v.number()),
    savedEpisodesImported: v.optional(v.number()),
    recentTracksImported: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("spotifyLinks")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();

    const data = {
      ...args,
      likedTracksImported: args.likedTracksImported ?? 0,
      savedShowsImported: args.savedShowsImported ?? 0,
      savedEpisodesImported: args.savedEpisodesImported ?? 0,
      recentTracksImported: args.recentTracksImported ?? 0,
    };

    if (existing) {
      await ctx.db.patch(existing._id, data);
      return existing._id;
    }
    return ctx.db.insert("spotifyLinks", data);
  },
});

export const remove = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("spotifyLinks")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();
    if (existing) await ctx.db.delete(existing._id);
  },
});
