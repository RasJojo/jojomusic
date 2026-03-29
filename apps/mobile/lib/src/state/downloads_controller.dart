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
  return DownloadsController(ref);
});

class DownloadsController {
  const DownloadsController(this.ref);

  final Ref ref;

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
    final validPlaylistIds = currentPlaylists
        .map((playlist) => playlist.id)
        .toSet()
      ..addAll(
        libraryPlaylists
        .map((playlist) => playlist.id)
        .toSet(),
      );
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

    final existingByKey = {
      for (final track in existingTracks) track.trackKey: track,
    };

    for (final entry in desiredTracks.entries) {
      final track = entry.value;
      final existing = existingByKey[track.trackKey];
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
    }

    for (final entry in desiredTracks.entries) {
      final track = entry.value;
      final existing = existingByKey[track.trackKey];
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

      await _downloadTrack(track: track, outputPath: filePath);
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
      ),
      ...playlists,
    ];
  }

  Future<void> _downloadTrack({
    required Track track,
    required String outputPath,
  }) async {
    final database = ref.read(appDatabaseProvider);
    final api = ref.read(apiProvider);
    final normalizedPath = _normalizedOfflinePath(outputPath);

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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    try {
      final resolved = await api.resolveTrack(track);
      await Dio().download(
        resolved.streamUrl,
        normalizedPath,
        onReceiveProgress: (received, total) async {
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
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        },
      );

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
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
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
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      rethrow;
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
