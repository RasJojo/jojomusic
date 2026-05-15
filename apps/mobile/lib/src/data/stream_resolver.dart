import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/app_models.dart';

class LocalStreamResolver {
  LocalStreamResolver({
    @visibleForTesting Future<ResolvedStream> Function(Track)? backendOverride,
  }) : _yt = YoutubeExplode(),
       _backendOverride = backendOverride;

  final YoutubeExplode _yt;
  final Future<ResolvedStream> Function(Track)? _backendOverride;
  final Map<String, _CachedStream> _cache = {};
  final Map<String, Future<ResolvedStream>> _inFlight = {};

  static final _videoIdRe = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  static const _cacheDuration = Duration(hours: 5, minutes: 30);

  Future<ResolvedStream> resolve(Track track) async {
    final cached = _cache[track.trackKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.stream;
    }

    final inFlight = _inFlight[track.trackKey];
    if (inFlight != null) return inFlight;

    final future = _backendOverride != null
        ? _backendOverride(track)
        : _doResolve(track);
    _inFlight[track.trackKey] = future;
    try {
      final result = await future;
      _cache[track.trackKey] = _CachedStream(
        stream: result,
        expiresAt: DateTime.now().add(_cacheDuration),
      );
      return result;
    } finally {
      _inFlight.remove(track.trackKey);
    }
  }

  Future<ResolvedStream> _doResolve(Track track) async {
    final videoId = _extractVideoId(track) ?? await _searchVideoId(track);
    if (videoId == null) {
      throw Exception('Aucun identifiant vidéo trouvé pour : ${track.artist} — ${track.title}');
    }

    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient.getManifest(videoId);
    } catch (e) {
      throw Exception('Flux introuvable pour $videoId : $e');
    }

    // mp4/aac en priorité — opus/webm rejeté par AVPlayer iOS
    final mp4Streams = manifest.audioOnly
        .where((s) => s.container.name == 'mp4')
        .toList()
      ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

    final String streamUrl;
    if (mp4Streams.isNotEmpty) {
      streamUrl = mp4Streams.first.url.toString();
    } else if (manifest.audioOnly.isNotEmpty) {
      streamUrl = manifest.audioOnly.withHighestBitrate().url.toString();
    } else if (manifest.muxed.isNotEmpty) {
      streamUrl = manifest.muxed.sortByVideoQuality().last.url.toString();
    } else {
      throw Exception('Aucun flux audio disponible pour $videoId');
    }

    // Pas de second appel réseau — on utilise les métadonnées déjà disponibles
    return ResolvedStream(
      streamUrl: streamUrl,
      title: track.title,
      artist: track.artist,
      source: 'youtube',
      webpageUrl: 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: track.artworkUrl,
      durationMs: track.durationMs,
    );
  }

  String? _extractVideoId(Track track) {
    final externalId = track.externalId;
    if (externalId != null && _videoIdRe.hasMatch(externalId)) {
      return externalId;
    }
    if (_videoIdRe.hasMatch(track.trackKey)) {
      return track.trackKey;
    }
    return null;
  }

  Future<String?> _searchVideoId(Track track) async {
    try {
      final query = '${track.artist} ${track.title}';
      final results = await _yt.search.search(query);
      if (results.isNotEmpty) {
        return results.first.id.value;
      }
    } catch (_) {}
    return null;
  }

  void evict(String trackKey) {
    _cache.remove(trackKey);
  }

  void dispose() => _yt.close();
}

class _CachedStream {
  const _CachedStream({required this.stream, required this.expiresAt});

  final ResolvedStream stream;
  final DateTime expiresAt;
}
