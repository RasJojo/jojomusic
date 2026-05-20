import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const record = mutation({
  args: {
    userId: v.id("users"),
    trackKey: v.string(),
    eventType: v.string(),
    listenedMs: v.number(),
    completionRatio: v.number(),
    trackPayload: v.any(),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert("playbackEvents", args);
  },
});

export const history = query({
  args: { userId: v.id("users"), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    return ctx.db
      .query("playbackEvents")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(args.limit ?? 50);
  },
});
