import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const listShows = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    return ctx.db
      .query("savedPodcastShows")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .collect();
  },
});

export const saveShow = mutation({
  args: { userId: v.id("users"), podcastKey: v.string(), podcastPayload: v.any() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedPodcastShows")
      .withIndex("by_user_podcast", (q) =>
        q.eq("userId", args.userId).eq("podcastKey", args.podcastKey)
      )
      .unique();
    if (existing) return existing._id;
    return ctx.db.insert("savedPodcastShows", args);
  },
});

export const unsaveShow = mutation({
  args: { userId: v.id("users"), podcastKey: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedPodcastShows")
      .withIndex("by_user_podcast", (q) =>
        q.eq("userId", args.userId).eq("podcastKey", args.podcastKey)
      )
      .unique();
    if (existing) await ctx.db.delete(existing._id);
  },
});

export const listEpisodes = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    return ctx.db
      .query("savedPodcastEpisodes")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .collect();
  },
});

export const saveEpisode = mutation({
  args: { userId: v.id("users"), episodeKey: v.string(), episodePayload: v.any() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedPodcastEpisodes")
      .withIndex("by_user_episode", (q) =>
        q.eq("userId", args.userId).eq("episodeKey", args.episodeKey)
      )
      .unique();
    if (existing) return existing._id;
    return ctx.db.insert("savedPodcastEpisodes", args);
  },
});

export const unsaveEpisode = mutation({
  args: { userId: v.id("users"), episodeKey: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("savedPodcastEpisodes")
      .withIndex("by_user_episode", (q) =>
        q.eq("userId", args.userId).eq("episodeKey", args.episodeKey)
      )
      .unique();
    if (existing) await ctx.db.delete(existing._id);
  },
});
