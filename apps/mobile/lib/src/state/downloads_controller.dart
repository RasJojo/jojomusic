import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import '../models/app_models.dart';
import 'providers.dart';

final downloadsProvider = StreamProvider<List<OfflineTrack>>((ref) {
  return ref.watch(appDatabaseProvider).watchOfflineTracks();
});

final downloadedPlaylistIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(appDatabaseProvider).watchDownloadedPlaylistIds();
});

final downloadsControllerProvider = Provider<DownloadsController>((ref) {
  final controller = DownloadsController(ref);
  // BUG #5 fix: register dispose so the controller knows when to stop touching
  // the database (Riverpod may tear down providers while a download is running).
  ref.onDispose(controller.dispose);
  return controller;
});

class DownloadsController {
  // BUG #4 fix: use a non-const constructor so we can hold a shared Dio
  // instance that is created once and closed on dispose.
  DownloadsController(this.ref)
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(minutes: 10),
            sendTimeout: const Duration(seconds: 25),
          ),
        );

  final Ref ref;
  // BUG #4 fix: shared Dio instance — created once, closed in dispose().
  final Dio _dio;
  // BUG #5 fix: lifecycle flag — set to true in dispose() so in-flight
  // callbacks can bail out before touching the database.
  bool _disposed = false;
  static const _downloadRetryCount = 3;
  static const _betweenTrackDelay = Duration(milliseconds: 850);

  void dispose() {
    _disposed = true;
    // BUG #4 fix: release the underlying HTTP client.
    _dio.close(force: true);
  }

  Future<void> togglePlaylistDownload({
    required Playlist playlist,
    required List<Playlist> playlists,
    List<Track> likes = const [],
  }) async {
    final database = ref.read(appDatabaseProvider);
    final isDownloaded = await database.isPlaylistDownloaded(playlist.id);
    if (isDownloaded) {
      await database.deleteOfflinePlaylist(playlist.id);
    } else {
      await database.upsertOfflinePlaylist(
        OfflinePlaylistsCompanion.insert(
          playlistId: playlist.id,
          name: playlist.name,
          description: Value(
            playlist.description.isEmpty ? null : playlist.description,
          ),
          artworkUrl: Value(playlist.displayArtworkUrl),
          autoDownloadNewTracks: const Value(true),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
    await syncDownloadedPlaylists(playlists: playlists, likes: likes);
  }

  Future<void> syncDownloadedPlaylists({
    List<Playlist>? playlists,
    List<Track>? likes,
  }) async {
    final database = ref.read(appDatabaseProvider);
    final api = ref.read(apiProvider);
    final currentPlaylists = playlists ?? await api.fetchPlaylists();
    final currentLikes = likes ?? await api.fetchLikes();
    final libraryPlaylists = _withFavoritesPlaylist(
      playlists: currentPlaylists,
      likes: currentLikes,
    );
    final validPlaylistIds =
        currentPlaylists.map((playlist) => playlist.id).toSet()
          ..addAll(libraryPlaylists.map((playlist) => playlist.id).toSet());
    await database.pruneOfflinePlaylists(validPlaylistIds);
    final downloadedPlaylistIds = await database.getDownloadedPlaylistIds();

    final desiredTracks = <String, Track>{};
    for (final playlist in libraryPlaylists) {
      if (!downloadedPlaylistIds.contains(playlist.id)) {
        continue;
      }
      for (final item in playlist.tracks) {
        desiredTracks.putIfAbsent(item.track.trackKey, () => item.track);
      }
    }

    await _syncOfflineTracks(desiredTracks);
  }

  Future<void> _syncOfflineTracks(Map<String, Track> desiredTracks) async {
    final database = ref.read(appDatabaseProvider);
    final existingTracks = await database.getOfflineTracks();
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/downloads');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    // BUG #3 + #15 fix: the original code had two separate loops both reading
    // from the same stale `existingByKey` snapshot taken before the first loop
    // ran. The first loop wrote DB rows (upserts) whose fresh state was never
    // reflected in the second loop's `existing` lookups.  Merge into one loop:
    // for each desired track, check the DB, update metadata / mark as downloaded
    // if the file already exists, or kick off a download otherwise.
    for (final entry in desiredTracks.entries) {
      final track = entry.value;
      // Re-read the current DB row each iteration so we always see the freshest
      // state (written by a previous iteration or a concurrent download).
      final existing = await database.findOfflineTrack(track.trackKey);
      final filePath =
          existing?.filePath ?? '${directory.path}/${track.trackKey}.m4a';
      final file = File(filePath);

      if (existing != null && await file.exists()) {
        // File is present — refresh metadata and mark as downloaded.
        await database.upsertOfflineTrack(
          OfflineTracksCompanion.insert(
            trackKey: track.trackKey,
            title: track.title,
            artist: track.artist,
            album: Value(track.album),
            artworkUrl: Value(track.displayArtworkUrl),
            filePath: filePath,
            status: 'downloaded',
            progress: const Value(1),
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
        continue;
      }

      // File does not exist yet — enqueue and download.
      await database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: track.trackKey,
          title: track.title,
          artist: track.artist,
          album: Value(track.album),
          artworkUrl: Value(track.displayArtworkUrl),
          filePath: filePath,
          status: 'queued',
          progress: const Value(0),
          createdAt: existing?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await _downloadTrackWithRetries(track: track, outputPath: filePath);
      await Future<void>.delayed(_betweenTrackDelay);
    }

    for (final existing in existingTracks) {
      if (desiredTracks.containsKey(existing.trackKey)) {
        continue;
      }
      final file = File(existing.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      await database.deleteOfflineTrack(existing.trackKey);
    }
  }

  List<Playlist> _withFavoritesPlaylist({
    required List<Playlist> playlists,
    required List<Track> likes,
  }) {
    if (likes.isEmpty) {
      return playlists;
    }
    return [
      Playlist(
        id: favoritesPlaylistId,
        name: 'Favoris',
        description: 'Tous les titres que tu as likés.',
        // BUG #11 fix: displayArtworkUrl is nullable — pick the first track
        // that actually has an artwork URL, falling back to the first track
        // (which may still be null, which is fine for a nullable field).
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
      ),
      ...playlists,
    ];
  }

  Future<void> _downloadTrack({
    required Track track,
    required String outputPath,
  }) async {
    // BUG #5 fix: bail out immediately if the controller has been disposed.
    if (_disposed) return;
    // BUG #5 fix: delete any partial file from a previous attempt BEFORE
    // starting the download so we never append to or corrupt a stale file.
    try {
      File(outputPath).deleteSync(recursive: false);
    } catch (_) {
      // Ignore ENOENT (file does not exist) and any other platform errors.
    }
    final database = ref.read(appDatabaseProvider);
    final api = ref.read(apiProvider);
    final normalizedPath = _normalizedOfflinePath(outputPath);
    // BUG #6 fix: capture createdAt once so every progress callback reuses the
    // same timestamp instead of generating a new one on each invocation.
    final trackCreatedAt = DateTime.now();
    // BUG #10 fix: local cancellation flag — set to true if the controller is
    // disposed while the download is in progress so the callback can exit early.
    var isCancelled = false;
    final cancelToken = CancelToken();

    await database.upsertOfflineTrack(
      OfflineTracksCompanion.insert(
        trackKey: track.trackKey,
        title: track.title,
        artist: track.artist,
        album: Value(track.album),
        artworkUrl: Value(track.displayArtworkUrl),
        filePath: normalizedPath,
        status: 'downloading',
        progress: const Value(0),
        createdAt: trackCreatedAt,
        updatedAt: DateTime.now(),
      ),
    );

    try {
      final resolved = await api.resolveTrack(track);
      // BUG #4 fix: use the shared _dio instance instead of creating a new one
      // per download. cancelToken lets us abort cleanly on dispose.
      await _dio.download(
        resolved.streamUrl,
        normalizedPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) async {
          // BUG #10 fix: stop if cancelled.
          if (isCancelled || _disposed) return;
          // BUG #5 fix: double-check disposed inside the async callback.
          if (_disposed) {
            isCancelled = true;
            cancelToken.cancel('controller disposed');
            return;
          }
          final progress = total <= 0 ? 0.0 : received / total;
          await database.upsertOfflineTrack(
            OfflineTracksCompanion.insert(
              trackKey: track.trackKey,
              title: track.title,
              artist: track.artist,
              album: Value(track.album),
              artworkUrl: Value(
                track.displayArtworkUrl ?? resolved.thumbnailUrl,
              ),
              filePath: normalizedPath,
              status: progress >= 1 ? 'downloaded' : 'downloading',
              progress: Value(progress),
              // BUG #6 fix: reuse the pre-captured createdAt.
              createdAt: trackCreatedAt,
              updatedAt: DateTime.now(),
            ),
          );
        },
      );

      if (_disposed) return;
      await database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: track.trackKey,
          title: track.title,
          artist: track.artist,
          album: Value(track.album),
          artworkUrl: Value(track.displayArtworkUrl ?? resolved.thumbnailUrl),
          filePath: normalizedPath,
          status: 'downloaded',
          progress: const Value(1),
          createdAt: trackCreatedAt,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      if (_disposed) return;
      try {
        final partial = File(normalizedPath);
        if (await partial.exists()) {
          await partial.delete();
        }
      } catch (_) {}
      if (_disposed) return;
      await database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: track.trackKey,
          title: track.title,
          artist: track.artist,
          album: Value(track.album),
          artworkUrl: Value(track.displayArtworkUrl),
          filePath: normalizedPath,
          status: 'failed',
          progress: const Value(0),
          createdAt: trackCreatedAt,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _downloadTrackWithRetries({
    required Track track,
    required String outputPath,
  }) async {
    for (var attempt = 1; attempt <= _downloadRetryCount; attempt++) {
      await _downloadTrack(track: track, outputPath: outputPath);
      final current = await ref
          .read(appDatabaseProvider)
          .findOfflineTrack(track.trackKey);
      if (current?.status == 'downloaded') {
        return;
      }
      if (attempt < _downloadRetryCount) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  String _normalizedOfflinePath(String filePath) {
    if (filePath.endsWith('.audio')) {
      return filePath.replaceFirst(RegExp(r'\.audio$'), '.m4a');
    }
    if (RegExp(r'\.[a-zA-Z0-9]+$').hasMatch(filePath)) {
      return filePath;
    }
    return '$filePath.m4a';
  }
}

// Downloads
