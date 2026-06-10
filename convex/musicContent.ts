"use node";

import { createHash } from "node:crypto";
import { internalAction } from "./_generated/server";
import { v } from "convex/values";
import { api } from "./_generated/api";
import type { ActionCtx } from "./_generated/server";

// ── Env ───────────────────────────────────────────────────────────────────────

const env = {
  lastfmKey: () => process.env.LASTFM_API_KEY ?? "",
  geniusToken: () => process.env.GENIUS_ACCESS_TOKEN ?? "",
  lrclibBase: () =>
    (process.env.LRCLIB_BASE_URL ?? "https://lrclib.net").replace(/\/+$/, ""),
  resolverUrl: () =>
    (process.env.RESOLVER_API_URL ?? "http://jojomusic-resolver:8000").replace(
      /\/+$/,
      "",
    ),
  resolverTimeoutMs: () =>
    parseInt(process.env.RESOLVER_TIMEOUT_SECONDS ?? "25") * 1000,
  publicBaseUrl: () =>
    (
      process.env.PUBLIC_BASE_URL ?? "https://jojomusicapi.jojoserv.com"
    ).replace(/\/+$/, ""),
  spotifyClientId: () => process.env.SPOTIFY_CLIENT_ID ?? "",
  spotifyClientSecret: () => process.env.SPOTIFY_CLIENT_SECRET ?? "",
  spotifyRedirectUri: () =>
    process.env.SPOTIFY_REDIRECT_URI ??
    "https://convex-site.jojoserv.com/integrations/spotify/callback",
};

const ITUNES_BASE = "https://itunes.apple.com";
const LASTFM_BASE = "https://ws.audioscrobbler.com/2.0/";
const MUSICBRAINZ_BASE = "https://musicbrainz.org/ws/2";

const TTL = {
  SEARCH: 5 * 60_000,
  ARTIST: 60 * 60_000,
  ALBUM: 60 * 60_000,
  BROWSE: 60 * 60_000,
  BROWSE_CAT: 30 * 60_000,
  PODCASTS_SEARCH: 5 * 60_000,
  PODCAST: 30 * 60_000,
  ARTWORK: 60 * 60_000,
  LYRICS: 60 * 60_000,
  SIMILAR: 30 * 60_000,
  HOME_HEAVY: 10 * 60_000,
  RECOMMENDATIONS: 10 * 60_000,
};

async function withCache<T>(
  ctx: ActionCtx,
  key: string,
  ttlMs: number,
  fn: () => Promise<T>,
): Promise<T> {
  const cached = await ctx.runQuery(api.cache.get, { key });
  if (cached && Date.now() - (cached.cachedAt as number) < ttlMs)
    return JSON.parse(cached.value as string) as T;
  const result = await fn();
  void ctx.runMutation(api.cache.set, {
    key,
    value: JSON.stringify(result),
    cachedAt: Date.now(),
  });
  return result;
}

async function withSuccessCache<T>(
  ctx: ActionCtx,
  key: string,
  ttlMs: number,
  fn: () => Promise<T | null>,
): Promise<T | null> {
  const cached = await ctx.runQuery(api.cache.get, { key });
  if (cached && Date.now() - (cached.cachedAt as number) < ttlMs) {
    const value = JSON.parse(cached.value as string) as T | null;
    if (value != null) return value;
  }
  const result = await fn();
  if (result != null) {
    void ctx.runMutation(api.cache.set, {
      key,
      value: JSON.stringify(result),
      cachedAt: Date.now(),
    });
  }
  return result;
}

// ── Types ─────────────────────────────────────────────────────────────────────

export type TrackPayload = {
  track_key: string;
  title: string;
  artist: string;
  album?: string | null;
  artwork_url?: string | null;
  artist_image_url?: string | null;
  duration_ms?: number | null;
  provider: string;
  external_id?: string | null;
  preview_url?: string | null;
  lyrics_synced_available: boolean;
};
export type ArtistPayload = {
  artist_key: string;
  name: string;
  image_url?: string | null;
  provider: string;
  external_id?: string | null;
  url?: string | null;
  listeners?: number | null;
  summary?: string | null;
};
export type AlbumPayload = {
  album_key: string;
  title: string;
  artist: string;
  artwork_url?: string | null;
  provider: string;
  external_id?: string | null;
  summary?: string | null;
  release_date?: string | null;
  track_count?: number | null;
};
export type PodcastPayload = {
  podcast_key: string;
  title: string;
  publisher: string;
  description?: string | null;
  artwork_url?: string | null;
  feed_url?: string | null;
  external_url?: string | null;
  episode_count?: number | null;
  release_date?: string | null;
};
export type PodcastEpisodePayload = {
  episode_key: string;
  podcast_title: string;
  title: string;
  publisher?: string | null;
  description?: string | null;
  artwork_url?: string | null;
  audio_url?: string | null;
  external_url?: string | null;
  duration_seconds?: number | null;
  published_at?: string | null;
};
export type BrowseCategoryPayload = {
  category_id: string;
  title: string;
  subtitle: string;
  color_hex: string;
  search_seed: string;
  artwork_url?: string | null;
};
export type GeneratedPlaylistPayload = {
  playlist_key: string;
  title: string;
  subtitle: string;
  artwork_url?: string | null;
  tracks: TrackPayload[];
};
export type SearchResponse = {
  query: string;
  artists: ArtistPayload[];
  tracks: TrackPayload[];
  albums: AlbumPayload[];
  podcasts: PodcastPayload[];
};
export type ResolvedStream = {
  stream_url: string;
  webpage_url?: string | null;
  thumbnail_url?: string | null;
  title: string;
  artist: string;
  duration_ms?: number | null;
  source: string;
};
export type LyricsResponse = {
  artist: string;
  title: string;
  plain_lyrics?: string | null;
  synced_lyrics?: string | null;
  provider: string;
};
export type HomeResponse = {
  recently_played: TrackPayload[];
  liked_tracks: TrackPayload[];
  recommendations: TrackPayload[];
  generated_playlists: GeneratedPlaylistPayload[];
  browse_categories: BrowseCategoryPayload[];
  featured_podcasts: PodcastPayload[];
};

// ── Static Data ───────────────────────────────────────────────────────────────

export const BROWSE_CATEGORIES: BrowseCategoryPayload[] = [
  {
    category_id: "new-releases",
    title: "Nouveautés",
    subtitle: "Dernières sorties, singles frais et nouveautés à lancer",
    color_hex: "#C04A23",
    search_seed: "new music friday",
  },
  {
    category_id: "pop-hits",
    title: "Pop",
    subtitle: "Hits immédiats, refrains massifs et grosses sorties",
    color_hex: "#8B2877",
    search_seed: "pop hits",
  },
  {
    category_id: "rap-hiphop",
    title: "Rap & Hip-Hop",
    subtitle: "Rap FR, US, trap et gros titres du moment",
    color_hex: "#B1591E",
    search_seed: "rap hip hop",
  },
  {
    category_id: "afro-vibes",
    title: "Afro",
    subtitle: "Afrobeats, amapiano et chaleur instantanée",
    color_hex: "#7A5A00",
    search_seed: "afrobeats amapiano",
  },
  {
    category_id: "mada-vibes",
    title: "Madagascar",
    subtitle: "Mada vibes, rap local, salegy et scène malgache",
    color_hex: "#007A62",
    search_seed: "music malagasy",
  },
  {
    category_id: "chill-mood",
    title: "Chill",
    subtitle: "Calme, focus, late night et textures douces",
    color_hex: "#274A9A",
    search_seed: "chill hits",
  },
  {
    category_id: "workout-energy",
    title: "Workout",
    subtitle: "Énergie, cardio, motivation et percussions lourdes",
    color_hex: "#1E8554",
    search_seed: "workout mix",
  },
  {
    category_id: "love-songs",
    title: "Love",
    subtitle: "Slow jams, pop sentimentale et titres à émotions",
    color_hex: "#A02458",
    search_seed: "love songs rnb",
  },
  {
    category_id: "podcasts-editorial",
    title: "Podcasts musicaux",
    subtitle: "Culture, interviews, société et épisodes longs",
    color_hex: "#5A276F",
    search_seed: "podcast francais",
  },
];

// ── Key builders ──────────────────────────────────────────────────────────────

function normalizeValue(v: string): string {
  return v
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}
function buildTrackKey(artist: string, title: string): string {
  return normalizeValue(`${artist}-${title}`);
}
function buildArtistKey(name: string): string {
  return normalizeValue(name);
}
function buildAlbumKey(artist: string, title: string): string {
  return normalizeValue(`${artist}-${title}`);
}
function buildPodcastKey(publisher: string, title: string): string {
  return normalizeValue(`${publisher}-${title}`);
}
function buildEpisodeKey(podcastKey: string, title: string): string {
  return normalizeValue(`${podcastKey}-${title}`);
}

function makeTrackPayload(
  p: Partial<TrackPayload> & Pick<TrackPayload, "title" | "artist">,
): TrackPayload {
  return {
    track_key: p.track_key ?? buildTrackKey(p.artist, p.title),
    title: p.title,
    artist: p.artist,
    album: p.album ?? null,
    artwork_url: p.artwork_url ?? null,
    artist_image_url: p.artist_image_url ?? null,
    duration_ms: p.duration_ms ?? null,
    provider: p.provider ?? "internal",
    external_id: p.external_id ?? null,
    preview_url: p.preview_url ?? null,
    lyrics_synced_available: p.lyrics_synced_available ?? false,
  };
}

// ── Dedup helpers ─────────────────────────────────────────────────────────────

function dedupeTracks(tracks: TrackPayload[], limit = 9999): TrackPayload[] {
  const seen = new Set<string>();
  return tracks
    .filter((t) => {
      if (seen.has(t.track_key)) return false;
      seen.add(t.track_key);
      return true;
    })
    .slice(0, limit);
}
function dedupeArtists(
  artists: ArtistPayload[],
  limit = 9999,
): ArtistPayload[] {
  const seen = new Set<string>();
  return artists
    .filter((a) => {
      if (seen.has(a.artist_key)) return false;
      seen.add(a.artist_key);
      return true;
    })
    .slice(0, limit);
}
function dedupeAlbums(albums: AlbumPayload[], limit = 9999): AlbumPayload[] {
  const seen = new Set<string>();
  return albums
    .filter((a) => {
      if (seen.has(a.album_key)) return false;
      seen.add(a.album_key);
      return true;
    })
    .slice(0, limit);
}
function dedupeNonEmpty(arr: string[]): string[] {
  const seen = new Set<string>();
  return arr.filter((s) => {
    const t = s.trim();
    if (!t || seen.has(t)) return false;
    seen.add(t);
    return true;
  });
}

// ── Asset key helpers ─────────────────────────────────────────────────────────

function imageAssetLookupKey(entityType: string, entityKey: string): string {
  return createHash("sha1")
    .update(`image:${entityType}:${entityKey}`)
    .digest("hex");
}
function audioAssetLookupKey(cacheKey: string): string {
  return createHash("sha1").update(cacheKey).digest("hex");
}
function resolvedStreamCacheKey(
  payload: { track?: TrackPayload; query?: string },
  query: string,
): string {
  if (payload.track) {
    if (payload.track.external_id)
      return `track:external:${payload.track.external_id}`;
    const parts = [
      payload.track.provider ?? "",
      payload.track.artist ?? "",
      payload.track.title ?? "",
      payload.track.album ?? "",
      payload.track.track_key ?? "",
    ];
    return `track:${parts.map((s) => s.trim().toLowerCase()).join("||")}`;
  }
  return `query:${query.trim().toLowerCase()}`;
}

// ── Fetch helpers ─────────────────────────────────────────────────────────────

async function fetchJson<T>(
  url: string | URL,
  init?: RequestInit,
  timeoutMs = 8000,
): Promise<T> {
  const r = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  return r.json() as Promise<T>;
}
async function fetchText(
  url: string | URL,
  init?: RequestInit,
  timeoutMs = 8000,
): Promise<string> {
  const r = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
  return r.text();
}
async function safe<T>(p: Promise<T>, fallback: T): Promise<T> {
  return p.catch(() => fallback);
}
async function safeTimed<T>(
  fn: () => Promise<T>,
  fallback: T,
  timeoutMs: number,
): Promise<T> {
  return Promise.race([
    fn().catch(() => fallback),
    new Promise<T>((res) => setTimeout(() => res(fallback), timeoutMs)),
  ]);
}

function asList<T>(v: T | T[] | undefined | null): T[] {
  if (!v) return [];
  return Array.isArray(v) ? v : [v];
}

// ── External APIs ─────────────────────────────────────────────────────────────

async function lastfm(
  method: string,
  params: Record<string, string | number>,
): Promise<Record<string, unknown>> {
  const key = env.lastfmKey();
  if (!key) return {};
  const url = new URL(LASTFM_BASE);
  url.searchParams.set("method", method);
  url.searchParams.set("api_key", key);
  url.searchParams.set("format", "json");
  for (const [k, v] of Object.entries(params))
    url.searchParams.set(k, String(v));
  return fetchJson(
    url,
    { headers: { "User-Agent": "jojomusic/1.0" } },
    7000,
  ).catch(() => ({}));
}

async function itunesSearch(
  params: Record<string, string | number>,
): Promise<Record<string, unknown>> {
  const url = new URL(`${ITUNES_BASE}/search`);
  for (const [k, v] of Object.entries(params))
    url.searchParams.set(k, String(v));
  return fetchJson(
    url,
    { headers: { Accept: "application/json" } },
    7000,
  ).catch(() => ({}));
}

function upscaleArtwork(url: string | null | undefined): string | null {
  if (!url) return null;
  const upgraded = url
    .replace("100x100bb", "600x600bb")
    .replace("30x30bb", "600x600bb");
  return isPlaceholderArtworkUrl(upgraded) ? null : upgraded;
}

function isPlaceholderArtworkUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  const normalized = url.toLowerCase();
  return (
    normalized.includes("2a96cbd8b46e442fc41c2b86b821562f") ||
    normalized.includes("/default_album_medium.") ||
    normalized.includes("/default_artist_")
  );
}

function cleanArtworkUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  const trimmed = url.trim();
  return trimmed && !isPlaceholderArtworkUrl(trimmed) ? trimmed : null;
}

function chooseLastfmImage(images: unknown): string | null {
  const arr = asList(images as Record<string, string>[]);
  const sorted = arr
    .filter((i) => i?.["#text"])
    .sort((a, b) => {
      const rank = ["small", "medium", "large", "extralarge", "mega"];
      return rank.indexOf(b?.size ?? "") - rank.indexOf(a?.size ?? "");
    });
  return cleanArtworkUrl(sorted[0]?.["#text"]);
}

function parseDate(s: unknown): string | null {
  if (!s) return null;
  const d = new Date(s as string);
  return isNaN(d.getTime()) ? null : d.toISOString();
}

// ── Track search ──────────────────────────────────────────────────────────────

async function searchTracksItunes(
  query: string,
  limit = 25,
): Promise<TrackPayload[]> {
  const data = await itunesSearch({ term: query, entity: "song", limit });
  const tracks = new Map<string, TrackPayload>();
  for (const item of asList(
    (data as Record<string, unknown>).results as Record<string, unknown>[],
  )) {
    if (!item.artistName || !item.trackName) continue;
    const t = makeTrackPayload({
      title: String(item.trackName),
      artist: String(item.artistName),
      album: item.collectionName ? String(item.collectionName) : null,
      artwork_url: upscaleArtwork(item.artworkUrl100 as string),
      duration_ms: item.trackTimeMillis ? Number(item.trackTimeMillis) : null,
      provider: "itunes",
      external_id: item.trackId ? String(item.trackId) : null,
      preview_url: item.previewUrl ? String(item.previewUrl) : null,
    });
    if (!tracks.has(t.track_key)) tracks.set(t.track_key, t);
  }
  return [...tracks.values()];
}

async function topTracksLastfm(
  artist: string,
  limit = 10,
): Promise<TrackPayload[]> {
  if (!env.lastfmKey()) return [];
  const payload = await lastfm("artist.gettoptracks", { artist, limit });
  return asList(
    (payload as Record<string, Record<string, unknown>>).toptracks?.track,
  )
    .map((row: Record<string, unknown>) => {
      const title = String(row.name ?? "").trim();
      const rowArtist = String(
        (row.artist as Record<string, unknown>)?.name ?? artist,
      ).trim();
      if (!title || !rowArtist) return null;
      return makeTrackPayload({
        title,
        artist: rowArtist,
        artwork_url: chooseLastfmImage(row.image),
        provider: "lastfm",
        external_id: row.mbid ? String(row.mbid) : null,
      });
    })
    .filter((t): t is TrackPayload => t !== null)
    .slice(0, limit);
}

async function similarTracksLastfm(
  artist: string,
  title: string,
  limit = 12,
): Promise<TrackPayload[]> {
  if (!env.lastfmKey()) return [];
  const payload = await lastfm("track.getsimilar", {
    artist,
    track: title,
    limit,
  });
  return asList(
    (payload as Record<string, Record<string, unknown>>).similartracks?.track,
  )
    .map((row: Record<string, unknown>) => {
      const rowArtist = String(
        (row.artist as Record<string, unknown>)?.name ?? "",
      ).trim();
      const rowTitle = String(row.name ?? "").trim();
      if (!rowArtist || !rowTitle) return null;
      return makeTrackPayload({
        title: rowTitle,
        artist: rowArtist,
        artwork_url: chooseLastfmImage(row.image),
        provider: "lastfm",
        external_id: row.mbid ? String(row.mbid) : null,
      });
    })
    .filter((t): t is TrackPayload => t !== null)
    .slice(0, limit);
}

async function topTracksForArtist(
  artist: string,
  limit = 10,
): Promise<TrackPayload[]> {
  const [lf, it] = await Promise.all([
    safe(topTracksLastfm(artist, limit), []),
    safe(
      searchTracksItunes(artist, limit * 2).then((tracks) =>
        dedupeTracks(
          tracks.filter((t) =>
            buildArtistKey(t.artist).includes(buildArtistKey(artist)),
          ),
          limit,
        ),
      ),
      [],
    ),
  ]);
  return dedupeTracks([...lf, ...it], limit);
}

// ── Artist search ─────────────────────────────────────────────────────────────

async function searchLastfmArtists(
  query: string,
  limit = 5,
): Promise<ArtistPayload[]> {
  if (!env.lastfmKey()) return [];
  const payload = await lastfm("artist.search", { artist: query, limit });
  return asList(
    (payload as Record<string, Record<string, Record<string, unknown>>>).results
      ?.artistmatches?.artist,
  )
    .map((row: Record<string, unknown>) => {
      const name = String(row.name ?? "").trim();
      if (!name) return null;
      return {
        artist_key: buildArtistKey(name),
        name,
        image_url: chooseLastfmImage(row.image),
        provider: "lastfm",
        external_id: row.mbid ? String(row.mbid) : null,
        url: row.url ? String(row.url) : null,
      };
    })
    .filter((a): a is ArtistPayload => a !== null)
    .slice(0, limit);
}

async function searchItunesArtists(
  query: string,
  limit = 5,
): Promise<ArtistPayload[]> {
  const data = await itunesSearch({
    term: query,
    entity: "musicArtist",
    limit,
  });
  return asList(
    (data as Record<string, unknown>).results as Record<string, unknown>[],
  )
    .map((row: Record<string, unknown>) => {
      const name = String(row.artistName ?? "").trim();
      if (!name) return null;
      return {
        artist_key: buildArtistKey(name),
        name,
        image_url: null,
        provider: "itunes",
        external_id: row.artistId ? String(row.artistId) : null,
        url: row.artistLinkUrl ? String(row.artistLinkUrl) : null,
      };
    })
    .filter((a): a is ArtistPayload => a !== null)
    .slice(0, limit);
}

async function searchMusicBrainzArtists(
  query: string,
  limit = 6,
): Promise<ArtistPayload[]> {
  const url = new URL(`${MUSICBRAINZ_BASE}/artist`);
  url.searchParams.set("query", query);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("fmt", "json");
  const data: Record<string, unknown> = await fetchJson(
    url,
    { headers: { "User-Agent": "jojomusic/1.0 (joela.rasam@gmail.com)" } },
    7000,
  ).catch(() => ({}));
  return asList(data.artists as Record<string, unknown>[])
    .map((row: Record<string, unknown>) => {
      const name = String(row.name ?? "").trim();
      if (!name) return null;
      return {
        artist_key: buildArtistKey(name),
        name,
        image_url: null,
        provider: "musicbrainz",
        external_id: row.id ? String(row.id) : null,
      };
    })
    .filter((a): a is ArtistPayload => a !== null)
    .slice(0, limit);
}

async function artistInfoLastfm(name: string): Promise<ArtistPayload | null> {
  if (!env.lastfmKey()) return null;
  const payload = await lastfm("artist.getinfo", { artist: name });
  const artist = (payload as Record<string, Record<string, unknown>>).artist;
  if (!artist?.name) return null;
  return {
    artist_key: buildArtistKey(String(artist.name)),
    name: String(artist.name),
    image_url: chooseLastfmImage(artist.image),
    provider: "lastfm",
    external_id: artist.mbid ? String(artist.mbid) : null,
    url: artist.url ? String(artist.url) : null,
    listeners: artist.stats
      ? Number((artist.stats as Record<string, unknown>).listeners)
      : null,
    summary: artist.bio
      ? String((artist.bio as Record<string, unknown>).summary ?? "")
          .replace(/<[^>]+>/g, "")
          .trim() || null
      : null,
  };
}

async function similarArtistsLastfm(
  name: string,
  limit = 8,
): Promise<ArtistPayload[]> {
  if (!env.lastfmKey()) return [];
  const payload = await lastfm("artist.getsimilar", { artist: name, limit });
  return asList(
    (payload as Record<string, Record<string, unknown>>).similarartists?.artist,
  )
    .map((row: Record<string, unknown>) => {
      const artistName = String(row.name ?? "").trim();
      if (!artistName) return null;
      return {
        artist_key: buildArtistKey(artistName),
        name: artistName,
        image_url: chooseLastfmImage(row.image),
        provider: "lastfm",
        external_id: row.mbid ? String(row.mbid) : null,
      };
    })
    .filter((a): a is ArtistPayload => a !== null)
    .slice(0, limit);
}

// ── Album search ──────────────────────────────────────────────────────────────

async function searchAlbums(
  query: string,
  limit = 10,
): Promise<AlbumPayload[]> {
  const data = await itunesSearch({ term: query, entity: "album", limit });
  const albums = new Map<string, AlbumPayload>();
  for (const row of asList(
    (data as Record<string, unknown>).results as Record<string, unknown>[],
  )) {
    const title = String(row.collectionName ?? "").trim();
    const artist = String(row.artistName ?? "").trim();
    if (!title || !artist) continue;
    const key = buildAlbumKey(artist, title);
    if (!albums.has(key))
      albums.set(key, {
        album_key: key,
        title,
        artist,
        artwork_url: upscaleArtwork(row.artworkUrl100 as string),
        provider: "itunes",
        external_id: row.collectionId ? String(row.collectionId) : null,
        release_date: parseDate(row.releaseDate),
        track_count: row.trackCount ? Number(row.trackCount) : null,
      });
  }
  return [...albums.values()];
}

async function albumsForArtist(
  artist: string,
  limit = 8,
): Promise<AlbumPayload[]> {
  const data = await itunesSearch({
    term: artist,
    entity: "album",
    attribute: "artistTerm",
    limit,
  });
  const albums = new Map<string, AlbumPayload>();
  for (const row of asList(
    (data as Record<string, unknown>).results as Record<string, unknown>[],
  )) {
    const title = String(row.collectionName ?? "").trim();
    if (!title) continue;
    const key = buildAlbumKey(artist, title);
    if (!albums.has(key))
      albums.set(key, {
        album_key: key,
        title,
        artist: String(row.artistName ?? artist),
        artwork_url: upscaleArtwork(row.artworkUrl100 as string),
        provider: "itunes",
        external_id: row.collectionId ? String(row.collectionId) : null,
        release_date: parseDate(row.releaseDate),
        track_count: row.trackCount ? Number(row.trackCount) : null,
      });
  }
  return [...albums.values()];
}

async function searchMusicBrainzAlbums(
  query: string,
  limit = 8,
): Promise<AlbumPayload[]> {
  const url = new URL(`${MUSICBRAINZ_BASE}/release-group`);
  url.searchParams.set("query", `${query} AND type:album`);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("fmt", "json");
  const data: Record<string, unknown> = await fetchJson(
    url,
    { headers: { "User-Agent": "jojomusic/1.0 (joela.rasam@gmail.com)" } },
    7000,
  ).catch(() => ({}));
  return asList(data["release-groups"] as Record<string, unknown>[])
    .map((row: Record<string, unknown>) => {
      const title = String(row.title ?? "").trim();
      const credit = asList(row["artist-credit"] as Record<string, unknown>[]);
      const artist = credit.length
        ? String(
            (credit[0] as Record<string, unknown>).artist
              ? (
                  (credit[0] as Record<string, unknown>).artist as Record<
                    string,
                    unknown
                  >
                ).name
              : (credit[0].name ?? ""),
          )
        : "";
      if (!title || !artist) return null;
      return {
        album_key: buildAlbumKey(artist, title),
        title,
        artist: String(artist),
        artwork_url: null,
        provider: "musicbrainz",
        external_id: row.id ? String(row.id) : null,
        release_date: parseDate(row["first-release-date"]),
      };
    })
    .filter((a): a is AlbumPayload => a !== null)
    .slice(0, limit);
}

// ── Album details ─────────────────────────────────────────────────────────────

async function albumDetailsLastfm(
  artist: string,
  title: string,
): Promise<{ album: AlbumPayload | null; tracks: TrackPayload[] }> {
  if (!env.lastfmKey()) return { album: null, tracks: [] };
  const payload = await lastfm("album.getinfo", { artist, album: title });
  const a = (payload as Record<string, Record<string, unknown>>).album;
  if (!a) return { album: null, tracks: [] };
  const tracks = asList((a.tracks as Record<string, unknown>)?.track)
    .map((t: Record<string, unknown>) =>
      makeTrackPayload({
        title: String(t.name ?? ""),
        artist: String((t.artist as Record<string, unknown>)?.name ?? artist),
        album: title,
        artwork_url: chooseLastfmImage(a.image),
        provider: "lastfm",
        external_id: t.mbid ? String(t.mbid) : null,
        duration_ms: t.duration ? Number(t.duration) * 1000 : null,
      }),
    )
    .filter((t) => t.title && t.artist);
  return {
    album: {
      album_key: buildAlbumKey(artist, title),
      title: String(a.name ?? title),
      artist,
      artwork_url: chooseLastfmImage(a.image),
      provider: "lastfm",
      external_id: a.mbid ? String(a.mbid) : null,
      summary: a.wiki
        ? String((a.wiki as Record<string, unknown>).summary ?? "")
            .replace(/<[^>]+>/g, "")
            .trim() || null
        : null,
    },
    tracks,
  };
}

async function albumDetailsItunes(
  artist: string,
  title: string,
  externalId?: string | null,
): Promise<{ album: AlbumPayload | null; tracks: TrackPayload[] }> {
  let results: Record<string, unknown>[];
  if (externalId) {
    const data = await itunesSearch({ id: externalId, entity: "song" }).catch(
      () => ({}),
    );
    results = asList(
      (data as Record<string, unknown>).results as Record<string, unknown>[],
    );
  } else {
    const data = await itunesSearch({
      term: `${artist} ${title}`,
      entity: "album",
      limit: 5,
    });
    const albumRow = asList(
      (data as Record<string, unknown>).results as Record<string, unknown>[],
    ).find((r) => r.collectionType === "Album");
    if (!albumRow?.collectionId) return { album: null, tracks: [] };
    const detail = await itunesSearch({
      id: String(albumRow.collectionId),
      entity: "song",
    }).catch(() => ({}));
    results = asList(
      (detail as Record<string, unknown>).results as Record<string, unknown>[],
    );
  }
  const albumRow = results.find(
    (r) => r.collectionType === "Album" || r.wrapperType === "collection",
  );
  const trackRows = results.filter(
    (r) => r.wrapperType === "track" && r.kind === "song",
  );
  if (!albumRow && !trackRows.length) return { album: null, tracks: [] };
  const artworkUrl = upscaleArtwork(albumRow?.artworkUrl100 as string | null);
  const tracks = trackRows.map((r) =>
    makeTrackPayload({
      title: String(r.trackName ?? ""),
      artist: String(r.artistName ?? artist),
      album: String(r.collectionName ?? title),
      artwork_url: artworkUrl,
      duration_ms: r.trackTimeMillis ? Number(r.trackTimeMillis) : null,
      provider: "itunes",
      external_id: r.trackId ? String(r.trackId) : null,
      preview_url: r.previewUrl ? String(r.previewUrl) : null,
    }),
  );
  return {
    album: albumRow
      ? {
          album_key: buildAlbumKey(artist, title),
          title: String(albumRow.collectionName ?? title),
          artist: String(albumRow.artistName ?? artist),
          artwork_url: artworkUrl,
          provider: "itunes",
          external_id: albumRow.collectionId
            ? String(albumRow.collectionId)
            : null,
          release_date: parseDate(albumRow.releaseDate),
          track_count: trackRows.length,
        }
      : null,
    tracks,
  };
}

// ── Podcast search ─────────────────────────────────────────────────────────────

async function itunesPodcastSearch(
  term: string,
  limit: number,
): Promise<Record<string, unknown>[]> {
  const data = await itunesSearch({ term, entity: "podcast", limit }).catch(
    () => ({}),
  );
  return asList(
    (data as Record<string, unknown>).results as Record<string, unknown>[],
  );
}

function mapItunesPodcast(
  item: Record<string, unknown>,
): PodcastPayload | null {
  const title = String(item.collectionName ?? item.trackName ?? "").trim();
  const publisher = String(item.artistName ?? "").trim();
  if (!title || !publisher) return null;
  return {
    podcast_key: buildPodcastKey(publisher, title),
    title,
    publisher,
    description: null,
    artwork_url: upscaleArtwork(
      (item.artworkUrl600 as string) ?? (item.artworkUrl100 as string),
    ),
    feed_url: item.feedUrl ? String(item.feedUrl) : null,
    external_url: item.collectionViewUrl
      ? String(item.collectionViewUrl)
      : null,
    episode_count: item.trackCount ? Number(item.trackCount) : null,
    release_date: parseDate(item.releaseDate),
  };
}

async function searchPodcastsImpl(
  query: string,
  limit = 12,
): Promise<PodcastPayload[]> {
  const variants = dedupeNonEmpty([
    query,
    `${query} podcast`,
    query.split(/\s+/)[0],
  ]);
  const seen = new Map<string, PodcastPayload>();
  await Promise.all(
    variants.map(async (term) => {
      const items = await safe(itunesPodcastSearch(term, limit * 2), []);
      for (const item of items) {
        const pod = mapItunesPodcast(item);
        if (pod && !seen.has(pod.podcast_key)) seen.set(pod.podcast_key, pod);
      }
    }),
  );
  return [...seen.values()].slice(0, limit);
}

// ── Podcast RSS parsing ───────────────────────────────────────────────────────

function extractXmlTag(xml: string, tag: string, nth = 0): string | null {
  const re = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, "gi");
  let match: RegExpExecArray | null;
  let count = 0;
  while ((match = re.exec(xml)) !== null) {
    if (count++ === nth)
      return match[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").trim();
  }
  return null;
}

function extractXmlAttr(xml: string, tag: string, attr: string): string | null {
  const re = new RegExp(`<${tag}[^>]*\\s${attr}="([^"]*)"`, "i");
  const match = xml.match(re);
  return match ? match[1] : null;
}

function parseRssItems(feedXml: string): PodcastEpisodePayload[] {
  const itemRe = /<item[\s>][\s\S]*?<\/item>/gi;
  const episodes: PodcastEpisodePayload[] = [];
  let match: RegExpExecArray | null;
  while ((match = itemRe.exec(feedXml)) !== null) {
    const xml = match[0];
    const title = extractXmlTag(xml, "title") ?? "";
    if (!title) continue;
    const audioUrl = extractXmlAttr(xml, "enclosure", "url") ?? null;
    const durationRaw =
      extractXmlTag(xml, "itunes:duration") ?? extractXmlTag(xml, "duration");
    const duration_seconds = durationRaw ? parseDuration(durationRaw) : null;
    const pubDateRaw = extractXmlTag(xml, "pubDate");
    const imageHref = extractXmlAttr(xml, "itunes:image", "href") ?? null;
    const description =
      extractXmlTag(xml, "itunes:summary") ?? extractXmlTag(xml, "description");
    const episodeKey = buildEpisodeKey("ep", title);
    episodes.push({
      episode_key: episodeKey,
      podcast_title: "",
      title,
      description: description
        ? description.replace(/<[^>]+>/g, "").slice(0, 500)
        : null,
      artwork_url: imageHref,
      audio_url: audioUrl,
      duration_seconds,
      published_at: pubDateRaw ? parseDate(pubDateRaw) : null,
    });
  }
  return episodes;
}

function parseDuration(s: string): number | null {
  const parts = s.split(":").map(Number);
  if (parts.some(isNaN)) {
    const n = parseFloat(s);
    return isNaN(n) ? null : Math.round(n);
  }
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return parts[0];
}

// ── Lyrics ────────────────────────────────────────────────────────────────────

async function fetchLrclibLyrics(
  artist: string,
  title: string,
): Promise<LyricsResponse | null> {
  const primaryArtist = artist
    .split(/\s*(?:&|,|feat\.?|ft\.?|featuring|avec)\s*/i)[0]
    .trim();
  const requests = dedupeNonEmpty([primaryArtist, artist]).map(async (a) => {
    const url = new URL(`${env.lrclibBase()}/api/search`);
    url.searchParams.set("track_name", title);
    url.searchParams.set("artist_name", a);
    const payload = await safe(
      fetchJson<Record<string, unknown>[]>(url, undefined, 9000),
      [],
    );
    const candidate = payload[0];
    if (candidate)
      return {
        artist,
        title,
        plain_lyrics: candidate.plainLyrics
          ? String(candidate.plainLyrics)
          : null,
        synced_lyrics: candidate.syncedLyrics
          ? String(candidate.syncedLyrics)
          : null,
        provider: "lrclib",
      };
    return null;
  });
  const results = await Promise.all(requests);
  return results.find((result) => result != null) ?? null;
}

async function fetchGeniusLyrics(
  artist: string,
  title: string,
): Promise<LyricsResponse | null> {
  const token = env.geniusToken();
  if (!token) return null;
  const normArtist = artist.toLowerCase().replace(/[^a-z0-9]/g, "");
  const normTitle = title.toLowerCase().replace(/[^a-z0-9]/g, "");
  const primaryArtist = artist
    .split(/\s*(?:&|,|feat\.?|ft\.?|featuring|avec)\s*/i)[0]
    .trim();
  const queries = dedupeNonEmpty([
    `${primaryArtist} ${title}`,
    `${artist} ${title}`,
    title,
  ]);
  for (const q of queries) {
    const url = new URL("https://api.genius.com/search");
    url.searchParams.set("q", q);
    const payload = await safe(
      fetchJson<Record<string, unknown>>(
        url,
        { headers: { Authorization: `Bearer ${token}` } },
        6000,
      ),
      {},
    );
    const hits = asList(
      (payload as Record<string, Record<string, unknown>>).response
        ?.hits as Record<string, unknown>[],
    );
    const hit = hits.find((entry: Record<string, unknown>) => {
      const result = entry.result as Record<string, unknown> | undefined;
      const pa = String(
        (result?.primary_artist as Record<string, unknown>)?.name ?? "",
      )
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "");
      const ct = String(result?.title ?? "")
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "");
      return (
        ct.includes(normTitle) &&
        pa.includes(normArtist.toLowerCase().replace(/[^a-z0-9]/g, ""))
      );
    });
    if (!hit) continue;
    const pageUrl = (hit.result as Record<string, unknown>)?.url as
      | string
      | undefined;
    if (!pageUrl) continue;
    const html = await safe(fetchText(pageUrl, undefined, 8000), null);
    if (!html) continue;
    const match =
      html.match(/"lyricsData":\{"body":\{"html":"([^"]+)"/) ??
      html.match(/<div data-lyrics-container="true">([\s\S]*?)<\/div>/);
    if (!match?.[1]) continue;
    const plain = match[1]
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, "")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&#?\w+;/g, "")
      .trim();
    if (!plain) continue;
    return {
      artist,
      title,
      plain_lyrics: plain,
      synced_lyrics: null,
      provider: "genius",
    };
  }
  return null;
}

// ── YouTube search ────────────────────────────────────────────────────────────

type YoutubeCandidate = {
  title: string;
  artist: string;
  webpage_url?: string | null;
  thumbnail_url?: string | null;
  duration_ms?: number | null;
  source: string;
};

async function searchYoutubeTracks(
  query: string,
  limit = 5,
): Promise<TrackPayload[]> {
  const payload = await safe(
    fetchJson<{ query: string; results: YoutubeCandidate[] }>(
      `${env.resolverUrl()}/api/v1/search`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ query, limit }),
      },
      12000,
    ),
    null,
  );
  if (!payload?.results?.length) return [];
  return dedupeTracks(
    payload.results
      .map((c) => {
        const rawTitle = (c.title ?? "").trim();
        if (!rawTitle) return null;
        const segments = rawTitle
          .split(/\s+-\s+/)
          .map((s) => s.trim())
          .filter(Boolean);
        let artist = (c.artist ?? "").trim();
        let title = rawTitle;
        if (segments.length >= 2) {
          artist = segments[0];
          title = segments.slice(1).join(" - ");
        }
        if (!artist) artist = "YouTube";
        return makeTrackPayload({
          title,
          artist,
          artwork_url: c.thumbnail_url ?? null,
          duration_ms: c.duration_ms ?? null,
          provider: "youtube",
          external_id: c.webpage_url ?? null,
        });
      })
      .filter((t): t is TrackPayload => t !== null),
    limit,
  );
}

// ── Image asset management ────────────────────────────────────────────────────

function isManagedMediaUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  return url.startsWith("/api/v1/media/") || url.includes("/api/v1/media/");
}

async function attachManagedImageMap(
  ctx: ActionCtx,
  requests: Array<{
    entityType: string;
    entityKey: string;
    sourceUrl: string | null;
  }>,
): Promise<Map<string, string>> {
  const entries = new Map<
    string,
    { entityType: string; entityKey: string; sourceUrl: string }
  >();
  for (const req of requests) {
    const sourceUrl = req.sourceUrl?.trim();
    if (!req.entityKey || !sourceUrl) continue;
    const compound = `${req.entityType}:${req.entityKey}`;
    if (!entries.has(compound))
      entries.set(compound, {
        entityType: req.entityType,
        entityKey: req.entityKey,
        sourceUrl,
      });
  }
  if (entries.size === 0) return new Map();

  const values = [...entries.values()];
  const assets = await Promise.all(
    values.map((e) =>
      ctx.runQuery(api.imageAssets.getByLookupKey, {
        lookupKey: imageAssetLookupKey(e.entityType, e.entityKey),
      }),
    ),
  );
  const managed = new Map<string, string>();
  const toQueue: typeof values = [];

  for (let i = 0; i < values.length; i++) {
    const entry = values[i];
    const asset = assets[i];
    const compound = `${entry.entityType}:${entry.entityKey}`;
    if (isManagedMediaUrl(entry.sourceUrl)) {
      managed.set(compound, entry.sourceUrl);
      continue;
    }
    if (asset?.status === "ready" && asset.assetKey && asset.filePath) {
      managed.set(
        compound,
        `${env.publicBaseUrl()}/api/v1/media/image/${asset.assetKey}`,
      );
      continue;
    }
    managed.set(compound, entry.sourceUrl);
    const recentlyQueued =
      asset?.lastQueuedAt && Date.now() - asset.lastQueuedAt < 10 * 60 * 1000;
    if (!recentlyQueued || asset?.sourceUrl !== entry.sourceUrl)
      toQueue.push(entry);
  }

  await Promise.allSettled(
    toQueue.map((e) => {
      const lookupKey = imageAssetLookupKey(e.entityType, e.entityKey);
      return ctx.runMutation(api.imageAssets.enqueue, {
        lookupKey,
        assetKey: lookupKey,
        entityType: e.entityType,
        entityKey: e.entityKey,
        sourceUrl: e.sourceUrl,
      });
    }),
  );
  return managed;
}

async function attachManagedTrackVisuals(
  ctx: ActionCtx,
  tracks: TrackPayload[],
): Promise<TrackPayload[]> {
  const map = await attachManagedImageMap(
    ctx,
    tracks.map((t) => ({
      entityType: "track",
      entityKey: t.track_key,
      sourceUrl: t.artwork_url ?? t.artist_image_url ?? null,
    })),
  );
  return tracks.map((t) => {
    const managed = map.get(`track:${t.track_key}`);
    if (!managed || managed === t.artwork_url) return t;
    return { ...t, artwork_url: managed };
  });
}

async function attachManagedArtistImages(
  ctx: ActionCtx,
  artists: ArtistPayload[],
): Promise<ArtistPayload[]> {
  const map = await attachManagedImageMap(
    ctx,
    artists.map((a) => ({
      entityType: "artist",
      entityKey: a.artist_key,
      sourceUrl: a.image_url ?? null,
    })),
  );
  return artists.map((a) => {
    const managed = map.get(`artist:${a.artist_key}`);
    return managed ? { ...a, image_url: managed } : a;
  });
}

async function attachManagedAlbumArtwork(
  ctx: ActionCtx,
  albums: AlbumPayload[],
): Promise<AlbumPayload[]> {
  const map = await attachManagedImageMap(
    ctx,
    albums.map((a) => ({
      entityType: "album",
      entityKey: a.album_key,
      sourceUrl: a.artwork_url ?? null,
    })),
  );
  return albums.map((a) => {
    const managed = map.get(`album:${a.album_key}`);
    return managed ? { ...a, artwork_url: managed } : a;
  });
}

async function attachManagedPodcastArtwork(
  ctx: ActionCtx,
  podcasts: PodcastPayload[],
): Promise<PodcastPayload[]> {
  const map = await attachManagedImageMap(
    ctx,
    podcasts.map((p) => ({
      entityType: "podcast",
      entityKey: p.podcast_key,
      sourceUrl: p.artwork_url ?? null,
    })),
  );
  return podcasts.map((p) => {
    const managed = map.get(`podcast:${p.podcast_key}`);
    return managed ? { ...p, artwork_url: managed } : p;
  });
}

async function attachManagedBrowseArtwork(
  ctx: ActionCtx,
  categories: BrowseCategoryPayload[],
): Promise<BrowseCategoryPayload[]> {
  const map = await attachManagedImageMap(
    ctx,
    categories.map((c) => ({
      entityType: "browse",
      entityKey: c.category_id,
      sourceUrl: c.artwork_url ?? null,
    })),
  );
  return categories.map((c) => {
    const managed = map.get(`browse:${c.category_id}`);
    return managed ? { ...c, artwork_url: managed } : c;
  });
}

async function attachManagedEpisodeArtwork(
  ctx: ActionCtx,
  episodes: PodcastEpisodePayload[],
): Promise<PodcastEpisodePayload[]> {
  const map = await attachManagedImageMap(
    ctx,
    episodes.map((e) => ({
      entityType: "episode",
      entityKey: e.episode_key,
      sourceUrl: e.artwork_url ?? null,
    })),
  );
  return episodes.map((e) => {
    const managed = map.get(`episode:${e.episode_key}`);
    return managed ? { ...e, artwork_url: managed } : e;
  });
}

// ── Audio asset management ────────────────────────────────────────────────────

async function findReadyAudioAsset(
  ctx: ActionCtx,
  lookupKey: string,
): Promise<ResolvedStream | null> {
  const asset = await ctx.runQuery(api.audioAssets.getByLookupKey, {
    lookupKey,
  });
  if (!asset || asset.status !== "ready" || !asset.filePath) return null;
  const thumbnailUrl = await attachManagedImageMap(ctx, [
    {
      entityType: "track",
      entityKey: asset.trackKey,
      sourceUrl: asset.thumbnailUrl ?? null,
    },
  ]).then(
    (m) => m.get(`track:${asset.trackKey}`) ?? asset.thumbnailUrl ?? null,
  );
  return {
    stream_url: `${env.publicBaseUrl()}/api/v1/media/audio/${asset.assetKey}`,
    webpage_url: asset.sourceWebpageUrl ?? null,
    thumbnail_url: thumbnailUrl ?? null,
    title: asset.title,
    artist: asset.artist,
    duration_ms: asset.durationMs ?? null,
    source: asset.source,
  };
}

async function waitForReadyAudioAsset(
  ctx: ActionCtx,
  lookupKey: string,
  timeoutMs = 12_000,
): Promise<ResolvedStream | null> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ready = await findReadyAudioAsset(ctx, lookupKey);
    if (ready) return ready;

    const asset = await ctx.runQuery(api.audioAssets.getByLookupKey, {
      lookupKey,
    });
    if (asset?.status === "failed") return null;

    await new Promise((resolve) => setTimeout(resolve, 450));
  }
  return findReadyAudioAsset(ctx, lookupKey);
}

async function ensureAudioAssetQueued(
  ctx: ActionCtx,
  payload: { track?: TrackPayload; query?: string },
  query: string,
  cacheKey: string,
): Promise<void> {
  const lookupKey = audioAssetLookupKey(cacheKey);
  const existing = await ctx.runQuery(api.audioAssets.getByLookupKey, {
    lookupKey,
  });
  if (existing?.status === "ready" && existing.filePath) return;
  const recentlyQueued =
    existing?.lastQueuedAt &&
    Date.now() - existing.lastQueuedAt < 10 * 60 * 1000;
  if (
    recentlyQueued &&
    (existing?.status === "queued" || existing?.status === "processing")
  )
    return;
  const artist =
    payload.track?.artist ?? query.split(/\s+-\s+/, 2)[0] ?? "Unknown";
  const title = payload.track?.title ?? query.split(/\s+-\s+/, 2)[1] ?? query;
  const trackKey = payload.track?.track_key ?? buildTrackKey(artist, title);
  await ctx.runMutation(api.audioAssets.upsert, {
    lookupKey,
    trackKey,
    query,
    title,
    artist,
    assetKey: lookupKey,
    status: "queued",
    publicPath: `/api/v1/media/audio/${lookupKey}`,
    source: "youtube",
  });
}

// ── Hydratetrack visuals ──────────────────────────────────────────────────────

async function hydrateTrackVisuals(
  tracks: TrackPayload[],
  artistLookup: Map<string, ArtistPayload>,
  fallbackImageUrl: string | null,
  iTunesLimit: number,
): Promise<TrackPayload[]> {
  const needsVisual = tracks.filter(
    (t) => !t.artwork_url && !t.artist_image_url,
  );
  if (!needsVisual.length) return tracks;
  const itunesSubset = needsVisual.slice(0, iTunesLimit);
  const enrichedMap = new Map<string, TrackPayload>();
  await Promise.all(
    itunesSubset.map(async (track) => {
      const candidates = await safeTimed(
        () => searchTracksItunes(`${track.artist} ${track.title}`, 4),
        [],
        2500,
      );
      const match =
        candidates.find(
          (c) =>
            normalizeValue(c.artist) === normalizeValue(track.artist) &&
            normalizeValue(c.title) === normalizeValue(track.title),
        ) ?? candidates[0];
      if (match)
        enrichedMap.set(track.track_key, {
          ...track,
          artwork_url: match.artwork_url ?? track.artwork_url ?? null,
          artist_image_url:
            match.artist_image_url ?? track.artist_image_url ?? null,
        });
    }),
  );
  return tracks.map((t) => {
    if (enrichedMap.has(t.track_key)) return enrichedMap.get(t.track_key)!;
    const artistImage =
      artistLookup.get(buildArtistKey(t.artist))?.image_url ?? fallbackImageUrl;
    if (artistImage && !t.artwork_url && !t.artist_image_url)
      return { ...t, artist_image_url: artistImage };
    return t;
  });
}

// ── Search utilities ──────────────────────────────────────────────────────────

function artistMatchesQuery(query: string, artist: ArtistPayload): boolean {
  const nq = normalizeValue(query);
  const na = normalizeValue(artist.name);
  return (
    na.includes(nq) ||
    nq.includes(na) ||
    nq.split("-").some((part) => na.includes(part) && part.length > 2)
  );
}

function isLikelySyntheticCollaborationArtist(
  query: string,
  artist: ArtistPayload,
): boolean {
  if (!artist.name.includes(",")) return false;
  const queryTokens = normalizeValue(query)
    .split("-")
    .filter((part) => part.length > 2);
  if (queryTokens.length < 2) return false;
  const artistName = normalizeValue(artist.name);
  return queryTokens.filter((token) => artistName.includes(token)).length >= 2;
}

function artistQueryVariants(query: string): string[] {
  const base = query.trim();
  const noBrackets = base.replace(/\s*[\[(][^\])]*[\])]?/g, "").trim();
  return dedupeNonEmpty([base, noBrackets, base.split(/\s+/)[0]]);
}

function findBestArtistMatch(
  query: string,
  artists: ArtistPayload[],
): ArtistPayload | null {
  const nq = normalizeValue(query);
  return (
    artists.find((a) => normalizeValue(a.name) === nq) ??
    artists.find(
      (a) =>
        normalizeValue(a.name).startsWith(nq) ||
        nq.startsWith(normalizeValue(a.name)),
    ) ??
    null
  );
}

function backfillArtistImagesFromTracks(
  artists: ArtistPayload[],
  tracks: TrackPayload[],
): ArtistPayload[] {
  const trackImageMap = new Map<string, string>();
  for (const t of tracks)
    if (t.artist_image_url)
      trackImageMap.set(buildArtistKey(t.artist), t.artist_image_url);
  return artists.map((a) =>
    a.image_url
      ? a
      : { ...a, image_url: trackImageMap.get(a.artist_key) ?? null },
  );
}

function hasExplicitYoutubeMarkers(query: string): boolean {
  return /youtube\.com|youtu\.be|ytb/i.test(query);
}

function searchTokens(query: string): string[] {
  return normalizeValue(query)
    .split("-")
    .filter((token) => token.length > 2);
}

function trackContainsAllQueryTokens(query: string, track: TrackPayload): boolean {
  const tokens = searchTokens(query);
  if (tokens.length < 2) return true;
  const haystack = normalizeValue(
    [track.artist, track.title, track.album ?? ""].join(" "),
  );
  return tokens.every((token) => haystack.includes(token));
}

function shouldUseYoutubeSearchFallback(
  query: string,
  tracks: TrackPayload[],
  artists: ArtistPayload[],
): boolean {
  const needsSpecificTrack =
    searchTokens(query).length >= 2 &&
    !tracks.some((track) => trackContainsAllQueryTokens(query, track));
  return (
    hasExplicitYoutubeMarkers(query) ||
    (tracks.length === 0 && artists.length === 0) ||
    needsSpecificTrack
  );
}

async function enrichArtistImages(
  artists: ArtistPayload[],
): Promise<ArtistPayload[]> {
  return artists;
}

// ── Search impl ───────────────────────────────────────────────────────────────

async function searchImpl(
  ctx: ActionCtx,
  query: string,
  limit: number,
): Promise<SearchResponse> {
  const normalizedQuery = query.trim();
  if (!normalizedQuery)
    return { query: "", artists: [], tracks: [], albums: [], podcasts: [] };

  const artistQueries = artistQueryVariants(normalizedQuery);
  const compactQuery = normalizeValue(normalizedQuery).length < 3;
  const fastTimeoutMs = compactQuery ? 1400 : 3200;
  const slowTimeoutMs = compactQuery ? 900 : 2800;
  const [
    tracks,
    lastfmArtistBatches,
    itunesArtistBatches,
    musicbrainzArtists,
    albums,
    mbAlbums,
    podcasts,
  ] = await Promise.all([
    safeTimed(() => searchTracksItunes(normalizedQuery, limit), [], fastTimeoutMs),
    compactQuery
      ? Promise.resolve([] as ArtistPayload[][])
      : Promise.all(
          artistQueries.map((q) =>
            safeTimed(
              () => searchLastfmArtists(q, Math.min(limit, 5)),
              [],
              slowTimeoutMs,
            ),
          ),
        ),
    Promise.all(
      artistQueries.map((q) =>
        safeTimed(
          () => searchItunesArtists(q, Math.min(limit, 5)),
          [],
          fastTimeoutMs,
        ),
      ),
    ),
    compactQuery
      ? Promise.resolve([] as ArtistPayload[])
      : safeTimed(
          () => searchMusicBrainzArtists(normalizedQuery, Math.min(limit, 6)),
          [],
          slowTimeoutMs,
        ),
    compactQuery
      ? Promise.resolve([] as AlbumPayload[])
      : safeTimed(
          () => searchAlbums(normalizedQuery, Math.min(limit, 8)),
          [],
          fastTimeoutMs,
        ),
    compactQuery
      ? Promise.resolve([] as AlbumPayload[])
      : safeTimed(
          () => searchMusicBrainzAlbums(normalizedQuery, Math.min(limit, 8)),
          [],
          slowTimeoutMs,
        ),
    compactQuery
      ? Promise.resolve([] as PodcastPayload[])
      : safeTimed(
          () => searchPodcastsImpl(normalizedQuery, Math.min(limit, 6)),
          [],
          slowTimeoutMs,
        ),
  ]);

  let artists = dedupeArtists(
    [
      ...lastfmArtistBatches.flat(),
      ...itunesArtistBatches.flat(),
      ...musicbrainzArtists,
    ].filter(
      (a) =>
        artistMatchesQuery(normalizedQuery, a) &&
        !isLikelySyntheticCollaborationArtist(normalizedQuery, a),
    ),
    Math.min(limit, 6),
  );
  artists = await enrichArtistImages(artists);

  const bestArtist = findBestArtistMatch(normalizedQuery, artists);
  let resultTracks = dedupeTracks(tracks, limit);
  let resultAlbums = dedupeAlbums(
    [...mbAlbums, ...albums],
    Math.min(limit, 10),
  );

  if (
    bestArtist &&
    (resultTracks.length < Math.min(limit, 8) ||
      resultAlbums.length < Math.min(limit, 6))
  ) {
    const [artistTracks, musicbrainzA, itunesA] = await Promise.all([
      safeTimed(
        () => topTracksForArtist(bestArtist.name, Math.min(limit, 6)),
        [],
        3500,
      ),
      safeTimed(
        () => searchMusicBrainzAlbums(`${bestArtist.name}`, Math.min(limit, 6)),
        [],
        3000,
      ),
      safeTimed(
        () => albumsForArtist(bestArtist.name, Math.min(limit, 6)),
        [],
        3000,
      ),
    ]);
    resultTracks = dedupeTracks([...artistTracks, ...resultTracks], limit);
    const specific = dedupeAlbums(
      [...musicbrainzA, ...itunesA],
      Math.min(limit, 10),
    );
    if (specific.length > 0) resultAlbums = specific;
  }

  if (shouldUseYoutubeSearchFallback(normalizedQuery, resultTracks, artists)) {
    const ytTracks = await safeTimed(
      () => searchYoutubeTracks(normalizedQuery, Math.min(limit, 6)),
      [],
      4500,
    );
    if (ytTracks.length > 0)
      resultTracks = dedupeTracks([...ytTracks, ...resultTracks], limit);
  }

  const artistLookup = new Map(artists.map((a) => [a.artist_key, a]));
  resultTracks = await hydrateTrackVisuals(
    resultTracks,
    artistLookup,
    bestArtist?.image_url ?? null,
    Math.min(limit, 3),
  );
  artists = backfillArtistImagesFromTracks(artists, resultTracks);

  const [mArtists, mTracks, mAlbums, mPodcasts] = await Promise.all([
    attachManagedArtistImages(ctx, artists),
    attachManagedTrackVisuals(ctx, resultTracks),
    attachManagedAlbumArtwork(ctx, resultAlbums),
    attachManagedPodcastArtwork(ctx, podcasts),
  ]);

  void primeAudioAssetsImpl(ctx, mTracks, 3);
  return {
    query: normalizedQuery,
    artists: mArtists,
    tracks: mTracks,
    albums: mAlbums,
    podcasts: mPodcasts,
  };
}

// ── Prime audio assets (fire-and-forget) ─────────────────────────────────────

async function primeAudioAssetsImpl(
  ctx: ActionCtx,
  tracks: TrackPayload[],
  limit = 3,
): Promise<void> {
  const unique = dedupeTracks(tracks, limit).slice(0, limit);
  await Promise.allSettled(
    unique.map((track) => {
      const query = `${track.artist} - ${track.title}`;
      const cacheKey = resolvedStreamCacheKey({ track }, query);
      return ensureAudioAssetQueued(ctx, { track }, query, cacheKey);
    }),
  );
}

// ── Recommendations ───────────────────────────────────────────────────────────

async function recommendationsImpl(
  ctx: ActionCtx,
  userId: string,
): Promise<TrackPayload[]> {
  const [likedRows, historyRows] = await Promise.all([
    ctx.runQuery(api.savedTracks.list, { userId: userId as never }),
    ctx.runQuery(api.playbackEvents.history, {
      userId: userId as never,
      limit: 100,
    }),
  ]);

  const artistWeights = new Map<string, number>();
  for (const row of likedRows) {
    const track = row.trackPayload as TrackPayload;
    if (track.artist)
      artistWeights.set(
        track.artist,
        (artistWeights.get(track.artist) ?? 0) + 4,
      );
  }
  for (const row of historyRows) {
    const track = row.trackPayload as TrackPayload;
    if (!track.artist) continue;
    const delta =
      row.eventType === "track_completed"
        ? 3
        : row.eventType === "play_started"
          ? 1
          : row.eventType.startsWith("skip")
            ? -1
            : 0;
    artistWeights.set(
      track.artist,
      (artistWeights.get(track.artist) ?? 0) + delta,
    );
  }

  const excludedKeys = new Set([
    ...likedRows.map((r) => r.trackKey),
    ...historyRows.map((r) => r.trackKey),
  ]);
  const limit = 16;

  if (artistWeights.size === 0) {
    const editorial = await safe(
      searchTracksItunes("new music friday", limit),
      [],
    );
    return attachManagedTrackVisuals(
      ctx,
      editorial.filter((t) => !excludedKeys.has(t.track_key)).slice(0, limit),
    );
  }

  const seedTracks = [
    ...likedRows.slice(0, 2).map((r) => r.trackPayload as TrackPayload),
    ...historyRows
      .filter((r) => ["play_started", "track_completed"].includes(r.eventType))
      .slice(0, 2)
      .map((r) => r.trackPayload as TrackPayload),
  ];

  const trackMap = new Map<string, TrackPayload>();
  const similarBatches = await Promise.all(
    seedTracks.map((seed) =>
      safe(similarTracksLastfm(seed.artist, seed.title, 6), []),
    ),
  );
  for (const batch of similarBatches) {
    for (const t of batch) {
      if (!trackMap.has(t.track_key) && !excludedKeys.has(t.track_key))
        trackMap.set(t.track_key, t);
      if (trackMap.size >= limit)
        return attachManagedTrackVisuals(
          ctx,
          [...trackMap.values()].slice(0, limit),
        );
    }
  }

  const topArtists = [...artistWeights.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 2)
    .map(([a]) => a);
  const artistBatches = await Promise.all(
    topArtists.map((a) => safe(topTracksForArtist(a, 8), [])),
  );
  for (const batch of artistBatches) {
    for (const t of batch) {
      if (!trackMap.has(t.track_key) && !excludedKeys.has(t.track_key))
        trackMap.set(t.track_key, t);
      if (trackMap.size >= limit) break;
    }
  }

  return attachManagedTrackVisuals(ctx, [...trackMap.values()].slice(0, limit));
}

function bestTrackVisual(tracks: TrackPayload[]): string | null {
  for (const t of tracks) {
    if (t.artwork_url) return t.artwork_url;
    if (t.artist_image_url) return t.artist_image_url;
  }
  return null;
}

function countArtists(tracks: TrackPayload[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const t of tracks) m.set(t.artist, (m.get(t.artist) ?? 0) + 1);
  return m;
}

async function buildGeneratedPlaylists(
  ctx: ActionCtx,
  userId: string,
  recommendations: TrackPayload[],
): Promise<GeneratedPlaylistPayload[]> {
  const [likedRows, historyRows] = await Promise.all([
    ctx.runQuery(api.savedTracks.list, { userId: userId as never }),
    ctx.runQuery(api.playbackEvents.history, {
      userId: userId as never,
      limit: 40,
    }),
  ]);
  const likedTracks = likedRows.map((r) => r.trackPayload as TrackPayload);
  const historyTracks = historyRows.map((r) => r.trackPayload as TrackPayload);
  const playlists: GeneratedPlaylistPayload[] = [];

  if (recommendations.length > 0) {
    playlists.push({
      playlist_key: "discover-weekly",
      title: "Découvertes de la semaine",
      subtitle:
        "Une sélection fraîche construite autour de ce que tu écoutes déjà",
      artwork_url: bestTrackVisual(recommendations),
      tracks: recommendations.slice(0, 12),
    });
  }

  const rewind = dedupeTracks([
    ...historyTracks.slice(0, 6),
    ...likedTracks.slice(0, 6),
  ]).slice(0, 12);
  if (rewind.length > 0) {
    playlists.push({
      playlist_key: "on-repeat",
      title: "On Repeat",
      subtitle: "Les titres que tu rejoues le plus en ce moment",
      artwork_url: bestTrackVisual(rewind),
      tracks: rewind,
    });
  }

  const topArtists = [
    ...countArtists([...likedTracks, ...historyTracks]).entries(),
  ]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 2)
    .map(([a]) => a);
  for (const [i, artist] of topArtists.entries()) {
    let artistTracks = dedupeTracks([
      ...likedTracks.filter((t) => t.artist === artist),
      ...historyTracks.filter((t) => t.artist === artist),
      ...recommendations.filter((t) => t.artist === artist),
    ]).slice(0, 12);
    if (artistTracks.length < 8) {
      const fetched = await safe(topTracksForArtist(artist, 8), []);
      artistTracks = dedupeTracks([...artistTracks, ...fetched]).slice(0, 12);
    }
    if (artistTracks.length > 0) {
      playlists.push({
        playlist_key: `daily-mix-${i + 1}`,
        title: `Daily Mix ${i + 1}`,
        subtitle: `Un mix centré sur ${artist} et les artistes qui gravitent autour`,
        artwork_url: bestTrackVisual(artistTracks),
        tracks: artistTracks,
      });
    }
  }

  if (playlists.length === 0) {
    for (const [key, title, subtitle, query] of [
      [
        "daily-mix-1",
        "Daily Mix 1",
        "Une base polyvalente pour démarrer l'écoute",
        "pop hits",
      ],
      [
        "discover-weekly",
        "Découvertes de la semaine",
        "Des sorties et titres frais pour lancer ton profil",
        "new music friday",
      ],
      [
        "afro-mix",
        "Afro Mix",
        "Afrobeats, amapiano et chaleur immédiate",
        "afrobeats hits",
      ],
    ] as const) {
      const tracks = await safe(searchTracksItunes(query, 12), []);
      if (tracks.length > 0)
        playlists.push({
          playlist_key: key,
          title,
          subtitle,
          artwork_url: bestTrackVisual(tracks),
          tracks,
        });
    }
  }
  return playlists.slice(0, 5);
}

// ── Exported internalActions ──────────────────────────────────────────────────

export const search = internalAction({
  args: { query: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, args) =>
    withCache(
      ctx,
      `search:${args.query.toLowerCase().trim()}:${args.limit ?? 20}`,
      TTL.SEARCH,
      () => searchImpl(ctx, args.query, args.limit ?? 20),
    ),
});

export const artistDetails = internalAction({
  args: { name: v.string() },
  handler: async (ctx, args) =>
    withCache(
      ctx,
      `artist:${args.name.toLowerCase().trim()}`,
      TTL.ARTIST,
      async () => {
        const [info, topTracks, similarArtists, albums] = await Promise.all([
          safe(artistInfoLastfm(args.name), null),
          safe(topTracksForArtist(args.name, 10), []),
          safe(similarArtistsLastfm(args.name, 8), []),
          safe(albumsForArtist(args.name, 8), []),
        ]);
        const artist: ArtistPayload = info ?? {
          artist_key: buildArtistKey(args.name),
          name: args.name,
          image_url: null,
          provider: "unknown",
        };
        const [mArtist, mTopTracks, mSimilar, mAlbums] = await Promise.all([
          attachManagedArtistImages(ctx, [artist]).then((a) => a[0]),
          attachManagedTrackVisuals(ctx, topTracks),
          attachManagedArtistImages(ctx, similarArtists),
          attachManagedAlbumArtwork(ctx, albums),
        ]);
        return {
          artist: mArtist,
          top_tracks: mTopTracks,
          top_albums: mAlbums,
          similar_artists: mSimilar,
        };
      },
    ),
});

export const albumDetails = internalAction({
  args: {
    artist: v.string(),
    title: v.string(),
    external_id: v.optional(v.string()),
  },
  handler: async (ctx, args) =>
    withCache(
      ctx,
      `album:${args.artist.toLowerCase().trim()}:${args.title.toLowerCase().trim()}`,
      TTL.ALBUM,
      async () => {
        const [lf, it] = await Promise.all([
          safe(albumDetailsLastfm(args.artist, args.title), {
            album: null,
            tracks: [],
          }),
          safe(albumDetailsItunes(args.artist, args.title, args.external_id), {
            album: null,
            tracks: [],
          }),
        ]);
        const album = lf.album ??
          it.album ?? {
            album_key: buildAlbumKey(args.artist, args.title),
            title: args.title,
            artist: args.artist,
            provider: "unknown",
          };
        const tracks = dedupeTracks([...lf.tracks, ...it.tracks]);
        const [mAlbum, mTracks] = await Promise.all([
          attachManagedAlbumArtwork(ctx, [album]).then((a) => a[0]),
          attachManagedTrackVisuals(ctx, tracks),
        ]);
        return { album: mAlbum, tracks: mTracks };
      },
    ),
});

export const browseCategories = internalAction({
  args: {},
  handler: async (ctx) =>
    withCache(ctx, "browse:categories", TTL.BROWSE, () =>
      attachManagedBrowseArtwork(ctx, BROWSE_CATEGORIES),
    ),
});

export const browseCategory = internalAction({
  args: { categoryId: v.string() },
  handler: async (ctx, args) =>
    withCache(
      ctx,
      `browse:cat:${args.categoryId}`,
      TTL.BROWSE_CAT,
      async () => {
        const category = BROWSE_CATEGORIES.find(
          (c) => c.category_id === args.categoryId,
        );
        if (!category) throw new Error("NOT_FOUND");
        const result = await searchImpl(ctx, category.search_seed, 20);
        const [mCategory] = await attachManagedBrowseArtwork(ctx, [category]);
        return {
          category: mCategory,
          tracks: result.tracks.slice(0, 12),
          artists: result.artists.slice(0, 6),
          albums: result.albums.slice(0, 6),
          podcasts: result.podcasts.slice(0, 4),
        };
      },
    ),
});

export const searchPodcasts = internalAction({
  args: { query: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, args) =>
    withCache(
      ctx,
      `podcasts:search:${args.query.toLowerCase().trim()}:${args.limit ?? 12}`,
      TTL.PODCASTS_SEARCH,
      async () => {
        const pods = await searchPodcastsImpl(args.query, args.limit ?? 12);
        return attachManagedPodcastArtwork(ctx, pods);
      },
    ),
});

export const podcastDetails = internalAction({
  args: { podcastKey: v.string() },
  handler: async (ctx, args) =>
    withCache(ctx, `podcast:${args.podcastKey}`, TTL.PODCAST, async () => {
      const keyParts = args.podcastKey.split("-");
      const searchQuery = keyParts.slice(1).join(" ") || keyParts[0];
      const items = await safe(itunesPodcastSearch(searchQuery, 10), []);
      const item =
        items.find(
          (i) => mapItunesPodcast(i)?.podcast_key === args.podcastKey,
        ) ?? items[0];
      if (!item) throw new Error("NOT_FOUND");
      const podcast = mapItunesPodcast(item);
      if (!podcast) throw new Error("NOT_FOUND");

      let episodes: PodcastEpisodePayload[] = [];
      if (item.feedUrl) {
        const xml = await safe(
          fetchText(String(item.feedUrl), undefined, 10000),
          null,
        );
        if (xml) {
          const podTitle = String(item.collectionName ?? "");
          const podArtwork = upscaleArtwork(
            (item.artworkUrl600 as string) ?? (item.artworkUrl100 as string),
          );
          episodes = parseRssItems(xml)
            .map((e) => ({
              ...e,
              podcast_title: podTitle,
              artwork_url: e.artwork_url ?? podArtwork,
              episode_key: buildEpisodeKey(args.podcastKey, e.title),
              publisher: podcast.publisher,
            }))
            .slice(0, 50);
          episodes = await attachManagedEpisodeArtwork(ctx, episodes);
        }
      }
      const [mPodcast] = await attachManagedPodcastArtwork(ctx, [podcast]);
      return { podcast: mPodcast, episodes };
    }),
});

export const trackArtwork = internalAction({
  args: { artist: v.string(), title: v.string() },
  handler: async (ctx, args) =>
    withCache(
      ctx,
      `artwork:${args.artist.toLowerCase().trim()}:${args.title.toLowerCase().trim()}`,
      TTL.ARTWORK,
      async () => {
        const tracks = await safe(
          searchTracksItunes(`${args.artist} ${args.title}`, 5),
          [],
        );
        const match =
          tracks.find(
            (t) => normalizeValue(t.title) === normalizeValue(args.title),
          ) ?? tracks[0];
        return { artwork_url: match?.artwork_url ?? null };
      },
    ),
});

export const lyrics = internalAction({
  args: { artist: v.string(), title: v.string() },
  handler: async (ctx, args) =>
    withSuccessCache(
      ctx,
      `lyrics:v3:${args.artist.toLowerCase().trim()}:${args.title.toLowerCase().trim()}`,
      TTL.LYRICS,
      async () => {
        const [lrclib, genius] = await Promise.all([
          safe(fetchLrclibLyrics(args.artist, args.title), null),
          safe(fetchGeniusLyrics(args.artist, args.title), null),
        ]);
        return lrclib ?? genius ?? null;
      },
    ),
});

export const resolveTrack = internalAction({
  args: {
    track: v.optional(v.any()),
    query: v.optional(v.string()),
    artist: v.optional(v.string()),
    title: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const query = args.track
      ? `${(args.track as TrackPayload).artist} - ${(args.track as TrackPayload).title}`
      : args.artist && args.title
        ? `${args.artist} - ${args.title}`
        : (args.query ?? "").trim();
    if (!query) throw new Error("MISSING_QUERY");

    const cacheKey = resolvedStreamCacheKey(
      { track: args.track as TrackPayload | undefined, query: args.query },
      query,
    );
    const lookupKey = audioAssetLookupKey(cacheKey);
    const ready = await findReadyAudioAsset(ctx, lookupKey);
    if (ready) return ready;

    await ensureAudioAssetQueued(
      ctx,
      { track: args.track as TrackPayload | undefined, query: args.query },
      query,
      cacheKey,
    );

    const prepared = await waitForReadyAudioAsset(ctx, lookupKey);
    if (prepared) return prepared;

    const cached = await ctx.runQuery(api.cache.get, {
      key: `resolved:${cacheKey}`,
    });
    if (cached && Date.now() - (cached.cachedAt as number) < 18 * 60_000) {
      const cachedValue = JSON.parse(cached.value as string) as ResolvedStream;
      if (isManagedMediaUrl(cachedValue.stream_url)) {
        return cachedValue;
      }
    }

    const response = await fetchJson<ResolvedStream>(
      `${env.resolverUrl()}/api/v1/resolve`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ query }),
      },
      env.resolverTimeoutMs(),
    );
    if (isManagedMediaUrl(response.stream_url)) {
      void ctx.runMutation(api.cache.set, {
        key: `resolved:${cacheKey}`,
        value: JSON.stringify(response),
        cachedAt: Date.now(),
      });
    }
    return response;
  },
});

export const similarTracks = internalAction({
  args: {
    track: v.any(),
    exclude_track_keys: v.optional(v.array(v.string())),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const track = args.track as TrackPayload;
    const excludeKeys = new Set(args.exclude_track_keys ?? []);
    const limit = args.limit ?? 12;
    const raw = await withCache(
      ctx,
      `similar_raw:${track.track_key}`,
      TTL.SIMILAR,
      () =>
        safe(
          similarTracksLastfm(track.artist, track.title, limit + 20),
          [] as TrackPayload[],
        ),
    );
    const filtered = dedupeTracks(
      raw.filter((t) => !excludeKeys.has(t.track_key)),
      limit,
    );
    return attachManagedTrackVisuals(ctx, filtered);
  },
});

export const home = internalAction({
  args: { userId: v.string() },
  handler: async (ctx, args) => {
    // Fresh from DB (fast Convex reads, always up-to-date)
    const [likedRows, historyRows] = await Promise.all([
      ctx.runQuery(api.savedTracks.list, { userId: args.userId as never }),
      ctx.runQuery(api.playbackEvents.history, {
        userId: args.userId as never,
        limit: 20,
      }),
    ]);

    const likedTracks = likedRows
      .slice(0, 12)
      .map((r) => r.trackPayload as TrackPayload);
    const recentMap = new Map<string, TrackPayload>();
    for (const r of historyRows)
      if (!recentMap.has(r.trackKey))
        recentMap.set(r.trackKey, r.trackPayload as TrackPayload);
    const recentlyPlayed = [...recentMap.values()].slice(0, 12);

    // Heavy external-API parts — cached 10 min
    const heavy = await withCache(
      ctx,
      `home_heavy:${args.userId}`,
      TTL.HOME_HEAVY,
      async () => {
        const [recs, cats, pods] = await Promise.all([
          safeTimed(
            () => recommendationsImpl(ctx, args.userId),
            [] as TrackPayload[],
            4000,
          ),
          safeTimed(
            () => attachManagedBrowseArtwork(ctx, BROWSE_CATEGORIES),
            BROWSE_CATEGORIES as BrowseCategoryPayload[],
            3000,
          ),
          safeTimed(
            async () => {
              const p = await searchPodcastsImpl("podcast musique", 6);
              return attachManagedPodcastArtwork(ctx, p);
            },
            [] as PodcastPayload[],
            2000,
          ),
        ]);
        const playlists = await safeTimed(
          () => buildGeneratedPlaylists(ctx, args.userId, recs),
          [] as GeneratedPlaylistPayload[],
          3000,
        );
        return {
          recommendations: recs,
          browse_categories: cats,
          featured_podcasts: pods,
          generated_playlists: playlists,
        };
      },
    );

    const [mRecent, mLiked, mRecs] = await Promise.all([
      safeTimed(
        () => attachManagedTrackVisuals(ctx, recentlyPlayed),
        recentlyPlayed,
        1200,
      ),
      safeTimed(
        () => attachManagedTrackVisuals(ctx, likedTracks),
        likedTracks,
        800,
      ),
      safeTimed(
        () => attachManagedTrackVisuals(ctx, heavy.recommendations),
        heavy.recommendations,
        1200,
      ),
    ]);

    void primeAudioAssetsImpl(
      ctx,
      [...mRecs.slice(0, 4), ...mRecent.slice(0, 2)],
      6,
    );

    return {
      recently_played: mRecent,
      liked_tracks: mLiked,
      recommendations: mRecs,
      generated_playlists: heavy.generated_playlists,
      browse_categories: heavy.browse_categories,
      featured_podcasts: heavy.featured_podcasts,
    } as HomeResponse;
  },
});

export const recommendations = internalAction({
  args: { userId: v.string() },
  handler: async (ctx, args) =>
    withCache(ctx, `recs:${args.userId}`, TTL.RECOMMENDATIONS, () =>
      recommendationsImpl(ctx, args.userId),
    ),
});

export const primeAudioAssets = internalAction({
  args: { tracks: v.array(v.any()), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    await primeAudioAssetsImpl(
      ctx,
      args.tracks as TrackPayload[],
      args.limit ?? 3,
    );
  },
});

export const buildFeaturedPodcasts = internalAction({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const pods = await searchPodcastsImpl("podcast musique", args.limit ?? 6);
    return attachManagedPodcastArtwork(ctx, pods);
  },
});
