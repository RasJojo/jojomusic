"use node";

import { createHmac } from "crypto";
import { internalAction } from "./_generated/server";
import { v } from "convex/values";
import { api } from "./_generated/api";
import type { ActionCtx } from "./_generated/server";
import type { TrackPayload, PodcastPayload } from "./musicContent";

// ── JWT helpers (duplicated from authNode for isolation) ──────────────────────

const JWT_SECRET = () => process.env.JWT_SECRET ?? "jojomusic-local-secret";

function b64url(buf: Buffer): string {
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function signJwt(payload: Record<string, unknown>, expiresInSeconds = 60 * 60 * 24 * 7): string {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64url(Buffer.from(JSON.stringify({ ...payload, iat: now, exp: now + expiresInSeconds })));
  const sig = b64url(createHmac("sha256", JWT_SECRET()).update(`${header}.${body}`).digest());
  return `${header}.${body}.${sig}`;
}

function verifyJwt(token: string): Record<string, unknown> | null {
  try {
    const [h, b, s] = token.split(".");
    if (!h || !b || !s) return null;
    const expected = b64url(createHmac("sha256", JWT_SECRET()).update(`${h}.${b}`).digest());
    if (expected !== s) return null;
    const payload = JSON.parse(Buffer.from(b, "base64url").toString("utf-8"));
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch { return null; }
}

// ── Spotify env ───────────────────────────────────────────────────────────────

const sp = {
  clientId: () => process.env.SPOTIFY_CLIENT_ID ?? "",
  clientSecret: () => process.env.SPOTIFY_CLIENT_SECRET ?? "",
  redirectUri: () => process.env.SPOTIFY_REDIRECT_URI ?? "https://convex-site.jojoserv.com/integrations/spotify/callback",
  scopes: "user-library-read user-read-recently-played user-read-private user-read-email",
};

// ── Spotify API helpers ───────────────────────────────────────────────────────

async function spotifyTokenRequest(body: URLSearchParams): Promise<{ accessToken: string; refreshToken: string | null; expiresAt: number | null }> {
  const creds = Buffer.from(`${sp.clientId()}:${sp.clientSecret()}`).toString("base64");
  const r = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Authorization: `Basic ${creds}` },
    body: body.toString(),
    signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) { const t = await r.text().catch(() => ""); throw new Error(`Spotify token error: ${r.status} ${t}`); }
  const data = await r.json() as Record<string, unknown>;
  const expiresIn = data.expires_in ? Number(data.expires_in) : 3600;
  return {
    accessToken: String(data.access_token ?? ""),
    refreshToken: data.refresh_token ? String(data.refresh_token) : null,
    expiresAt: Date.now() + expiresIn * 1000,
  };
}

async function exchangeSpotifyCode(code: string): Promise<{ accessToken: string; refreshToken: string | null; expiresAt: number | null }> {
  const body = new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: sp.redirectUri() });
  return spotifyTokenRequest(body);
}

async function refreshSpotifyAccessToken(refreshToken: string): Promise<{ accessToken: string; refreshToken: string | null; expiresAt: number | null }> {
  const body = new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken });
  return spotifyTokenRequest(body);
}

async function ensureSpotifyAccessToken(link: { accessToken?: string | null; refreshToken?: string | null; tokenExpiresAt?: number | null }): Promise<{ accessToken: string; refreshToken: string | null; expiresAt: number | null }> {
  if (link.accessToken && link.tokenExpiresAt && link.tokenExpiresAt > Date.now() + 60_000) {
    return { accessToken: link.accessToken, refreshToken: link.refreshToken ?? null, expiresAt: link.tokenExpiresAt };
  }
  if (!link.refreshToken) throw new Error("NO_REFRESH_TOKEN");
  return refreshSpotifyAccessToken(link.refreshToken);
}

async function fetchSpotifyApi(path: string, accessToken: string, params?: Record<string, string>): Promise<Record<string, unknown>> {
  const url = new URL(`https://api.spotify.com/v1${path}`);
  if (params) for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const r = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` }, signal: AbortSignal.timeout(10000) });
  if (!r.ok) { const t = await r.text().catch(() => ""); throw new Error(`Spotify API ${r.status}: ${t}`); }
  return r.json() as Promise<Record<string, unknown>>;
}

async function spotifyPaginate(path: string, accessToken: string): Promise<Record<string, unknown>[]> {
  const items: Record<string, unknown>[] = [];
  let next: string | null = path;
  while (next && items.length < 500) {
    const data = await fetchSpotifyApi(next.startsWith("http") ? new URL(next).pathname + new URL(next).search : next, accessToken).catch(() => null);
    if (!data) break;
    const page = data.items ?? data.tracks?.items ?? data.shows?.items ?? data.episodes?.items ?? [];
    for (const item of Array.isArray(page) ? page : []) items.push(item as Record<string, unknown>);
    next = (data.next as string | null) ?? null;
  }
  return items;
}

function mapSpotifyTrack(track: Record<string, unknown> | undefined): TrackPayload | null {
  if (!track?.name || !track.artists) return null;
  const artist = ((track.artists as Record<string, unknown>[])[0])?.name;
  if (!artist) return null;
  const images = (((track.album as Record<string, unknown>)?.images) as { url: string; width: number }[] | undefined) ?? [];
  const artwork = images.sort((a, b) => (b.width ?? 0) - (a.width ?? 0))[0]?.url ?? null;
  const name = String(track.name ?? "").trim();
  const artistStr = String(artist ?? "").trim();
  const key = String(name + artistStr).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return { track_key: key, title: name, artist: artistStr, album: String((track.album as Record<string, unknown>)?.name ?? "") || null, artwork_url: artwork, provider: "spotify", external_id: String(track.id ?? ""), preview_url: track.preview_url ? String(track.preview_url) : null, lyrics_synced_available: false };
}

function mapSpotifyShow(show: Record<string, unknown> | undefined): PodcastPayload | null {
  if (!show?.name || !show.publisher) return null;
  const name = String(show.name).trim();
  const publisher = String(show.publisher).trim();
  const images = (show.images as { url: string }[] | undefined) ?? [];
  const key = `${publisher}-${name}`.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return { podcast_key: key, title: name, publisher, description: show.description ? String(show.description).slice(0, 500) : null, artwork_url: images[0]?.url ?? null, feed_url: null, external_url: show.external_urls ? String((show.external_urls as Record<string, string>).spotify ?? "") : null, episode_count: show.total_episodes ? Number(show.total_episodes) : null };
}

// ── Spotify import ────────────────────────────────────────────────────────────

async function importSpotifyBundle(
  ctx: ActionCtx,
  userId: string,
  linkId: string,
  accessToken: string,
  refreshToken: string | null,
  expiresAt: number | null,
): Promise<void> {
  const [savedTracksItems, savedShowsItems, recentTracksItems] = await Promise.all([
    spotifyPaginate("/me/tracks", accessToken).catch(() => [] as Record<string, unknown>[]),
    spotifyPaginate("/me/shows", accessToken).catch(() => [] as Record<string, unknown>[]),
    spotifyPaginate("/me/player/recently-played?limit=50", accessToken).catch(() => [] as Record<string, unknown>[]),
  ]);

  const profile = await fetchSpotifyApi("/me", accessToken).catch(() => ({}));
  const uid = userId as never;

  let likedTracksImported = 0;
  for (const item of savedTracksItems) {
    const track = mapSpotifyTrack((item as Record<string, unknown>).track as Record<string, unknown>);
    if (track) { await ctx.runMutation(api.savedTracks.save, { userId: uid, trackKey: track.track_key, trackPayload: track as never }); likedTracksImported++; }
  }

  let savedShowsImported = 0;
  for (const item of savedShowsItems) {
    const podcast = mapSpotifyShow((item as Record<string, unknown>).show as Record<string, unknown>);
    if (podcast) { await ctx.runMutation(api.podcasts.saveShow, { userId: uid, podcastKey: podcast.podcast_key, podcastPayload: podcast as never }); savedShowsImported++; }
  }

  let recentTracksImported = 0;
  for (const item of recentTracksItems) {
    const track = mapSpotifyTrack((item as Record<string, unknown>).track as Record<string, unknown>);
    if (track) {
      await ctx.runMutation(api.playbackEvents.record, { userId: uid, trackKey: track.track_key, eventType: "play_started", listenedMs: 0, completionRatio: 0, trackPayload: track as never });
      recentTracksImported++;
    }
  }

  await ctx.runMutation(api.spotify.upsert, {
    userId: uid,
    spotifyUserId: String(profile.id ?? ""),
    displayName: profile.display_name ? String(profile.display_name) : undefined,
    email: profile.email ? String(profile.email) : undefined,
    avatarUrl: profile.images ? String(((profile.images as Record<string, unknown>[])[0] as Record<string, string>)?.url ?? "") : undefined,
    country: profile.country ? String(profile.country) : undefined,
    product: profile.product ? String(profile.product) : undefined,
    accessToken: accessToken,
    refreshToken: refreshToken ?? undefined,
    tokenExpiresAt: expiresAt ?? undefined,
    importedAt: Date.now(),
    likedTracksImported,
    savedShowsImported,
    savedEpisodesImported: 0,
    recentTracksImported,
  });
}

// ── Exported internalActions ──────────────────────────────────────────────────

export const spotifyConnect = internalAction({
  args: { userId: v.string() },
  handler: async (_ctx, args) => {
    if (!sp.clientId() || !sp.clientSecret() || !sp.redirectUri()) {
      return { ok: false as const, error: "Spotify integration not configured", status: 503 };
    }
    const state = signJwt({ sub: args.userId, kind: "spotify_link" }, 15 * 60);
    const params = new URLSearchParams({ client_id: sp.clientId(), response_type: "code", redirect_uri: sp.redirectUri(), scope: sp.scopes, state, show_dialog: "true" });
    return { ok: true as const, authorize_url: `https://accounts.spotify.com/authorize?${params.toString()}` };
  },
});

export const spotifyCallback = internalAction({
  args: { code: v.optional(v.string()), state: v.optional(v.string()), error: v.optional(v.string()) },
  handler: async (ctx, args) => {
    if (args.error || !args.code || !args.state) {
      return callbackHtml(false, args.error ?? "Aucun code reçu");
    }
    const payload = verifyJwt(args.state);
    if (!payload || payload.kind !== "spotify_link" || typeof payload.sub !== "string") {
      return callbackHtml(false, "État invalide ou expiré");
    }
    const userId = payload.sub;
    try {
      const tokens = await exchangeSpotifyCode(args.code);
      await importSpotifyBundle(ctx, userId, "", tokens.accessToken, tokens.refreshToken, tokens.expiresAt);
      return callbackHtml(true, "Compte Spotify connecté avec succès !");
    } catch (err) {
      return callbackHtml(false, err instanceof Error ? err.message : "Erreur inconnue");
    }
  },
});

export const spotifySync = internalAction({
  args: { userId: v.string() },
  handler: async (ctx, args) => {
    const link = await ctx.runQuery(api.spotify.get, { userId: args.userId as never });
    if (!link) return { ok: false as const, error: "Compte Spotify non connecté", status: 404 };
    try {
      const tokens = await ensureSpotifyAccessToken(link);
      await importSpotifyBundle(ctx, args.userId, String(link._id), tokens.accessToken, tokens.refreshToken, tokens.expiresAt);
      return { ok: true as const };
    } catch (err) {
      return { ok: false as const, error: err instanceof Error ? err.message : "Sync failed", status: 500 };
    }
  },
});

export const spotifyStatus = internalAction({
  args: { userId: v.string() },
  handler: async (ctx, args) => {
    const configured = !!(sp.clientId() && sp.clientSecret() && sp.redirectUri());
    const link = await ctx.runQuery(api.spotify.get, { userId: args.userId as never });
    if (!link) {
      return { configured, connected: false, liked_tracks_imported: 0, saved_shows_imported: 0, saved_episodes_imported: 0, recent_tracks_imported: 0, saved_shows: [] };
    }
    const shows = await ctx.runQuery(api.podcasts.listShows, { userId: args.userId as never });
    return {
      configured, connected: true,
      spotify_user_id: link.spotifyUserId,
      display_name: link.displayName ?? null,
      email: link.email ?? null,
      avatar_url: link.avatarUrl ?? null,
      country: link.country ?? null,
      product: link.product ?? null,
      imported_at: link.importedAt ? new Date(link.importedAt).toISOString() : null,
      liked_tracks_imported: link.likedTracksImported,
      saved_shows_imported: link.savedShowsImported,
      saved_episodes_imported: link.savedEpisodesImported,
      recent_tracks_imported: link.recentTracksImported,
      saved_shows: shows.map(s => s.podcastPayload),
    };
  },
});

export const spotifyDisconnect = internalAction({
  args: { userId: v.string() },
  handler: async (ctx, args) => {
    const uid = args.userId as never;
    await Promise.all([
      ctx.runMutation(api.spotify.remove, { userId: uid }),
    ]);
  },
});

function callbackHtml(success: boolean, message: string): string {
  const color = success ? "#1DB954" : "#E53E3E";
  const icon = success ? "✓" : "✗";
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Spotify ${success ? "Connecté" : "Erreur"}</title><style>body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#121212;color:#fff}.card{text-align:center;padding:2rem;background:#1a1a1a;border-radius:12px;max-width:400px}.icon{font-size:4rem;color:${color}}.message{margin-top:1rem;font-size:1.1rem;opacity:.9}</style></head><body><div class="card"><div class="icon">${icon}</div><div class="message">${message}</div><p style="opacity:.5;font-size:.85rem;margin-top:1rem">Tu peux fermer cette fenêtre.</p></div></body></html>`;
}
