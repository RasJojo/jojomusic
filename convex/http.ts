import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { api, internal } from "./_generated/api";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

function html(body: string, status = 200): Response {
  return new Response(body, { status, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

// Validates Bearer token and returns user id/name/email, or returns a 401 response.
async function requireUser(ctx: Parameters<Parameters<typeof httpAction>[0]>[0], request: Request): Promise<{ id: string; name: string; email: string } | Response> {
  const auth = request.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Token manquant" }, 401);
  const token = auth.slice(7).trim();
  const result = await ctx.runAction(internal.authNode.verifyToken, { token });
  if (!result.ok) return json({ error: result.error }, result.status);
  return { id: result.id, name: result.name, email: result.email };
}

const http = httpRouter();

// ── Health ─────────────────────────────────────────────────────────────────────

http.route({ path: "/health", method: "GET", handler: httpAction(async () => json({ ok: true })) });

// ── Auth ───────────────────────────────────────────────────────────────────────

http.route({
  path: "/auth/register", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || typeof body.email !== "string" || typeof body.password !== "string" || typeof body.name !== "string") {
      return json({ error: "name, email et password requis" }, 400);
    }
    const result = await ctx.runAction(internal.authNode.register, { email: body.email, password: body.password, name: body.name });
    if (!result.ok) return json({ error: result.error }, result.status);
    return json({ access_token: result.access_token, token_type: "bearer", user: result.user, convex_user_id: result.convex_user_id });
  }),
});

http.route({
  path: "/auth/login", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || typeof body.email !== "string" || typeof body.password !== "string") {
      return json({ error: "email et password requis" }, 400);
    }
    const result = await ctx.runAction(internal.authNode.login, { email: body.email, password: body.password });
    if (!result.ok) return json({ error: result.error }, result.status);
    return json({ access_token: result.access_token, token_type: "bearer", user: result.user, convex_user_id: result.convex_user_id });
  }),
});

http.route({
  path: "/auth/me", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    return json({ id: user.id, name: user.name, email: user.email });
  }),
});

// ── Music content (no auth required) ──────────────────────────────────────────

http.route({
  path: "/search", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const query = url.searchParams.get("query") ?? "";
    const limit = parseInt(url.searchParams.get("limit") ?? "20");
    try {
      const result = await ctx.runAction(internal.musicContent.search, { query, limit });
      return json(result);
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/artists/details", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const name = url.searchParams.get("name") ?? "";
    if (!name) return json({ error: "name requis" }, 400);
    try {
      return json(await ctx.runAction(internal.musicContent.artistDetails, { name }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/albums/details", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const artist = url.searchParams.get("artist") ?? "";
    const title = url.searchParams.get("title") ?? "";
    if (!artist || !title) return json({ error: "artist et title requis" }, 400);
    try {
      return json(await ctx.runAction(internal.musicContent.albumDetails, { artist, title, external_id: url.searchParams.get("external_id") ?? undefined }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/browse/categories", method: "GET",
  handler: httpAction(async (ctx) => {
    try {
      return json(await ctx.runAction(internal.musicContent.browseCategories, {}));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  pathPrefix: "/browse/categories/", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const categoryId = new URL(request.url).pathname.replace("/browse/categories/", "");
    if (!categoryId) return json({ error: "categoryId requis" }, 400);
    try {
      return json(await ctx.runAction(internal.musicContent.browseCategory, { categoryId }));
    } catch (e) {
      return e instanceof Error && e.message === "NOT_FOUND" ? json({ error: "Not found" }, 404) : json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/podcasts/search", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const query = url.searchParams.get("query") ?? "";
    const limit = parseInt(url.searchParams.get("limit") ?? "12");
    try {
      return json(await ctx.runAction(internal.musicContent.searchPodcasts, { query, limit }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  pathPrefix: "/podcasts/", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const podcastKey = decodeURIComponent(new URL(request.url).pathname.replace("/podcasts/", ""));
    if (!podcastKey) return json({ error: "podcastKey requis" }, 400);
    try {
      return json(await ctx.runAction(internal.musicContent.podcastDetails, { podcastKey }));
    } catch (e) {
      return e instanceof Error && e.message === "NOT_FOUND" ? json({ error: "Not found" }, 404) : json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/tracks/artwork", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const artist = url.searchParams.get("artist") ?? "";
    const title = url.searchParams.get("title") ?? "";
    try {
      return json(await ctx.runAction(internal.musicContent.trackArtwork, { artist, title }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/lyrics", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const artist = url.searchParams.get("artist") ?? "";
    const title = url.searchParams.get("title") ?? "";
    try {
      const result = await ctx.runAction(internal.musicContent.lyrics, { artist, title });
      if (!result) return new Response(null, { status: 204 });
      return json(result);
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/tracks/resolve", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body) return json({ error: "Body requis" }, 400);
    try {
      const result = await ctx.runAction(internal.musicContent.resolveTrack, { track: body.track, query: body.query as string | undefined, artist: body.artist as string | undefined, title: body.title as string | undefined, allowPreview: body.allow_preview as boolean | undefined });
      return json(result);
    } catch (e) {
      return json({ error: String(e) }, e instanceof Error && e.message === "MISSING_QUERY" ? 400 : 503);
    }
  }),
});

http.route({
  path: "/tracks/similar", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body?.track) return json({ error: "track requis" }, 400);
    try {
      return json(await ctx.runAction(internal.musicContent.similarTracks, { track: body.track, exclude_track_keys: body.exclude_track_keys as string[] | undefined, limit: body.limit as number | undefined }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

// ── Me — likes ─────────────────────────────────────────────────────────────────

http.route({
  path: "/me/likes", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const rows = await ctx.runQuery(api.savedTracks.list, { userId: user.id as never });
    return json(rows.map(r => r.trackPayload));
  }),
});

http.route({
  path: "/me/likes", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const track = await request.json().catch(() => null);
    if (!track?.track_key) return json({ error: "track_key requis" }, 400);
    await ctx.runMutation(api.savedTracks.save, { userId: user.id as never, trackKey: track.track_key, trackPayload: track });
    return json(track);
  }),
});

http.route({
  pathPrefix: "/me/likes/", method: "DELETE",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const trackKey = new URL(request.url).pathname.replace("/me/likes/", "");
    await ctx.runMutation(api.savedTracks.unsave, { userId: user.id as never, trackKey });
    return new Response(null, { status: 204 });
  }),
});

// ── Me — history ───────────────────────────────────────────────────────────────

http.route({
  path: "/me/history", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const rows = await ctx.runQuery(api.playbackEvents.history, { userId: user.id as never, limit: 50 });
    return json(rows);
  }),
});

http.route({
  path: "/me/history", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body?.track || typeof (body.track as Record<string, unknown>).track_key !== "string") return json({ error: "track requis" }, 400);
    const track = body.track as Record<string, unknown>;
    await ctx.runMutation(api.playbackEvents.record, {
      userId: user.id as never,
      trackKey: String(track.track_key),
      eventType: String(body.event_type ?? "play_started"),
      listenedMs: Number(body.listened_ms ?? 0),
      completionRatio: Number(body.completion_ratio ?? 0),
      trackPayload: track,
    });
    return new Response(null, { status: 204 });
  }),
});

// ── Me — home & recommendations ────────────────────────────────────────────────

http.route({
  path: "/me/home", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    try {
      return json(await ctx.runAction(internal.musicContent.home, { userId: user.id }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/recommendations", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    try {
      return json(await ctx.runAction(internal.musicContent.recommendations, { userId: user.id }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

// ── Me — podcasts ──────────────────────────────────────────────────────────────

http.route({
  path: "/me/podcasts", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const rows = await ctx.runQuery(api.podcasts.listShows, { userId: user.id as never });
    return json(rows.map(r => r.podcastPayload));
  }),
});

http.route({
  path: "/me/podcasts", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    const podcast = body?.podcast as Record<string, unknown> | undefined;
    if (!podcast?.podcast_key) return json({ error: "podcast requis" }, 400);
    await ctx.runMutation(api.podcasts.saveShow, { userId: user.id as never, podcastKey: String(podcast.podcast_key), podcastPayload: podcast });
    return json(podcast);
  }),
});

http.route({
  pathPrefix: "/me/podcasts/", method: "DELETE",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const podcastKey = decodeURIComponent(new URL(request.url).pathname.replace("/me/podcasts/", ""));
    await ctx.runMutation(api.podcasts.unsaveShow, { userId: user.id as never, podcastKey });
    return new Response(null, { status: 204 });
  }),
});

// ── Playlists ──────────────────────────────────────────────────────────────────

http.route({
  path: "/playlists", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const playlists = await ctx.runQuery(api.playlists.list, { userId: user.id as never });
    return json(playlists.map(p => ({
      id: p._id, name: p.name, description: p.description,
      artwork_url: p.artworkUrl ?? bestArtwork(p.tracks),
      created_at: new Date(p._creationTime).toISOString(),
      updated_at: new Date(p._creationTime).toISOString(),
      tracks: p.tracks.map((t: Record<string, unknown>) => ({ id: t._id, track_key: t.trackKey, position: t.position, track_payload: t.trackPayload, created_at: new Date((t._creationTime as number)).toISOString() })),
    })));
  }),
});

http.route({
  path: "/playlists", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    if (!body?.name) return json({ error: "name requis" }, 400);
    const id = await ctx.runMutation(api.playlists.create, { userId: user.id as never, name: String(body.name), description: body.description ? String(body.description) : undefined, artworkUrl: body.artwork_url ? String(body.artwork_url) : undefined });
    const playlists = await ctx.runQuery(api.playlists.list, { userId: user.id as never });
    const playlist = playlists.find((p: Record<string, unknown>) => p._id === id) ?? playlists[0];
    return json(toPlaylistOut(playlist));
  }),
});

http.route({
  pathPrefix: "/playlists/", method: "PATCH",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const playlistId = new URL(request.url).pathname.replace("/playlists/", "");
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    try {
      await ctx.runMutation(api.playlists.update, { playlistId: playlistId as never, userId: user.id as never, name: body?.name ? String(body.name) : undefined, description: body?.description ? String(body.description) : undefined, artworkUrl: body?.artwork_url ? String(body.artwork_url) : undefined });
      const playlists = await ctx.runQuery(api.playlists.list, { userId: user.id as never });
      const playlist = playlists.find((p: Record<string, unknown>) => p._id === playlistId);
      if (!playlist) return json({ error: "Not found" }, 404);
      return json(toPlaylistOut(playlist));
    } catch (e) {
      return e instanceof Error && e.message === "NOT_FOUND" ? json({ error: "Not found" }, 404) : json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  pathPrefix: "/playlists/", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const path = new URL(request.url).pathname;
    const parts = path.replace("/playlists/", "").split("/");
    const playlistId = parts[0];
    const body = await request.json().catch(() => null) as Record<string, unknown> | null;
    const track = body?.track as Record<string, unknown> | undefined;
    if (!track?.track_key) return json({ error: "track requis" }, 400);
    try {
      await ctx.runMutation(api.playlists.addTrack, { playlistId: playlistId as never, userId: user.id as never, trackKey: String(track.track_key), trackPayload: track });
      const playlists = await ctx.runQuery(api.playlists.list, { userId: user.id as never });
      const playlist = playlists.find((p: Record<string, unknown>) => p._id === playlistId);
      if (!playlist) return json({ error: "Not found" }, 404);
      return json(toPlaylistOut(playlist));
    } catch (e) {
      return e instanceof Error && e.message === "NOT_FOUND" ? json({ error: "Not found" }, 404) : json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  pathPrefix: "/playlists/", method: "DELETE",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const path = new URL(request.url).pathname;
    const parts = path.replace("/playlists/", "").split("/");
    const playlistId = parts[0];
    if (parts[1] === "tracks" && parts[2]) {
      const trackKey = decodeURIComponent(parts[2]);
      try {
        await ctx.runMutation(api.playlists.removeTrack, { playlistId: playlistId as never, userId: user.id as never, trackKey });
        const playlists = await ctx.runQuery(api.playlists.list, { userId: user.id as never });
        const playlist = playlists.find((p: Record<string, unknown>) => p._id === playlistId);
        if (!playlist) return json({ error: "Not found" }, 404);
        return json(toPlaylistOut(playlist));
      } catch (e) {
        return e instanceof Error && e.message === "NOT_FOUND" ? json({ error: "Not found" }, 404) : json({ error: String(e) }, 500);
      }
    }
    try {
      await ctx.runMutation(api.playlists.remove, { playlistId: playlistId as never, userId: user.id as never });
      return new Response(null, { status: 204 });
    } catch (e) {
      return e instanceof Error && e.message === "NOT_FOUND" ? json({ error: "Not found" }, 404) : json({ error: String(e) }, 500);
    }
  }),
});

// ── Spotify integration ────────────────────────────────────────────────────────

http.route({
  path: "/me/integrations/spotify", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    try {
      return json(await ctx.runAction(internal.spotifyNode.spotifyStatus, { userId: user.id }));
    } catch (e) {
      return json({ error: String(e) }, 500);
    }
  }),
});

http.route({
  path: "/me/integrations/spotify/connect", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const result = await ctx.runAction(internal.spotifyNode.spotifyConnect, { userId: user.id });
    if (!result.ok) return json({ error: result.error }, result.status);
    return json({ authorize_url: result.authorize_url });
  }),
});

http.route({
  path: "/me/integrations/spotify/sync", method: "POST",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    const result = await ctx.runAction(internal.spotifyNode.spotifySync, { userId: user.id });
    if (!result.ok) return json({ error: result.error }, result.status);
    return json(await ctx.runAction(internal.spotifyNode.spotifyStatus, { userId: user.id }));
  }),
});

http.route({
  path: "/me/integrations/spotify", method: "DELETE",
  handler: httpAction(async (ctx, request) => {
    const user = await requireUser(ctx, request);
    if (user instanceof Response) return user;
    await ctx.runAction(internal.spotifyNode.spotifyDisconnect, { userId: user.id });
    return new Response(null, { status: 204 });
  }),
});

http.route({
  path: "/integrations/spotify/callback", method: "GET",
  handler: httpAction(async (ctx, request) => {
    const url = new URL(request.url);
    const result = await ctx.runAction(internal.spotifyNode.spotifyCallback, {
      code: url.searchParams.get("code") ?? undefined,
      state: url.searchParams.get("state") ?? undefined,
      error: url.searchParams.get("error") ?? undefined,
    });
    return html(result);
  }),
});

// ── CORS preflight ─────────────────────────────────────────────────────────────

http.route({
  pathPrefix: "/",
  method: "OPTIONS",
  handler: httpAction(async () =>
    new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    })
  ),
});

// ── Helpers ────────────────────────────────────────────────────────────────────

function bestArtwork(tracks: unknown[]): string | null {
  for (const t of tracks) {
    const tp = (t as Record<string, unknown>).trackPayload as Record<string, unknown> | null;
    if (tp?.artwork_url) return String(tp.artwork_url);
    if (tp?.artist_image_url) return String(tp.artist_image_url);
  }
  return null;
}

function toPlaylistOut(p: Record<string, unknown>): Record<string, unknown> {
  const tracks = (p.tracks as Record<string, unknown>[] | undefined) ?? [];
  return {
    id: p._id, name: p.name, description: p.description,
    artwork_url: p.artworkUrl ?? bestArtwork(tracks),
    created_at: new Date((p._creationTime as number)).toISOString(),
    updated_at: new Date((p._creationTime as number)).toISOString(),
    tracks: tracks.map(t => ({ id: t._id, track_key: t.trackKey, position: t.position, track_payload: t.trackPayload, created_at: new Date((t._creationTime as number)).toISOString() })),
  };
}

export default http;
