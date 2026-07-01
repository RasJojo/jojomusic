import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/convex_service.dart';
import '../models/app_models.dart';
import 'downloads_controller.dart';
import 'home_controller.dart';
import 'providers.dart';
import 'session_controller.dart';

class LibraryState {
  const LibraryState({
    required this.likes,
    required this.playlists,
    required this.followedPodcasts,
    this.savedAlbums = const [],
  });

  final List<Track> likes;
  final List<Playlist> playlists;
  final List<Podcast> followedPodcasts;
  final List<Album> savedAlbums;

  bool isLiked(Track track) =>
      likes.any((item) => item.trackKey == track.trackKey);

  bool isAlbumSaved(String albumKey) =>
      savedAlbums.any((a) => a.albumKey == albumKey);

  Set<String> playlistIdsForTrack(Track track) => {
    for (final playlist in playlists)
      if (playlist.tracks.any((item) => item.track.trackKey == track.trackKey))
        playlist.id,
  };

  bool isInPlaylist(String playlistId, Track track) =>
      playlistIdsForTrack(track).contains(playlistId);

  bool isPodcastFollowed(Podcast podcast) =>
      followedPodcasts.any((item) => item.podcastKey == podcast.podcastKey);

  Playlist? get favoritesPlaylist {
    if (likes.isEmpty) return null;
    return Playlist(
      id: favoritesPlaylistId,
      name: 'Favoris',
      description: 'Tous les titres que tu as likés.',
      // BUG #12 fix: likes.first may have a null displayArtworkUrl; find the
      // first track that actually has one, falling back to likes.first (which
      // may still be null — that is fine since artworkUrl is nullable).
      artworkUrl: likes
          .firstWhere(
            (t) => t.displayArtworkUrl != null,
            orElse: () => likes.first,
          )
          .displayArtworkUrl,
      tracks: likes
          .asMap()
          .entries
          .map(
            (entry) => PlaylistTrackItem(
              id: 'favorite:${entry.value.trackKey}',
              position: entry.key,
              track: entry.value,
            ),
          )
          .toList(growable: false),
    );
  }
}

const _libraryCacheKeyPrefix = 'jojomusic.library.cache';
const _savedAlbumsKey = 'jojomusic.saved_albums';
const _libraryFetchTimeout = Duration(seconds: 8);

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<LibraryState> {
  String get _libraryCacheKey {
    final userId =
        ref.read(sessionControllerProvider).asData?.value?.user.id ?? 'anon';
    return '$_libraryCacheKeyPrefix.$userId';
  }

  String? get _convexUserId =>
      ref.read(sessionControllerProvider).asData?.value?.convexUserId;

  ConvexService get _convex => ref.read(convexServiceProvider);

  @override
  Future<LibraryState> build() async {
    // Wait for the session to resolve before reading the cache.
    // SessionController.build() has no network calls, so this completes on
    // the next microtask — but without this await, _libraryCacheKey() gets
    // called while the session is still AsyncLoading and falls back to the
    // 'anon' key, causing a cache miss every time the app starts offline.
    await ref
        .read(sessionControllerProvider.future)
        .timeout(const Duration(seconds: 1), onTimeout: () => null);

    // Listen to session changes so the library refreshes when the session
    // becomes available or changes (e.g. after background token validation).
    // Use user.id rather than convexUserId so this fires even when Convex
    // hasn't been resolved yet.
    ref.listen(sessionControllerProvider, (previous, next) {
      final prevUserId = previous?.asData?.value?.user.id;
      final nextUserId = next.asData?.value?.user.id;
      if (nextUserId != null && nextUserId != prevUserId) {
        unawaited(_refreshInBackground());
      }
    });
    final cached = await _restoreCachedLibrary();
    if (cached != null) {
      unawaited(_refreshInBackground());
      return cached;
    }
    final next = await _fetchLibrary();
    await _persistLibrary(next);
    _scheduleOfflineSync(next.playlists, next.likes);
    return next;
  }

  Future<void> refresh() async {
    final fallback = state.asData?.value ?? await _restoreCachedLibrary();
    if (fallback == null) state = const AsyncLoading();
    try {
      final next = await _fetchLibrary();
      await _persistLibrary(next);
      _scheduleOfflineSync(next.playlists, next.likes);
      state = AsyncData(next);
    } catch (error, stackTrace) {
      if (fallback != null) {
        state = AsyncData(fallback);
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> toggleLike(Track track) async {
    final current = state.asData?.value;
    if (current == null) return refresh();

    final convexId = _convexUserId;
    final liked = current.likes.any((item) => item.trackKey == track.trackKey);

    if (convexId != null) {
      if (liked) {
        await _convex.unsaveTrack(
          convexUserId: convexId,
          trackKey: track.trackKey,
        );
      } else {
        await _convex.saveTrack(convexUserId: convexId, track: track);
      }
    } else {
      // Fallback NestJS si pas encore de Convex user
      final api = ref.read(apiProvider);
      if (liked) {
        await api.unlikeTrack(track.trackKey);
      } else {
        await api.likeTrack(track);
      }
    }
    await refresh();
    ref.invalidate(homeControllerProvider);
  }

  Future<Playlist> createPlaylist({
    required String name,
    String description = '',
  }) async {
    final convexId = _convexUserId;
    late Playlist playlist;
    if (convexId != null) {
      playlist = await _convex.createPlaylistAndReturn(
        convexUserId: convexId,
        name: name,
        description: description,
      );
    } else {
      playlist = await ref
          .read(apiProvider)
          .createPlaylist(name: name, description: description);
    }
    await refresh();
    return playlist;
  }

  Future<Playlist> createPlaylistWithTrack({
    required String name,
    required Track track,
    String description = '',
  }) async {
    final playlist = await createPlaylist(name: name, description: description);
    await addToPlaylist(playlistId: playlist.id, track: track);
    return playlist;
  }

  Future<Playlist> renamePlaylist({
    required String playlistId,
    required String name,
    String? description,
  }) async {
    final convexId = _convexUserId;
    if (convexId != null) {
      await _convex.updatePlaylist(
        convexUserId: convexId,
        playlistId: playlistId,
        name: name,
        description: description,
      );
    } else {
      await ref
          .read(apiProvider)
          .updatePlaylist(
            playlistId: playlistId,
            name: name,
            description: description,
          );
    }
    await refresh();
    // state.asData can be null if refresh() transitions through AsyncLoading;
    // fall back to a minimal Playlist rather than crashing with ! on null.
    return state.asData?.value.playlists.firstWhere(
          (p) => p.id == playlistId,
          orElse: () => Playlist(
            id: playlistId,
            name: name,
            description: description ?? '',
            tracks: [],
          ),
        ) ??
        Playlist(
          id: playlistId,
          name: name,
          description: description ?? '',
          tracks: [],
        );
  }

  Future<void> addToPlaylist({
    required String playlistId,
    required Track track,
  }) async {
    final convexId = _convexUserId;
    if (convexId != null) {
      await _convex.addTrackToPlaylist(
        convexUserId: convexId,
        playlistId: playlistId,
        track: track,
      );
    } else {
      await ref
          .read(apiProvider)
          .addTrackToPlaylist(playlistId: playlistId, track: track);
    }
    await refresh();
  }

  Future<void> toggleTrackInPlaylist({
    required Playlist playlist,
    required Track track,
  }) async {
    if (playlist.tracks.any((item) => item.track.trackKey == track.trackKey)) {
      await removeFromPlaylist(
        playlistId: playlist.id,
        trackKey: track.trackKey,
      );
      return;
    }
    await addToPlaylist(playlistId: playlist.id, track: track);
  }

  Future<void> removeFromPlaylist({
    required String playlistId,
    required String trackKey,
  }) async {
    final convexId = _convexUserId;
    if (convexId != null) {
      await _convex.removeTrackFromPlaylist(
        convexUserId: convexId,
        playlistId: playlistId,
        trackKey: trackKey,
      );
    } else {
      await ref
          .read(apiProvider)
          .removeTrackFromPlaylist(playlistId: playlistId, trackKey: trackKey);
    }
    await refresh();
  }

  Future<void> deletePlaylist(String playlistId) async {
    final convexId = _convexUserId;
    if (convexId != null) {
      await _convex.deletePlaylist(
        convexUserId: convexId,
        playlistId: playlistId,
      );
    } else {
      await ref.read(apiProvider).deletePlaylist(playlistId);
    }
    await refresh();
  }

  Future<void> followPodcast(Podcast podcast) async {
    final convexId = _convexUserId;
    if (convexId != null) {
      await _convex.savePodcastShow(convexUserId: convexId, podcast: podcast);
    } else {
      await ref.read(apiProvider).followPodcast(podcast);
    }
    await refresh();
  }

  Future<void> unfollowPodcast(String podcastKey) async {
    final convexId = _convexUserId;
    if (convexId != null) {
      await _convex.unsavePodcastShow(
        convexUserId: convexId,
        podcastKey: podcastKey,
      );
    } else {
      await ref.read(apiProvider).unfollowPodcast(podcastKey);
    }
    await refresh();
  }

  Future<void> togglePodcastFollow(Podcast podcast) async {
    if (state.asData?.value.isPodcastFollowed(podcast) ?? false) {
      await unfollowPodcast(podcast.podcastKey);
      return;
    }
    await followPodcast(podcast);
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<LibraryState> _fetchLibrary() async {
    final convexId = _convexUserId;
    final savedAlbums = await _loadSavedAlbums();

    if (convexId != null) {
      try {
        final results = await Future.wait([
          _convex
              .listSavedTracks(convexId)
              .timeout(_libraryFetchTimeout)
              .catchError((_) => <Track>[]),
          _convex
              .listPlaylists(convexId)
              .timeout(_libraryFetchTimeout)
              .catchError((_) => <Playlist>[]),
          _convex
              .listSavedPodcastShows(convexId)
              .timeout(_libraryFetchTimeout)
              .catchError((_) => <Podcast>[]),
        ], eagerError: false);
        final likes = results[0] as List<Track>;
        final playlists = results[1] as List<Playlist>;
        final podcasts = results[2] as List<Podcast>;
        // If Convex returned nothing at all, the data hasn't been migrated yet.
        // Fall back to the NestJS HTTP API which holds the source of truth.
        if (likes.isEmpty && playlists.isEmpty && podcasts.isEmpty) {
          return _fetchLibraryFromHttp(savedAlbums);
        }
        return LibraryState(
          likes: likes,
          playlists: playlists,
          followedPodcasts: podcasts,
          savedAlbums: savedAlbums,
        );
      } catch (_) {
        return _fetchLibraryFromHttp(savedAlbums);
      }
    }

    return _fetchLibraryFromHttp(savedAlbums);
  }

  Future<LibraryState> _fetchLibraryFromHttp(List<Album> savedAlbums) async {
    final api = ref.read(apiProvider);
    // BUG #7 fix: same defensive pattern as the Convex path — individual
    // failures degrade gracefully instead of discarding all fetched data.
    final results = await Future.wait([
      api
          .fetchLikes()
          .timeout(_libraryFetchTimeout)
          .catchError((_) => <Track>[]),
      api
          .fetchPlaylists()
          .timeout(_libraryFetchTimeout)
          .catchError((_) => <Playlist>[]),
      api
          .fetchFollowedPodcasts()
          .timeout(_libraryFetchTimeout)
          .catchError((_) => <Podcast>[]),
    ], eagerError: false);
    return LibraryState(
      likes: results[0] as List<Track>,
      playlists: results[1] as List<Playlist>,
      followedPodcasts: results[2] as List<Podcast>,
      savedAlbums: savedAlbums,
    );
  }

  // ── Saved albums (local only) ─────────────────────────────────────────────

  Future<List<Album>> _loadSavedAlbums() async {
    final encoded = ref
        .read(sharedPreferencesProvider)
        .getString(_savedAlbumsKey);
    if (encoded == null || encoded.isEmpty) return [];
    try {
      final list = jsonDecode(encoded) as List<dynamic>;
      return list
          .map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistSavedAlbums(List<Album> albums) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _savedAlbumsKey,
          jsonEncode(albums.map((a) => a.toJson()).toList()),
        );
  }

  Future<void> toggleSaveAlbum(Album album) async {
    final current = state.asData?.value;
    if (current == null) return;
    final saved = List<Album>.from(current.savedAlbums);
    final idx = saved.indexWhere((a) => a.albumKey == album.albumKey);
    if (idx >= 0) {
      saved.removeAt(idx);
    } else {
      saved.insert(0, album);
    }
    await _persistSavedAlbums(saved);
    state = AsyncData(
      LibraryState(
        likes: current.likes,
        playlists: current.playlists,
        followedPodcasts: current.followedPodcasts,
        savedAlbums: saved,
      ),
    );
  }

  // ── Cache SharedPreferences ───────────────────────────────────────────────

  Future<void> _persistLibrary(LibraryState library) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _libraryCacheKey,
          jsonEncode({
            'likes': library.likes.map((t) => t.toJson()).toList(),
            'playlists': library.playlists
                .map(
                  (p) => {
                    'id': p.id,
                    'name': p.name,
                    'description': p.description,
                    'artwork_url': p.artworkUrl,
                    'tracks': p.tracks
                        .map(
                          (item) => {
                            'id': item.id,
                            'position': item.position,
                            'track_payload': item.track.toJson(),
                          },
                        )
                        .toList(),
                  },
                )
                .toList(),
            'followed_podcasts': library.followedPodcasts
                .map(
                  (pod) => {
                    'podcast_key': pod.podcastKey,
                    'title': pod.title,
                    'publisher': pod.publisher,
                    'description': pod.description,
                    'artwork_url': pod.artworkUrl,
                    'feed_url': pod.feedUrl,
                    'external_url': pod.externalUrl,
                    'episode_count': pod.episodeCount,
                    'release_date': pod.releaseDate?.toIso8601String(),
                  },
                )
                .toList(),
          }),
        );
  }

  Future<LibraryState?> _restoreCachedLibrary() async {
    final encoded = ref
        .read(sharedPreferencesProvider)
        .getString(_libraryCacheKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final likes = (json['likes'] as List<dynamic>? ?? [])
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
      final playlists = (json['playlists'] as List<dynamic>? ?? [])
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();
      final followedPodcasts =
          (json['followed_podcasts'] as List<dynamic>? ?? [])
              .map((item) => Podcast.fromJson(item as Map<String, dynamic>))
              .toList();
      final savedAlbums = await _loadSavedAlbums();
      return LibraryState(
        likes: likes,
        playlists: playlists,
        followedPodcasts: followedPodcasts,
        savedAlbums: savedAlbums,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final next = await _fetchLibrary();
      // Guard: _fetchLibraryFromHttp() uses catchError on every call, so when
      // offline all three return [] without throwing. Don't overwrite populated
      // cached state with that empty result — it would wipe the library display.
      final current = state.asData?.value;
      final fetchedIsEmpty =
          next.likes.isEmpty &&
          next.playlists.isEmpty &&
          next.followedPodcasts.isEmpty;
      final cacheHasData =
          current != null &&
          (current.likes.isNotEmpty ||
              current.playlists.isNotEmpty ||
              current.followedPodcasts.isNotEmpty);
      if (fetchedIsEmpty && cacheHasData) return;

      await _persistLibrary(next);
      _scheduleOfflineSync(next.playlists, next.likes);
      if (!ref.mounted) return;
      state = AsyncData(next);
      return;
    } catch (_) {}

    // Network failed. Try the cache with the now-resolved session key.
    // This covers the race where session loads after the initial build()
    // ran with the 'anon' cache key and found nothing.
    if (!ref.mounted) return;
    if (state is AsyncData) return; // already showing data, don't overwrite
    final cached = await _restoreCachedLibrary();
    if (cached != null && ref.mounted) {
      state = AsyncData(cached);
    }
  }

  void _scheduleOfflineSync(List<Playlist> playlists, List<Track> likes) {
    unawaited(
      ref
          .read(downloadsControllerProvider)
          .syncDownloadedPlaylists(playlists: playlists, likes: likes),
    );
  }
}
