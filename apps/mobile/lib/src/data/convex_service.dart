import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

import '../models/app_models.dart';

/// Couche d'accès à Convex — remplace les appels Dio pour les données utilisateur.
/// Les appels de contenu (search, stream, home) restent dans ApiService.
class ConvexService {
  ConvexService._();

  static ConvexService? _instance;
  static ConvexService get instance {
    _instance ??= ConvexService._();
    return _instance!;
  }

  ConvexClient get _client => ConvexClient.instance;

  // ─── Helpers ─────────────────────────────────────────────────────────────

  dynamic _decode(String json) => jsonDecode(json);

  List<dynamic> _decodeList(String json) {
    final decoded = jsonDecode(json);
    if (decoded is List) return decoded;
    return [];
  }

  // ─── Auth / Users ─────────────────────────────────────────────────────────

  /// Upsert d'un utilisateur depuis son ID NestJS. Retourne le Convex _id.
  Future<String> upsertUser({
    required String externalId,
    required String name,
    required String email,
  }) async {
    final result = await _client.mutation(
      name: 'auth:upsertByExternalId',
      args: {'externalId': externalId, 'name': name, 'email': email},
    );
    // Convex retourne l'_id entre guillemets
    return _decode(result) as String;
  }

  // ─── Playlists ────────────────────────────────────────────────────────────

  Future<List<Playlist>> listPlaylists(String convexUserId) async {
    final result = await _client.query('playlists:list', {
      'userId': convexUserId,
    });
    final list = _decodeList(result);
    return list
        .map((json) => _playlistFromConvex(json as Map<String, dynamic>))
        .toList();
  }

  Future<String> createPlaylist({
    required String convexUserId,
    required String name,
    String description = '',
    String? artworkUrl,
  }) async {
    final result = await _client.mutation(
      name: 'playlists:create',
      args: {
        'userId': convexUserId,
        'name': name,
        'description': description,
        'artworkUrl': ?artworkUrl,
      },
    );
    return _decode(result) as String;
  }

  Future<Playlist> createPlaylistAndReturn({
    required String convexUserId,
    required String name,
    String description = '',
  }) async {
    final id = await createPlaylist(
      convexUserId: convexUserId,
      name: name,
      description: description,
    );
    // Retourne un Playlist minimal immédiatement, la lib se rafraîchira
    return Playlist(id: id, name: name, description: description, tracks: []);
  }

  Future<void> updatePlaylist({
    required String convexUserId,
    required String playlistId,
    String? name,
    String? description,
    String? artworkUrl,
  }) async {
    await _client.mutation(
      name: 'playlists:update',
      args: {
        'playlistId': playlistId,
        'userId': convexUserId,
        'name': ?name,
        'description': ?description,
        'artworkUrl': ?artworkUrl,
      },
    );
  }

  Future<void> deletePlaylist({
    required String convexUserId,
    required String playlistId,
  }) async {
    await _client.mutation(
      name: 'playlists:remove',
      args: {'playlistId': playlistId, 'userId': convexUserId},
    );
  }

  Future<void> addTrackToPlaylist({
    required String convexUserId,
    required String playlistId,
    required Track track,
  }) async {
    await _client.mutation(
      name: 'playlists:addTrack',
      args: {
        'playlistId': playlistId,
        'userId': convexUserId,
        'trackKey': track.trackKey,
        'trackPayload': track.toJson(),
      },
    );
  }

  Future<void> removeTrackFromPlaylist({
    required String convexUserId,
    required String playlistId,
    required String trackKey,
  }) async {
    await _client.mutation(
      name: 'playlists:removeTrack',
      args: {
        'playlistId': playlistId,
        'userId': convexUserId,
        'trackKey': trackKey,
      },
    );
  }

  // ─── Saved Tracks (likes) ─────────────────────────────────────────────────

  Future<List<Track>> listSavedTracks(String convexUserId) async {
    final result = await _client.query('savedTracks:list', {
      'userId': convexUserId,
    });
    final list = _decodeList(result);
    return list
        .map(
          (item) => Track.fromJson(
            (item as Map<String, dynamic>)['trackPayload']
                as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> saveTrack({
    required String convexUserId,
    required Track track,
  }) async {
    await _client.mutation(
      name: 'savedTracks:save',
      args: {
        'userId': convexUserId,
        'trackKey': track.trackKey,
        'trackPayload': track.toJson(),
      },
    );
  }

  Future<void> unsaveTrack({
    required String convexUserId,
    required String trackKey,
  }) async {
    await _client.mutation(
      name: 'savedTracks:unsave',
      args: {'userId': convexUserId, 'trackKey': trackKey},
    );
  }

  // ─── Playback State (temps réel cross-device) ─────────────────────────────

  Future<void> syncPlaybackState({
    required String convexUserId,
    required Track track,
    required bool isPlaying,
    required int positionMs,
    String? deviceId,
  }) async {
    await _client.mutation(
      name: 'playbackState:sync',
      args: {
        'userId': convexUserId,
        'trackKey': track.trackKey,
        'trackPayload': track.toJson(),
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'deviceId': ?deviceId,
      },
    );
  }

  Future<void> setPlayingState({
    required String convexUserId,
    required bool isPlaying,
    required int positionMs,
  }) async {
    await _client.mutation(
      name: 'playbackState:setPlaying',
      args: {
        'userId': convexUserId,
        'isPlaying': isPlaying,
        'positionMs': positionMs,
      },
    );
  }

  /// Stream temps réel de l'état de lecture — tous les devices du même user
  Stream<RemotePlaybackState?> watchPlaybackState(String convexUserId) {
    final controller = StreamController<RemotePlaybackState?>.broadcast();
    // BUG #11 fix: use a Completer so that onCancel always waits for setup()
    // to complete before cancelling the handle, preventing a race where
    // onCancel fires with handle == null while setup() is still in flight.
    final setupCompleter = Completer<SubscriptionHandle?>();

    // Run setup asynchronously; on failure close the controller to avoid a
    // leaked open stream (which would be a memory leak).
    () async {
      try {
        final handle = await _client.subscribe(
          name: 'playbackState:get',
          args: {'userId': convexUserId},
          onUpdate: (json) {
            final data = _decode(json);
            if (data == null) {
              controller.add(null);
            } else {
              controller.add(
                RemotePlaybackState.fromJson(data as Map<String, dynamic>),
              );
            }
          },
          onError: (msg, _) => controller.addError(msg),
        );
        setupCompleter.complete(handle);
      } catch (error, stack) {
        // BUG #11 fix: setup failed — signal the Completer and close the
        // controller so the caller's StreamSubscription terminates cleanly.
        setupCompleter.complete(null);
        if (!controller.isClosed) {
          controller.addError(error, stack);
          await controller.close();
        }
      }
    }();

    controller.onCancel = () async {
      // BUG #13 fix: await setup completion before cancelling so we never
      // lose the handle reference due to a timing race.
      final handle = await setupCompleter.future;
      handle?.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };
    return controller.stream;
  }

  // ─── Playback Events ──────────────────────────────────────────────────────

  Future<void> recordPlaybackEvent({
    required String convexUserId,
    required Track track,
    required String eventType,
    required int listenedMs,
    required double completionRatio,
  }) async {
    await _client.mutation(
      name: 'playbackEvents:record',
      args: {
        'userId': convexUserId,
        'trackKey': track.trackKey,
        'eventType': eventType,
        'listenedMs': listenedMs,
        'completionRatio': completionRatio,
        'trackPayload': track.toJson(),
      },
    );
  }

  // ─── Podcasts ─────────────────────────────────────────────────────────────

  Future<List<Podcast>> listSavedPodcastShows(String convexUserId) async {
    final result = await _client.query('podcasts:listShows', {
      'userId': convexUserId,
    });
    final list = _decodeList(result);
    return list
        .map(
          (item) => Podcast.fromJson(
            (item as Map<String, dynamic>)['podcastPayload']
                as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> savePodcastShow({
    required String convexUserId,
    required Podcast podcast,
  }) async {
    await _client.mutation(
      name: 'podcasts:saveShow',
      args: {
        'userId': convexUserId,
        'podcastKey': podcast.podcastKey,
        'podcastPayload': podcast.toJson(),
      },
    );
  }

  Future<void> unsavePodcastShow({
    required String convexUserId,
    required String podcastKey,
  }) async {
    await _client.mutation(
      name: 'podcasts:unsaveShow',
      args: {'userId': convexUserId, 'podcastKey': podcastKey},
    );
  }

  // ─── Helpers de conversion ────────────────────────────────────────────────

  static Playlist _playlistFromConvex(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    final tracks = rawTracks.map((t) {
      final track = t as Map<String, dynamic>;
      return PlaylistTrackItem(
        id: track['_id'] as String,
        position: (track['position'] as num).toInt(),
        track: Track.fromJson(track['trackPayload'] as Map<String, dynamic>),
      );
    }).toList()..sort((a, b) => a.position.compareTo(b.position));

    return Playlist(
      id: json['_id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      artworkUrl: json['artworkUrl'] as String?,
      tracks: tracks,
    );
  }
}

/// État de lecture distant (Convex) — pour la sync cross-device.
class RemotePlaybackState {
  const RemotePlaybackState({
    required this.userId,
    required this.trackKey,
    required this.trackPayload,
    required this.isPlaying,
    required this.positionMs,
    this.deviceId,
    required this.updatedAt,
  });

  final String userId;
  final String trackKey;
  final Map<String, dynamic> trackPayload;
  final bool isPlaying;
  final int positionMs;
  final String? deviceId;
  final int updatedAt;

  Track get track => Track.fromJson(trackPayload);

  factory RemotePlaybackState.fromJson(Map<String, dynamic> json) =>
      RemotePlaybackState(
        userId: json['userId'] as String,
        trackKey: json['trackKey'] as String,
        trackPayload: json['trackPayload'] as Map<String, dynamic>,
        isPlaying: json['isPlaying'] as bool,
        positionMs: (json['positionMs'] as num).toInt(),
        deviceId: json['deviceId'] as String?,
        updatedAt: (json['updatedAt'] as num).toInt(),
      );
}
