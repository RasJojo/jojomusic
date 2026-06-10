import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const get = query({
  args: { key: v.string() },
  handler: async (ctx, { key }) =>
    ctx.db.query("apiCache").withIndex("by_key", q => q.eq("key", key)).first(),
});

export const set = mutation({
  args: { key: v.string(), value: v.any(), cachedAt: v.number() },
  handler: async (ctx, { key, value, cachedAt }) => {
    const existing = await ctx.db.query("apiCache").withIndex("by_key", q => q.eq("key", key)).first();
    if (existing) await ctx.db.patch(existing._id, { value, cachedAt });
    else await ctx.db.insert("apiCache", { key, value, cachedAt });
  },
});
