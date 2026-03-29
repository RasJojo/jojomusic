import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'downloads_controller.dart';
import 'home_controller.dart';
import 'providers.dart';

class LibraryState {
  const LibraryState({required this.likes, required this.playlists});

  final List<Track> likes;
  final List<Playlist> playlists;

  Playlist? get favoritesPlaylist {
    if (likes.isEmpty) {
      return null;
    }
    return Playlist(
      id: favoritesPlaylistId,
      name: 'Favoris',
      description: 'Tous les titres que tu as likés.',
      artworkUrl: likes.first.displayArtworkUrl,
      tracks: likes.asMap().entries
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

const _libraryCacheKey = 'jojomusic.library.cache';
const _libraryFetchTimeout = Duration(seconds: 8);

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryState>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<LibraryState> {
  @override
  Future<LibraryState> build() async {
    final cached = await _restoreCachedLibrary();
    if (cached != null) {
      unawaited(_refreshInBackground());
      return cached;
    }
    try {
      final next = await _fetchLibrary().timeout(_libraryFetchTimeout);
      await _persistLibrary(next);
      _scheduleOfflineSync(next.playlists, next.likes);
      return next;
    } on DioException catch (error) {
      if (_canUseOfflineCache(error) && cached != null) {
        return cached;
      }
      rethrow;
    } on TimeoutException {
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    final fallback = state.asData?.value ?? await _restoreCachedLibrary();
    if (fallback == null) {
      state = const AsyncLoading();
    }
    try {
      final next = await _fetchLibrary().timeout(_libraryFetchTimeout);
      await _persistLibrary(next);
      _scheduleOfflineSync(next.playlists, next.likes);
      state = AsyncData(next);
    } on DioException catch (error, stackTrace) {
      if (_canUseOfflineCache(error) && fallback != null) {
        state = AsyncData(fallback);
        return;
      }
      state = AsyncError(error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      if (fallback != null) {
        state = AsyncData(fallback);
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> toggleLike(Track track) async {
    final current = state.asData?.value;
    if (current == null) {
      return refresh();
    }

    final api = ref.read(apiProvider);
    final liked = current.likes.any((item) => item.trackKey == track.trackKey);
    if (liked) {
      await api.unlikeTrack(track.trackKey);
    } else {
      await api.likeTrack(track);
    }
    await refresh();
    ref.invalidate(homeControllerProvider);
  }

  Future<Playlist> createPlaylist({
    required String name,
    String description = '',
  }) async {
    final playlist = await ref
        .read(apiProvider)
        .createPlaylist(name: name, description: description);
    await refresh();
    return playlist;
  }

  Future<Playlist> createPlaylistWithTrack({
    required String name,
    required Track track,
    String description = '',
  }) async {
    final playlist = await ref
        .read(apiProvider)
        .createPlaylist(name: name, description: description);
    await ref
        .read(apiProvider)
        .addTrackToPlaylist(playlistId: playlist.id, track: track);
    await refresh();
    return playlist;
  }

  Future<void> addToPlaylist({
    required String playlistId,
    required Track track,
  }) async {
    await ref
        .read(apiProvider)
        .addTrackToPlaylist(playlistId: playlistId, track: track);
    await refresh();
  }

  Future<void> removeFromPlaylist({
    required String playlistId,
    required String trackKey,
  }) async {
    await ref
        .read(apiProvider)
        .removeTrackFromPlaylist(playlistId: playlistId, trackKey: trackKey);
    await refresh();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await ref.read(apiProvider).deletePlaylist(playlistId);
    await refresh();
  }

  Future<LibraryState> _fetchLibrary() async {
    final api = ref.read(apiProvider);
    final likes = await api.fetchLikes();
    final playlists = await api.fetchPlaylists();
    return LibraryState(likes: likes, playlists: playlists);
  }

  Future<void> _persistLibrary(LibraryState library) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _libraryCacheKey,
          jsonEncode({
            'likes': library.likes.map((track) => track.toJson()).toList(),
            'playlists': library.playlists
                .map(
                  (playlist) => {
                    'id': playlist.id,
                    'name': playlist.name,
                    'description': playlist.description,
                    'artwork_url': playlist.artworkUrl,
                    'tracks': playlist.tracks
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
          }),
        );
  }

  Future<LibraryState?> _restoreCachedLibrary() async {
    final encoded = ref
        .read(sharedPreferencesProvider)
        .getString(_libraryCacheKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final likes = (json['likes'] as List<dynamic>? ?? [])
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
      final playlists = (json['playlists'] as List<dynamic>? ?? [])
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();
      return LibraryState(likes: likes, playlists: playlists);
    } catch (_) {
      return null;
    }
  }

  bool _canUseOfflineCache(DioException error) {
    final statusCode = error.response?.statusCode;
    return statusCode == null;
  }

  Future<void> _refreshInBackground() async {
    try {
      final next = await _fetchLibrary().timeout(_libraryFetchTimeout);
      await _persistLibrary(next);
      _scheduleOfflineSync(next.playlists, next.likes);
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(next);
    } on DioException catch (_) {
      return;
    } on TimeoutException {
      return;
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
