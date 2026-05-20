import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// Upsert par externalId (UUID NestJS) — appelé au login/register côté Flutter
export const upsertByExternalId = mutation({
  args: {
    externalId: v.string(),
    name: v.string(),
    email: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_external_id", (q) => q.eq("externalId", args.externalId))
      .unique();

    if (existing) {
      if (existing.name !== args.name || existing.email !== args.email) {
        await ctx.db.patch(existing._id, { name: args.name, email: args.email });
      }
      return existing._id;
    }

    return ctx.db.insert("users", {
      externalId: args.externalId,
      name: args.name,
      email: args.email.toLowerCase(),
      passwordHash: "",
    });
  },
});

export const getById = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return null;
    return { _id: user._id, email: user.email, name: user.name };
  },
});

export const getByExternalId = query({
  args: { externalId: v.string() },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_external_id", (q) => q.eq("externalId", args.externalId))
      .unique();
    if (!user) return null;
    return { _id: user._id, email: user.email, name: user.name };
  },
});
