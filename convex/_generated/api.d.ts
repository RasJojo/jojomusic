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
import type * as imageAssets from "../imageAssets.js";
import type * as playbackEvents from "../playbackEvents.js";
import type * as playbackState from "../playbackState.js";
import type * as playlists from "../playlists.js";
import type * as podcasts from "../podcasts.js";
import type * as savedTracks from "../savedTracks.js";
import type * as spotify from "../spotify.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  audioAssets: typeof audioAssets;
  auth: typeof auth;
  imageAssets: typeof imageAssets;
  playbackEvents: typeof playbackEvents;
  playbackState: typeof playbackState;
  playlists: typeof playlists;
  podcasts: typeof podcasts;
  savedTracks: typeof savedTracks;
  spotify: typeof spotify;
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
