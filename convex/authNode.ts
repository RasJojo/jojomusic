"use node";

import { createHmac, pbkdf2Sync, randomBytes, timingSafeEqual } from "crypto";
import { internalAction } from "./_generated/server";
import { v } from "convex/values";
import { api } from "./_generated/api";

// ── JWT (HS256) ───────────────────────────────────────────────────────────────

const JWT_SECRET = process.env.JWT_SECRET ?? "jojomusic-local-secret";
const ACCESS_TOKEN_SECONDS = 60 * 60 * 24 * 7; // 7 jours

function b64url(buf: Buffer): string {
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function signJwt(payload: Record<string, unknown>): string {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64url(
    Buffer.from(JSON.stringify({ ...payload, iat: now, exp: now + ACCESS_TOKEN_SECONDS }))
  );
  const sig = b64url(createHmac("sha256", JWT_SECRET).update(`${header}.${body}`).digest());
  return `${header}.${body}.${sig}`;
}

function verifyJwt(token: string): Record<string, unknown> | null {
  try {
    const [h, b, s] = token.split(".");
    if (!h || !b || !s) return null;
    const expected = b64url(createHmac("sha256", JWT_SECRET).update(`${h}.${b}`).digest());
    if (expected !== s) return null;
    const payload = JSON.parse(Buffer.from(b, "base64url").toString("utf-8"));
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

// ── Password (PBKDF2-SHA256, compatible format NestJS) ────────────────────────

function toPB64(buf: Buffer): string {
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_");
}

function fromPB64(val: string): Buffer {
  const n = val.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(n + "=".repeat((4 - (n.length % 4)) % 4), "base64");
}

export function hashPasswordSync(password: string): string {
  const salt = randomBytes(16);
  const digest = pbkdf2Sync(password, salt, 390_000, 32, "sha256");
  return `pbkdf2_sha256$390000$${toPB64(salt)}$${toPB64(digest)}`;
}

function verifyPassword(password: string, hash: string): boolean {
  const parts = hash.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2_sha256") return false;
  const iters = Number(parts[1]);
  if (!Number.isFinite(iters) || iters <= 0) return false;
  const salt = fromPB64(parts[2]);
  const expected = fromPB64(parts[3]);
  const candidate = pbkdf2Sync(password, salt, iters, expected.length, "sha256");
  return timingSafeEqual(candidate, expected);
}

// ── Auth result types ─────────────────────────────────────────────────────────

type AuthOk = {
  ok: true;
  access_token: string;
  user: { id: string; name: string; email: string };
  convex_user_id: string;
};
type AuthErr = { ok: false; error: string; status: number };
type AuthResult = AuthOk | AuthErr;

type MeOk = { ok: true; id: string; name: string; email: string };
type MeErr = { ok: false; error: string; status: number };
type MeResult = MeOk | MeErr;

// ── Internal actions ──────────────────────────────────────────────────────────

export const login = internalAction({
  args: { email: v.string(), password: v.string() },
  handler: async (ctx, args): Promise<AuthResult> => {
    const email = args.email.toLowerCase().trim();
    const user = await ctx.runQuery(api.auth.findByEmail, { email });
    if (!user || !verifyPassword(args.password, user.passwordHash)) {
      return { ok: false, error: "Email ou mot de passe incorrect", status: 401 };
    }
    // sub = externalId (PostgreSQL UUID) pour compat NestJS pendant migration
    const sub = (user.externalId as string | undefined) ?? user._id;
    const accessToken = signJwt({ sub, kind: "access" });
    return {
      ok: true,
      access_token: accessToken,
      user: { id: user._id, name: user.name, email: user.email },
      convex_user_id: user._id,
    };
  },
});

export const register = internalAction({
  args: { email: v.string(), password: v.string(), name: v.string() },
  handler: async (ctx, args): Promise<AuthResult> => {
    const email = args.email.toLowerCase().trim();
    const name = args.name.trim();

    const existing = await ctx.runQuery(api.auth.findByEmail, { email });
    if (existing) {
      return { ok: false, error: "Email déjà utilisé", status: 409 };
    }

    const convexId = await ctx.runMutation(api.auth.createUser, {
      email,
      name,
      passwordHash: hashPasswordSync(args.password),
    });

    const accessToken = signJwt({ sub: convexId, kind: "access" });
    return {
      ok: true,
      access_token: accessToken,
      user: { id: convexId, name, email },
      convex_user_id: convexId,
    };
  },
});

export const verifyToken = internalAction({
  args: { token: v.string() },
  handler: async (ctx, args): Promise<MeResult> => {
    const payload = verifyJwt(args.token);
    if (!payload || payload.kind !== "access" || typeof payload.sub !== "string") {
      return { ok: false, error: "Token invalide", status: 401 };
    }

    // sub peut être externalId (UUID) ou convexId
    let user = await ctx.runQuery(api.auth.getByExternalId, { externalId: payload.sub });
    if (!user) {
      user = await ctx.runQuery(api.auth.getById, { userId: payload.sub as never });
    }
    if (!user) return { ok: false, error: "Utilisateur introuvable", status: 401 };

    return { ok: true, id: user._id, name: user.name, email: user.email };
  },
});
