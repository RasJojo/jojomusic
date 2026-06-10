/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as audioAssets from "../audioAssets.js";
import type * as auth from "../auth.js";
import type * as authNode from "../authNode.js";
import type * as cache from "../cache.js";
import type * as http from "../http.js";
import type * as imageAssets from "../imageAssets.js";
import type * as jojoflix from "../jojoflix.js";
import type * as migration from "../migration.js";
import type * as musicContent from "../musicContent.js";
import type * as playbackEvents from "../playbackEvents.js";
import type * as playbackState from "../playbackState.js";
import type * as playlists from "../playlists.js";
import type * as podcasts from "../podcasts.js";
import type * as savedTracks from "../savedTracks.js";
import type * as spotify from "../spotify.js";
import type * as spotifyNode from "../spotifyNode.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  audioAssets: typeof audioAssets;
  auth: typeof auth;
  authNode: typeof authNode;
  cache: typeof cache;
  http: typeof http;
  imageAssets: typeof imageAssets;
  jojoflix: typeof jojoflix;
  migration: typeof migration;
  musicContent: typeof musicContent;
  playbackEvents: typeof playbackEvents;
  playbackState: typeof playbackState;
  playlists: typeof playlists;
  podcasts: typeof podcasts;
  savedTracks: typeof savedTracks;
  spotify: typeof spotify;
  spotifyNode: typeof spotifyNode;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
