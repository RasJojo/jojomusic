import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const list = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const playlists = await ctx.db
      .query("playlists")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .collect();

    return Promise.all(
      playlists.map(async (playlist) => {
        const tracks = await ctx.db
          .query("playlistTracks")
          .withIndex("by_playlist", (q) => q.eq("playlistId", playlist._id))
          .order("asc")
          .collect();
        return { ...playlist, tracks };
      })
    );
  },
});

export const create = mutation({
  args: {
    userId: v.id("users"),
    name: v.string(),
    description: v.optional(v.string()),
    artworkUrl: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert("playlists", {
      userId: args.userId,
      name: args.name.trim(),
      description: args.description?.trim() ?? "",
      artworkUrl: args.artworkUrl,
    });
  },
});

export const update = mutation({
  args: {
    playlistId: v.id("playlists"),
    userId: v.id("users"),
    name: v.optional(v.string()),
    description: v.optional(v.string()),
    artworkUrl: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const playlist = await ctx.db.get(args.playlistId);
    if (!playlist || playlist.userId !== args.userId) throw new Error("NOT_FOUND");

    const patch: Record<string, unknown> = {};
    if (args.name !== undefined) patch.name = args.name.trim();
    if (args.description !== undefined) patch.description = args.description.trim();
    if (args.artworkUrl !== undefined) patch.artworkUrl = args.artworkUrl;
    await ctx.db.patch(args.playlistId, patch);
  },
});

export const remove = mutation({
  args: { playlistId: v.id("playlists"), userId: v.id("users") },
  handler: async (ctx, args) => {
    const playlist = await ctx.db.get(args.playlistId);
    if (!playlist || playlist.userId !== args.userId) throw new Error("NOT_FOUND");

    const tracks = await ctx.db
      .query("playlistTracks")
      .withIndex("by_playlist", (q) => q.eq("playlistId", args.playlistId))
      .collect();
    await Promise.all(tracks.map((t) => ctx.db.delete(t._id)));
    await ctx.db.delete(args.playlistId);
  },
});

export const addTrack = mutation({
  args: {
    playlistId: v.id("playlists"),
    userId: v.id("users"),
    trackKey: v.string(),
    trackPayload: v.any(),
  },
  handler: async (ctx, args) => {
    const playlist = await ctx.db.get(args.playlistId);
    if (!playlist || playlist.userId !== args.userId) throw new Error("NOT_FOUND");

    const existing = await ctx.db
      .query("playlistTracks")
      .withIndex("by_playlist_track", (q) =>
        q.eq("playlistId", args.playlistId).eq("trackKey", args.trackKey)
      )
      .unique();
    if (existing) return existing._id;

    const tracks = await ctx.db
      .query("playlistTracks")
      .withIndex("by_playlist", (q) => q.eq("playlistId", args.playlistId))
      .collect();
    const maxPosition = tracks.reduce((max, t) => Math.max(max, t.position), -1);

    return ctx.db.insert("playlistTracks", {
      playlistId: args.playlistId,
      trackKey: args.trackKey,
      position: maxPosition + 1,
      trackPayload: args.trackPayload,
    });
  },
});

export const removeTrack = mutation({
  args: {
    playlistId: v.id("playlists"),
    userId: v.id("users"),
    trackKey: v.string(),
  },
  handler: async (ctx, args) => {
    const playlist = await ctx.db.get(args.playlistId);
    if (!playlist || playlist.userId !== args.userId) throw new Error("NOT_FOUND");

    const track = await ctx.db
      .query("playlistTracks")
      .withIndex("by_playlist_track", (q) =>
        q.eq("playlistId", args.playlistId).eq("trackKey", args.trackKey)
      )
      .unique();
    if (track) await ctx.db.delete(track._id);
  },
});

export const reorderTracks = mutation({
  args: {
    playlistId: v.id("playlists"),
    userId: v.id("users"),
    orderedTrackKeys: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const playlist = await ctx.db.get(args.playlistId);
    if (!playlist || playlist.userId !== args.userId) throw new Error("NOT_FOUND");

    const tracks = await ctx.db
      .query("playlistTracks")
      .withIndex("by_playlist", (q) => q.eq("playlistId", args.playlistId))
      .collect();

    const trackMap = new Map(tracks.map((t) => [t.trackKey, t]));
    await Promise.all(
      args.orderedTrackKeys.map((key, index) => {
        const track = trackMap.get(key);
        if (track) return ctx.db.patch(track._id, { position: index });
      })
    );
  },
});
