import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import '../data/stream_resolver.dart';
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
  ref.onDispose(controller.dispose);
  return controller;
});

class DownloadsController {
  DownloadsController(this.ref) : _localResolver = LocalStreamResolver();

  final Ref ref;
  final LocalStreamResolver _localResolver;
  bool _disposed = false;
  bool _syncInProgress = false;
  static const _downloadRetryCount = 2;
  static const _betweenTrackDelay = Duration(milliseconds: 850);
  static const _failedTrackCooldown = Duration(hours: 2);

  void dispose() {
    _disposed = true;
    _localResolver.dispose();
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
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      await _syncOfflineTracksInternal(desiredTracks);
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _syncOfflineTracksInternal(
    Map<String, Track> desiredTracks,
  ) async {
    final database = ref.read(appDatabaseProvider);
    final existingTracks = await database.getOfflineTracks();
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/downloads');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    for (final entry in desiredTracks.entries) {
      final track = entry.value;
      final existing = await database.findOfflineTrack(track.trackKey);
      final filePath =
          existing?.filePath ?? '${directory.path}/${track.trackKey}.m4a';
      final file = File(filePath);

      if (existing != null && await file.exists()) {
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

      // Skip recently failed tracks to avoid hammering a source that keeps failing.
      if (existing != null && existing.status == 'failed') {
        final sinceFailure = DateTime.now().difference(existing.updatedAt);
        if (sinceFailure < _failedTrackCooldown) {
          continue;
        }
      }

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

  /// Resolves the best stream URL for a track: backend first, YouTube fallback.
  Future<String> _resolveStreamUrl(Track track) async {
    try {
      final api = ref.read(apiProvider);
      final resolved = await api
          .resolveTrack(track)
          .timeout(const Duration(seconds: 10));
      final url = resolved.streamUrl.trim();
      if (url.isNotEmpty && resolved.source != 'preview') {
        return url;
      }
    } catch (_) {}
    // Backend unavailable or returned a preview — fall back to YouTube.
    final resolved = await _localResolver
        .resolve(track)
        .timeout(const Duration(seconds: 40));
    return resolved.streamUrl;
  }

  Future<void> _downloadTrack({
    required Track track,
    required String outputPath,
  }) async {
    if (_disposed) return;
    try {
      await File(outputPath).delete();
    } catch (_) {}

    final database = ref.read(appDatabaseProvider);
    final trackCreatedAt = DateTime.now();

    await database.upsertOfflineTrack(
      OfflineTracksCompanion.insert(
        trackKey: track.trackKey,
        title: track.title,
        artist: track.artist,
        album: Value(track.album),
        artworkUrl: Value(track.displayArtworkUrl),
        filePath: outputPath,
        status: 'resolving',
        progress: const Value(0),
        createdAt: trackCreatedAt,
        updatedAt: DateTime.now(),
      ),
    );

    try {
      final streamUrl = await _resolveStreamUrl(track);
      if (_disposed) return;

      await database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: track.trackKey,
          title: track.title,
          artist: track.artist,
          album: Value(track.album),
          artworkUrl: Value(track.displayArtworkUrl),
          filePath: outputPath,
          status: 'downloading',
          progress: const Value(0),
          createdAt: trackCreatedAt,
          updatedAt: DateTime.now(),
        ),
      );

      final filename = '${track.trackKey}.m4a';
      final task = DownloadTask(
        taskId: 'dl_${track.trackKey}',
        url: streamUrl,
        filename: filename,
        directory: 'downloads',
        baseDirectory: BaseDirectory.applicationDocuments,
        updates: Updates.statusAndProgress,
        retries: 0,
        allowPause: true,
      );

      final result = await FileDownloader().download(
        task,
        onProgress: (progress) async {
          if (_disposed) return;
          await database.upsertOfflineTrack(
            OfflineTracksCompanion.insert(
              trackKey: track.trackKey,
              title: track.title,
              artist: track.artist,
              album: Value(track.album),
              artworkUrl: Value(track.displayArtworkUrl),
              filePath: outputPath,
              status: 'downloading',
              progress: Value(progress.clamp(0.0, 1.0)),
              createdAt: trackCreatedAt,
              updatedAt: DateTime.now(),
            ),
          );
        },
      );

      if (_disposed) return;

      if (result.status != TaskStatus.complete) {
        throw Exception('Download ended with status: ${result.status}');
      }

      await database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: track.trackKey,
          title: track.title,
          artist: track.artist,
          album: Value(track.album),
          artworkUrl: Value(track.displayArtworkUrl),
          filePath: outputPath,
          status: 'downloaded',
          progress: const Value(1),
          createdAt: trackCreatedAt,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      if (_disposed) return;
      try {
        final partial = File(outputPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      if (_disposed) return;
      await database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: track.trackKey,
          title: track.title,
          artist: track.artist,
          album: Value(track.album),
          artworkUrl: Value(track.displayArtworkUrl),
          filePath: outputPath,
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
        await Future<void>.delayed(Duration(seconds: attempt * 3));
      }
    }
  }
}
