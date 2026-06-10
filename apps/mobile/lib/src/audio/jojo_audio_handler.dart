import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:just_audio/just_audio.dart' as ja;

import '../config/app_environment.dart';
import '../data/api_service.dart';
import '../data/app_database.dart';
import '../data/artwork_cache.dart';
import '../data/convex_service.dart';
import '../data/lrclib_service.dart';
import '../data/sponsorblock_service.dart';
import '../data/stream_resolver.dart';
import '../data/ytmusic/ytmusic_client.dart';
import '../models/app_models.dart';

class JojoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static const _streamLoadTimeout = Duration(seconds: 10);
  static const _resolveTimeout = Duration(seconds: 15);
  static const _fallbackResolveTimeout = Duration(seconds: 8);

  JojoAudioHandler({
    required AppEnvironment environment,
    required AppDatabase database,
  }) : _environment = environment,
       _database = database,
       _player = ja.AudioPlayer() {
    _api = ApiService(environment: _environment);
    _localResolver = LocalStreamResolver();
    _ytClient = YtMusicClient();
    _lrclibService = LrclibService();
    _sponsorBlockService = SponsorBlockService();
    _player.playerStateStream.listen(_broadcastState);
    _player.durationStream.listen((duration) {
      if (duration != null) {
        _syncCurrentTrackMetadata(durationMs: duration.inMilliseconds);
      }
    });
    _player.positionStream.listen((position) {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: position,
          bufferedPosition: _player.bufferedPosition,
        ),
      );
      _maybeHandleImplicitCompletion(position: position);
      if (_sponsorBlockEnabled) _checkSponsorSegment(position);
      if (_crossfadeEnabled) _maybeTriggerCrossfade(position);
    });
    _player.processingStateStream.distinct().listen((state) {
      if (state == ja.ProcessingState.completed) {
        unawaited(_handleQueueCompletion());
      }
    });
    _player.playbackEventStream.listen((event) {
      _syncNativeCurrentIndex(event.currentIndex, forcePublish: true);
      _syncActiveAudioSource(forcePublish: true);
    });
    _player.currentIndexStream.distinct().listen(_handleNativeCurrentIndex);
    _player.sequenceStateStream.listen((sequence) {
      _syncNativeSequenceState(sequence, forcePublish: true);
    });
    Timer.periodic(const Duration(milliseconds: 900), (_) {
      _syncNativeCurrentIndex(_player.currentIndex, forcePublish: true);
      _syncActiveAudioSource(forcePublish: true);
      _watchdogForCompletion();
    });
  }

  void updateApiToken(String? token) {
    _api = ApiService(environment: _environment, accessToken: token);
  }

  /// Appelé depuis app.dart quand l'utilisateur se connecte.
  void setConvexService(ConvexService service, String userId) {
    _convexService = service;
    _convexUserId = userId;
  }

  void clearConvexService() {
    _convexService = null;
    _convexUserId = null;
  }

  final AppEnvironment _environment;
  final AppDatabase _database;
  final ja.AudioPlayer _player;
  late ApiService _api;
  late LocalStreamResolver _localResolver;
  ConvexService? _convexService;
  String? _convexUserId;
  DateTime? _lastConvexPositionSync;
  DateTime? _trackStartTime;
  late YtMusicClient _ytClient;
  final List<Track> _queueTracks = [];
  final Map<String, LyricsData?> _lyricsCache = {};
  final Map<String, Future<LyricsData?>> _lyricsInFlight = {};
  int _currentIndex = -1;
  int _completionCallToken = 0;
  bool _autoplayEnabled = true;
  bool _isExtendingQueue = false;
  bool _pauseRequestedManually = false;
  bool _shuffleEnabled = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  String? _lastAutoplaySeedKey;
  String? _completionGuardTrackKey;
  DateTime? _completionGuardAt;
  String? _lastProgressTrackKey;
  int? _lastProgressPositionMs;
  DateTime? _lastProgressAt;
  int _loadGeneration = 0;
  int _nativeQueueBaseIndex = 0;
  int _nativeQueuePreparedUntil = -1;
  bool _isLoadingTrack = false;
  Future<void> _playerMutationChain = Future<void>.value();

  late LrclibService _lrclibService;
  late SponsorBlockService _sponsorBlockService;
  bool _sponsorBlockEnabled = false;
  List<SponsorSegment> _currentSegments = [];
  bool _isSkippingSegment = false;

  bool _crossfadeEnabled = false;
  int _crossfadeDurationSeconds = 5;
  Timer? _crossfadeTimer;
  double _crossfadeVolume = 1.0;
  bool _fadeInActive = false;

  final Map<String, Future<ResolvedStream>> _resolveInFlight = {};
  final Map<String, _CachedResolvedStream> _resolvedStreamCache = {};

  Future<void> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoplay = true,
  }) async {
    if (tracks.isEmpty) {
      return;
    }
    // Reset chain so a previously hung setUrl can't block new playback requests.
    _playerMutationChain = Future<void>.value();
    _autoplayEnabled = autoplay;
    _lastAutoplaySeedKey = null;
    _queueTracks
      ..clear()
      ..addAll(tracks);
    queue.add(_buildQueueMediaItems());
    final clampedIndex = initialIndex.clamp(0, tracks.length - 1);
    await _loadAt(clampedIndex);
  }

  Future<LyricsData?> fetchLyricsForTrack(
    Track track, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _lyricsCache[track.trackKey];
      if (cached != null) {
        return cached;
      }
    }
    final pending = _lyricsInFlight[track.trackKey];
    if (pending != null) {
      return pending;
    }

    final future = _fetchLyricsWithFallback(track);
    _lyricsInFlight[track.trackKey] = future;
    try {
      final lyrics = await future;
      if (lyrics != null) {
        _lyricsCache[track.trackKey] = lyrics;
      } else {
        _lyricsCache.remove(track.trackKey);
      }
      return lyrics;
    } finally {
      _lyricsInFlight.remove(track.trackKey);
    }
  }

  Future<void> preloadLyricsForTrack(Track track) async {
    await fetchLyricsForTrack(track);
  }

  Future<void> prewarmTrack(Track track) async {
    final offline = await _database.findOfflineTrack(track.trackKey);
    final offlinePath = await _readyOfflinePath(offline);
    if (offlinePath != null) {
      return;
    }
    await _resolveTrack(track);
  }

  Future<void> playDirectSource({
    required String id,
    required String title,
    required String artist,
    required String sourceUrl,
    String? album,
    String? artworkUrl,
    int? durationMs,
  }) async {
    _isLoadingTrack = true;
    final loadGeneration = ++_loadGeneration;
    ++_completionCallToken;
    _playerMutationChain = Future<void>.value();
    _queueTracks.clear();
    _currentIndex = 0;
    _autoplayEnabled = false;
    _lastAutoplaySeedKey = null;
    queue.add([
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        artUri: artworkUrl == null ? null : Uri.tryParse(artworkUrl),
        duration: durationMs == null
            ? null
            : Duration(milliseconds: durationMs),
        extras: {'track_key': id, 'artwork_url': artworkUrl, 'queue_index': 0},
      ),
    ]);
    try {
      await _mutatePlayer(() async {
        await _safeStopPlayer();
        if (loadGeneration != _loadGeneration) {
          return;
        }
        await _player.setUrl(sourceUrl).timeout(_streamLoadTimeout);
        if (loadGeneration != _loadGeneration) {
          return;
        }
        mediaItem.add(queue.value.first);
        _broadcastState(_player.playerState);
        await _player.play();
        _broadcastState(_player.playerState);
      });
    } finally {
      if (loadGeneration == _loadGeneration) {
        _isLoadingTrack = false;
      }
    }
  }

  Track? get currentTrack =>
      _currentIndex >= 0 && _currentIndex < _queueTracks.length
      ? _queueTracks[_currentIndex]
      : null;

  @override
  Future<void> play() {
    _pauseRequestedManually = false;
    return _player.play();
  }

  Future<void> retryCurrentTrack() async {
    if (_currentIndex < 0 || _currentIndex >= _queueTracks.length) {
      return;
    }
    await _loadAt(_currentIndex);
  }

  @override
  Future<void> pause() {
    _pauseRequestedManually = true;
    return _player.pause();
  }

  @override
  Future<void> stop() async {
    _pauseRequestedManually = true;
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    _broadcastState(_player.playerState);
  }

  Future<void> cycleRepeatMode() async {
    switch (_repeatMode) {
      case AudioServiceRepeatMode.none:
        _repeatMode = AudioServiceRepeatMode.all;
      case AudioServiceRepeatMode.all:
        _repeatMode = AudioServiceRepeatMode.one;
      default:
        _repeatMode = AudioServiceRepeatMode.none;
    }
    _broadcastState(_player.playerState);
  }

  @override
  Future<void> skipToNext() async {
    if (_shuffleEnabled && _queueTracks.length > 1) {
      final candidates = List.generate(
        _queueTracks.length,
        (i) => i,
      ).where((i) => i != _currentIndex).toList()..shuffle();
      await _loadAt(candidates.first);
      return;
    }
    if (_currentIndex < _queueTracks.length - 1) {
      await _loadAt(_currentIndex + 1);
      return;
    }
    if (_autoplayEnabled) {
      await _ensureAutoplayTail(seed: currentTrack);
      if (_currentIndex < _queueTracks.length - 1) {
        await _loadAt(_currentIndex + 1);
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex > 0) {
      await _loadAt(_currentIndex - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queueTracks.length) {
      return;
    }
    await _loadAt(index);
  }

  Future<void> _loadAt(int index) async {
    if (index < 0 || index >= _queueTracks.length) {
      return;
    }
    _isLoadingTrack = true;
    _cancelCrossfade();
    final loadGeneration = ++_loadGeneration;
    ++_completionCallToken;
    _currentIndex = index;
    _completionGuardTrackKey = null;
    _completionGuardAt = null;
    _lastProgressTrackKey = _queueTracks[index].trackKey;
    _lastProgressPositionMs = 0;
    _lastProgressAt = DateTime.now();
    _pauseRequestedManually = false;
    _trackStartTime = DateTime.now();
    final track = _queueTracks[index];
    // Sync état de lecture vers Convex (nouveau morceau)
    _syncPlaybackState(forcePosition: true);
    try {
      await _interruptCurrentPlayback();
      if (loadGeneration != _loadGeneration) return;
      _broadcastLoadingState();
      mediaItem.add(_toMediaItem(track, index: index));
      final ja.AudioSource audioSource;
      try {
        audioSource = await _audioSourceForTrack(index, track);
      } catch (error) {
        if (loadGeneration == _loadGeneration) {
          _broadcastLoadError(error);
        }
        throw TrackLoadException(track: track, cause: error);
      }
      if (loadGeneration != _loadGeneration) return;

      try {
        await _player
            .setAudioSources(
              [audioSource],
              initialIndex: 0,
              initialPosition: Duration.zero,
            )
            .timeout(_streamLoadTimeout);
      } on ja.PlayerInterruptedException {
        return;
      } catch (error) {
        if (loadGeneration != _loadGeneration) return;
        _resolvedStreamCache.remove(track.trackKey);
        try {
          final refreshedSource = await _audioSourceForTrack(
            index,
            track,
            forceRefresh: true,
          );
          if (loadGeneration != _loadGeneration) return;
          await _player
              .setAudioSources(
                [refreshedSource],
                initialIndex: 0,
                initialPosition: Duration.zero,
              )
              .timeout(_streamLoadTimeout);
        } on ja.PlayerInterruptedException {
          return;
        } catch (retryError) {
          if (loadGeneration == _loadGeneration) {
            _broadcastLoadError(
              retryError is TimeoutException ? retryError : error,
            );
          }
          throw TrackLoadException(
            track: track,
            cause: retryError is TimeoutException ? retryError : error,
          );
        }
      }

      if (loadGeneration != _loadGeneration) return;
      _nativeQueueBaseIndex = index;
      _nativeQueuePreparedUntil = index;
      mediaItem.add(_toMediaItem(_queueTracks[index], index: index));
      _broadcastState(_player.playerState);
      unawaited(preloadLyricsForTrack(track));
      unawaited(_prepareNativeUpcoming(index, loadGeneration));
      final videoId = track.externalId ?? track.trackKey;
      if (_sponsorBlockEnabled &&
          RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
        unawaited(_loadSponsorSegments(videoId));
      } else {
        _currentSegments = [];
      }
      if (!_pauseRequestedManually) {
        if (_crossfadeEnabled) _startFadeIn();
        await _player.play();
      }
      _broadcastState(_player.playerState);
    } finally {
      if (loadGeneration == _loadGeneration) {
        _isLoadingTrack = false;
      }
    }
  }

  Future<void> _safeStopPlayer() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _interruptCurrentPlayback() async {
    try {
      await _player.pause();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.clearAudioSources();
    } catch (_) {}
    _nativeQueueBaseIndex = _currentIndex;
    _nativeQueuePreparedUntil = _currentIndex - 1;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
      ),
    );
  }

  Future<ja.AudioSource> _audioSourceForTrack(
    int index,
    Track track, {
    bool forceRefresh = false,
  }) async {
    final offline = await _database.findOfflineTrack(track.trackKey);
    final offlinePath = await _readyOfflinePath(offline);
    final media = _toMediaItem(track, index: index);
    if (offlinePath != null) {
      return ja.AudioSource.uri(Uri.file(offlinePath), tag: media);
    }

    if (forceRefresh) {
      _resolvedStreamCache.remove(track.trackKey);
    }
    final resolved = await _resolveTrack(track);
    if (resolved.thumbnailUrl != null) {
      resolvedArtworkCache[track.trackKey] = resolved.thumbnailUrl!;
    }
    if (index == _currentIndex) {
      _syncCurrentTrackMetadata(
        artworkUrl: resolved.thumbnailUrl,
        durationMs: resolved.durationMs,
      );
    }
    return ja.AudioSource.uri(_streamUri(resolved.streamUrl), tag: media);
  }

  Uri _streamUri(String source) {
    final value = source.trim();
    if (value.isEmpty) {
      throw const FormatException('source audio vide');
    }
    final uri = Uri.parse(value);
    if (uri.hasScheme) {
      return uri;
    }
    if (value.startsWith('/')) {
      return Uri.parse('${_environment.apiBaseUrl}$value');
    }
    throw FormatException('source audio invalide: $source');
  }

  void _handleNativeCurrentIndex(int? nativeIndex) {
    _syncNativeCurrentIndex(nativeIndex, forcePublish: true);
  }

  void _syncActiveAudioSource({bool forcePublish = false}) {
    final sequence = _player.sequenceState;
    _syncNativeSequenceState(sequence, forcePublish: forcePublish);
  }

  void _syncNativeSequenceState(
    ja.SequenceState sequence, {
    bool forcePublish = false,
  }) {
    if (_isLoadingTrack) return;
    final tag = sequence.currentSource?.tag;
    if (tag is MediaItem) {
      final queueIndex = _queueIndexForMediaItem(
        tag,
        nativeIndex: sequence.currentIndex,
      );
      if (queueIndex != null) {
        _publishQueueIndex(queueIndex, forcePublish: forcePublish);
        return;
      }
    }
    _syncNativeCurrentIndex(sequence.currentIndex, forcePublish: forcePublish);
  }

  void _syncNativeCurrentIndex(int? nativeIndex, {bool forcePublish = false}) {
    if (nativeIndex == null || _isLoadingTrack) return;
    final queueIndex = _nativeQueueBaseIndex + nativeIndex;
    _publishQueueIndex(queueIndex, forcePublish: forcePublish);
  }

  int? _queueIndexForMediaItem(MediaItem item, {int? nativeIndex}) {
    final extrasIndex = item.extras?['queue_index'];
    if (extrasIndex is int) return extrasIndex;
    if (extrasIndex is num) return extrasIndex.toInt();
    if (extrasIndex is String) {
      final parsed = int.tryParse(extrasIndex);
      if (parsed != null) return parsed;
    }

    final trackKey = item.extras?['track_key']?.toString();
    if (trackKey != null && trackKey.isNotEmpty) {
      final index = _queueTracks.indexWhere(
        (track) => track.trackKey == trackKey,
      );
      if (index >= 0) return index;
    }

    if (nativeIndex != null) {
      return _nativeQueueBaseIndex + nativeIndex;
    }
    return null;
  }

  void _publishQueueIndex(int queueIndex, {bool forcePublish = false}) {
    if (queueIndex < 0 || queueIndex >= _queueTracks.length) {
      return;
    }

    final nextItem = _toMediaItem(_queueTracks[queueIndex], index: queueIndex);
    final publishedItem = mediaItem.value;
    final alreadyPublished =
        publishedItem?.id == nextItem.id &&
        playbackState.value.queueIndex == queueIndex;
    if (queueIndex == _currentIndex) {
      if (forcePublish && !alreadyPublished) {
        mediaItem.add(nextItem);
        _broadcastState(_player.playerState);
      }
      return;
    }

    _recordPlaybackEvent('completed');
    _currentIndex = queueIndex;
    _completionGuardTrackKey = null;
    _completionGuardAt = null;
    _lastProgressTrackKey = _queueTracks[queueIndex].trackKey;
    _lastProgressPositionMs = 0;
    _lastProgressAt = DateTime.now();
    _trackStartTime = DateTime.now();
    queue.add(_buildQueueMediaItems());
    mediaItem.add(nextItem);
    _broadcastState(_player.playerState);
    _syncPlaybackState(forcePosition: true);
    unawaited(preloadLyricsForTrack(_queueTracks[queueIndex]));
    unawaited(_prepareNativeUpcoming(queueIndex, _loadGeneration));
  }

  Future<void> _prepareNativeUpcoming(int index, int loadGeneration) async {
    final targetIndex = (index + 3).clamp(0, _queueTracks.length - 1);
    if (targetIndex <= _nativeQueuePreparedUntil) {
      if (_autoplayEnabled && _queueTracks.length - index <= 3) {
        unawaited(_ensureAutoplayTail(seed: _queueTracks[index]));
      }
      return;
    }

    final sources = <ja.AudioSource>[];
    var preparedUntil = _nativeQueuePreparedUntil;
    for (var i = _nativeQueuePreparedUntil + 1; i <= targetIndex; i++) {
      if (loadGeneration != _loadGeneration) return;
      try {
        sources.add(await _audioSourceForTrack(i, _queueTracks[i]));
        preparedUntil = i;
      } catch (_) {
        break;
      }
    }
    if (sources.isNotEmpty && loadGeneration == _loadGeneration) {
      try {
        await _player.addAudioSources(sources);
        _nativeQueuePreparedUntil = preparedUntil;
      } catch (_) {}
    }

    if (_autoplayEnabled && _queueTracks.length - index <= 3) {
      await _ensureAutoplayTail(seed: _queueTracks[index]);
      if (loadGeneration == _loadGeneration &&
          _queueTracks.length - 1 > _nativeQueuePreparedUntil) {
        unawaited(_prepareNativeUpcoming(index, loadGeneration));
      }
    }
  }

  Future<void> _mutatePlayer(Future<void> Function() action) {
    final completer = Completer<void>();
    _playerMutationChain = _playerMutationChain.catchError((_) {}).then((
      _,
    ) async {
      try {
        await action();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<String?> _readyOfflinePath(OfflineTrack? offline) async {
    if (offline == null || offline.status != 'downloaded') {
      return null;
    }
    final file = File(offline.filePath);
    if (!await file.exists()) {
      return null;
    }
    if (!offline.filePath.endsWith('.audio')) {
      return offline.filePath;
    }
    return _repairLegacyOfflineFile(offline, file);
  }

  Future<String> _repairLegacyOfflineFile(
    OfflineTrack offline,
    File file,
  ) async {
    final extension = await _guessAudioExtension(file);
    final repairedPath = file.path.replaceFirst(
      RegExp(r'\.audio$'),
      '.$extension',
    );
    if (repairedPath == file.path) {
      return file.path;
    }

    try {
      final repairedFile = File(repairedPath);
      if (await repairedFile.exists()) {
        await file.delete();
      } else {
        await file.rename(repairedPath);
      }
      await _database.upsertOfflineTrack(
        OfflineTracksCompanion.insert(
          trackKey: offline.trackKey,
          title: offline.title,
          artist: offline.artist,
          album: Value(offline.album),
          artworkUrl: Value(offline.artworkUrl),
          filePath: repairedPath,
          status: 'downloaded',
          progress: const Value(1),
          createdAt: offline.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
      return repairedPath;
    } catch (_) {
      return file.path;
    }
  }

  Future<String> _guessAudioExtension(File file) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, 16)) {
      bytes.addAll(chunk);
      if (bytes.length >= 16) {
        break;
      }
    }

    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'm4a';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1A &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xDF &&
        bytes[3] == 0xA3) {
      return 'webm';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45) {
      return 'wav';
    }
    if (bytes.length >= 3 &&
        ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
            (bytes.length >= 2 &&
                bytes[0] == 0xFF &&
                (bytes[1] & 0xE0) == 0xE0))) {
      return 'mp3';
    }
    return 'm4a';
  }

  Future<ResolvedStream> _resolveTrack(Track track) {
    final cached = _resolvedStreamCache[track.trackKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return Future.value(cached.stream);
    }

    final inFlight = _resolveInFlight[track.trackKey];
    if (inFlight != null) return inFlight;

    final future = _doResolveTrack(track);
    _resolveInFlight[track.trackKey] = future;
    return future.whenComplete(() => _resolveInFlight.remove(track.trackKey));
  }

  Future<ResolvedStream> _doResolveTrack(Track track) async {
    try {
      final resolved = await _api.resolveTrack(track).timeout(_resolveTimeout);
      _cacheResolvedTrack(track, resolved);
      return resolved;
    } catch (_) {
      final resolved = await _localResolver
          .resolve(track)
          .timeout(_fallbackResolveTimeout);
      _cacheResolvedTrack(track, resolved);
      return resolved;
    }
  }

  void _cacheResolvedTrack(Track track, ResolvedStream resolved) {
    final ttl = _isManagedMediaUrl(resolved.streamUrl)
        ? const Duration(hours: 5)
        : const Duration(minutes: 1);
    _resolvedStreamCache[track.trackKey] = _CachedResolvedStream(
      stream: resolved,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  bool _isManagedMediaUrl(String url) {
    final mediaBase = '${_environment.apiBaseUrl}/api/v1/media/';
    return url.startsWith('/api/v1/media/') || url.startsWith(mediaBase);
  }

  Future<void> _prefetchQueueAround(int index) async {
    for (final offset in [1, 2]) {
      final nextIndex = index + offset;
      if (nextIndex >= 0 && nextIndex < _queueTracks.length) {
        unawaited(_resolveTrack(_queueTracks[nextIndex]));
      }
    }
    if (_autoplayEnabled && _queueTracks.length - index <= 3) {
      unawaited(_ensureAutoplayTail(seed: _queueTracks[index]));
    }
  }

  Future<void> _handleQueueCompletion() async {
    // Enregistre l'événement de complétion dans Convex (fire-and-forget)
    _recordPlaybackEvent('completed');
    final token = ++_completionCallToken;
    try {
      if (_repeatMode == AudioServiceRepeatMode.one) {
        await _player.seek(Duration.zero);
        unawaited(_player.play());
        return;
      }
      if (_shuffleEnabled && _queueTracks.length > 1) {
        final candidates = List.generate(
          _queueTracks.length,
          (i) => i,
        ).where((i) => i != _currentIndex).toList()..shuffle();
        await _loadAt(candidates.first);
        return;
      }
      if (_repeatMode == AudioServiceRepeatMode.all &&
          _currentIndex >= _queueTracks.length - 1) {
        if (token != _completionCallToken) return;
        await _loadAt(0);
        return;
      }
      if (_currentIndex < _queueTracks.length - 1) {
        await _tryLoadNext(token);
      } else if (_autoplayEnabled) {
        // Wait for any in-flight queue extension before deciding to stop.
        if (_isExtendingQueue) {
          for (int i = 0; i < 20 && _isExtendingQueue; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
        await _ensureAutoplayTail(seed: currentTrack);
        if (_currentIndex < _queueTracks.length - 1) {
          await _tryLoadNext(token);
        } else {
          await stop();
        }
      } else {
        await stop();
      }
    } catch (_) {
      await stop();
    }
  }

  Future<void> _tryLoadNext(int token) async {
    // Try up to 3 consecutive tracks starting from the next one.
    // If a track fails to load (network / stream error), skip it and try the
    // next one rather than stopping — this prevents silence mid-playlist.
    final startIndex = _currentIndex + 1;
    for (int skip = 0; skip < 3; skip++) {
      final candidateIndex = startIndex + skip;
      if (candidateIndex >= _queueTracks.length) break;
      if (_completionCallToken != token) return;
      // Two attempts per candidate (transient network errors).
      for (int attempt = 0; attempt < 2; attempt++) {
        if (_completionCallToken != token) return;
        try {
          await _loadAt(candidateIndex);
          return;
        } catch (_) {
          continue;
        }
      }
    }
    if (_completionCallToken == token) {
      await stop();
    }
  }

  void _maybeHandleImplicitCompletion({Duration? position}) {
    final track = currentTrack;
    final duration = _effectiveTrackDuration();
    if (track == null ||
        duration == null ||
        duration <= const Duration(seconds: 1)) {
      return;
    }

    final currentPosition = position ?? _player.position;
    final remaining = duration - currentPosition;
    final processingState = _player.processingState;
    final looksFinished =
        remaining <= const Duration(milliseconds: 350) &&
        (processingState == ja.ProcessingState.completed ||
            (!_player.playing && processingState == ja.ProcessingState.ready));
    if (!looksFinished) {
      return;
    }

    final now = DateTime.now();
    if (_completionGuardTrackKey == track.trackKey &&
        _completionGuardAt != null &&
        now.difference(_completionGuardAt!) < const Duration(seconds: 2)) {
      return;
    }
    _completionGuardTrackKey = track.trackKey;
    _completionGuardAt = now;
  }

  void _watchdogForCompletion() {
    if (_pauseRequestedManually || _isLoadingTrack) {
      return;
    }
    final track = currentTrack;
    final duration = _effectiveTrackDuration();
    if (track == null ||
        duration == null ||
        duration <= const Duration(seconds: 1)) {
      return;
    }
    final position = _player.position;
    _recordProgress(track.trackKey, position);
    final remaining = duration - position;

    final looksFinished =
        !_player.playing &&
        remaining <= const Duration(seconds: 2) &&
        _player.processingState != ja.ProcessingState.loading &&
        _player.processingState != ja.ProcessingState.buffering;
    final looksStalledAtTail =
        remaining <= const Duration(milliseconds: 1500) &&
        !_player.playing &&
        _player.processingState != ja.ProcessingState.loading &&
        _player.processingState != ja.ProcessingState.buffering &&
        _progressHasStalled(
          track.trackKey,
          position,
          const Duration(seconds: 3),
        );

    final looksStalledMidTrack =
        _player.playing &&
        _player.processingState == ja.ProcessingState.buffering &&
        _progressHasStalled(
          track.trackKey,
          position,
          const Duration(seconds: 8),
        );

    // Stream URL died mid-track (network cut, expired URL): player stopped
    // unexpectedly without reaching end → re-resolve and restart the track.
    final looksDeadMidTrack =
        !_player.playing &&
        !_pauseRequestedManually &&
        remaining > const Duration(seconds: 5) &&
        _player.processingState == ja.ProcessingState.idle &&
        _progressHasStalled(
          track.trackKey,
          position,
          const Duration(seconds: 4),
        );

    if (!looksFinished &&
        !looksStalledAtTail &&
        !looksStalledMidTrack &&
        !looksDeadMidTrack) {
      return;
    }

    final now = DateTime.now();
    if (_completionGuardTrackKey == track.trackKey &&
        _completionGuardAt != null &&
        now.difference(_completionGuardAt!) < const Duration(seconds: 2)) {
      return;
    }
    _completionGuardTrackKey = track.trackKey;
    _completionGuardAt = now;

    if (looksStalledMidTrack) {
      unawaited(_player.play());
    } else if (looksDeadMidTrack) {
      // Re-resolve stream from scratch (clears hung mutation chain too).
      _playerMutationChain = Future<void>.value();
      unawaited(_loadAt(_currentIndex));
    } else {
      unawaited(_handleQueueCompletion());
    }
  }

  Duration? _effectiveTrackDuration() {
    final playerDuration = _player.duration;
    if (playerDuration != null && playerDuration > Duration.zero) {
      return playerDuration;
    }
    final trackDurationMs = currentTrack?.durationMs;
    if (trackDurationMs != null && trackDurationMs > 0) {
      return Duration(milliseconds: trackDurationMs);
    }
    final mediaDuration = mediaItem.value?.duration;
    if (mediaDuration != null && mediaDuration > Duration.zero) {
      return mediaDuration;
    }
    return null;
  }

  void _recordProgress(String trackKey, Duration position) {
    final positionMs = position.inMilliseconds;
    final now = DateTime.now();
    if (_lastProgressTrackKey != trackKey) {
      _lastProgressTrackKey = trackKey;
      _lastProgressPositionMs = positionMs;
      _lastProgressAt = now;
      return;
    }

    final previousPositionMs = _lastProgressPositionMs;
    if (previousPositionMs == null ||
        (positionMs - previousPositionMs).abs() >= 400) {
      _lastProgressPositionMs = positionMs;
      _lastProgressAt = now;
    }
  }

  bool _progressHasStalled(
    String trackKey,
    Duration position,
    Duration threshold,
  ) {
    _recordProgress(trackKey, position);
    if (_lastProgressTrackKey != trackKey || _lastProgressAt == null) {
      return false;
    }
    return DateTime.now().difference(_lastProgressAt!) >= threshold;
  }

  Future<void> _ensureAutoplayTail({Track? seed}) async {
    final seedTrack = seed ?? currentTrack;
    if (!_autoplayEnabled ||
        seedTrack == null ||
        _isExtendingQueue ||
        _lastAutoplaySeedKey == seedTrack.trackKey) {
      return;
    }

    final videoId = seedTrack.externalId ?? seedTrack.trackKey;
    final isYtId = RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId);
    if (!isYtId) return;

    _isExtendingQueue = true;
    try {
      final existingKeys = _queueTracks.map((t) => t.trackKey).toSet();
      final radioTracks = await _ytClient.fetchRadio(videoId);
      final newTracks = radioTracks
          .where((t) => !existingKeys.contains(t.videoId))
          .take(10)
          .map((t) => t.toTrack())
          .toList();
      if (newTracks.isEmpty) return;
      _lastAutoplaySeedKey = seedTrack.trackKey;
      _queueTracks.addAll(newTracks);
      queue.add(_buildQueueMediaItems());
      final prefetchIndex = _currentIndex < 0 ? 0 : _currentIndex;
      unawaited(_prefetchQueueAround(prefetchIndex));
    } catch (_) {
      return;
    } finally {
      _isExtendingQueue = false;
    }
  }

  List<MediaItem> _buildQueueMediaItems() => _queueTracks
      .asMap()
      .entries
      .map((entry) => _toMediaItem(entry.value, index: entry.key))
      .toList(growable: false);

  String _mediaItemId(Track track, {required int index}) {
    final parts = [
      track.externalId,
      track.trackKey,
      track.provider,
      track.artist,
      track.title,
      track.album,
      '$index',
    ].whereType<String>().where((value) => value.isNotEmpty);
    return parts.join('::');
  }

  MediaItem _toMediaItem(Track track, {required int index}) => MediaItem(
    id: _mediaItemId(track, index: index),
    title: track.title,
    artist: track.artist,
    album: track.album,
    artUri: track.displayArtworkUrl == null
        ? null
        : Uri.tryParse(track.displayArtworkUrl!),
    duration: track.durationMs == null
        ? null
        : Duration(milliseconds: track.durationMs!),
    extras: {
      'track_key': track.trackKey,
      'queue_index': index,
      if (track.externalId != null) 'external_id': track.externalId,
      if (track.provider.isNotEmpty) 'provider': track.provider,
      if (track.displayArtworkUrl != null)
        'artwork_url': track.displayArtworkUrl,
    },
  );

  void _syncCurrentTrackMetadata({String? artworkUrl, int? durationMs}) {
    if (_currentIndex < 0 || _currentIndex >= _queueTracks.length) {
      return;
    }
    final current = _queueTracks[_currentIndex];
    final nextArtwork = current.artworkUrl ?? artworkUrl;
    final nextDuration = current.durationMs ?? durationMs;
    if (nextArtwork == current.artworkUrl &&
        nextDuration == current.durationMs) {
      return;
    }

    final updated = current.copyWith(
      artworkUrl: nextArtwork,
      durationMs: nextDuration,
    );
    _queueTracks[_currentIndex] = updated;
    final updatedQueue = _buildQueueMediaItems();
    queue.add(updatedQueue);
    mediaItem.add(updatedQueue[_currentIndex]);
  }

  void _broadcastState(ja.PlayerState state) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.playPause,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _mapProcessingState(state.processingState),
        playing: state.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
        shuffleMode: _shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: _repeatMode,
      ),
    );
    // Sync play/pause vers Convex (throttlé côté _syncPlaybackState)
    _syncPlaybackState();
  }

  void _broadcastLoadingState() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        processingState: AudioProcessingState.loading,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
      ),
    );
  }

  void _broadcastLoadError(Object error) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        processingState: AudioProcessingState.error,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
        errorMessage: 'Lecture impossible: $error',
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ja.ProcessingState state) {
    switch (state) {
      case ja.ProcessingState.idle:
        return AudioProcessingState.idle;
      case ja.ProcessingState.loading:
        return AudioProcessingState.loading;
      case ja.ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ja.ProcessingState.ready:
        return AudioProcessingState.ready;
      case ja.ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
    _broadcastState(_player.playerState);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _queueTracks.length ||
        newIndex >= _queueTracks.length ||
        oldIndex == newIndex) {
      return;
    }
    final track = _queueTracks.removeAt(oldIndex);
    _queueTracks.insert(newIndex, track);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    queue.add(_buildQueueMediaItems());
  }

  void setSponsorBlockEnabled(bool enabled) {
    _sponsorBlockEnabled = enabled;
    if (!enabled) _currentSegments = [];
  }

  void setCrossfadeEnabled(bool enabled) {
    _crossfadeEnabled = enabled;
    if (!enabled) _cancelCrossfade();
  }

  void setCrossfadeDuration(int seconds) {
    _crossfadeDurationSeconds = seconds.clamp(1, 10);
  }

  void _checkSponsorSegment(Duration position) {
    if (_isSkippingSegment || _currentSegments.isEmpty) return;
    for (final seg in _currentSegments) {
      if (seg.contains(position)) {
        _isSkippingSegment = true;
        unawaited(
          _player.seek(seg.end).then((_) => _isSkippingSegment = false),
        );
        return;
      }
    }
  }

  Future<void> _loadSponsorSegments(String videoId) async {
    try {
      _currentSegments = await _sponsorBlockService.fetchSegments(videoId);
    } catch (_) {
      _currentSegments = [];
    }
  }

  void _maybeTriggerCrossfade(Duration position) {
    if (_crossfadeTimer != null) return;
    final duration = _effectiveTrackDuration();
    if (duration == null || !_player.playing) return;
    final remaining = duration - position;
    final threshold = Duration(seconds: _crossfadeDurationSeconds);
    if (remaining > Duration.zero && remaining <= threshold) {
      _startFadeOut();
    }
  }

  void _startFadeOut() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final duration = _effectiveTrackDuration();
      final pos = _player.position;
      if (duration == null || !_crossfadeEnabled) {
        _cancelCrossfade();
        return;
      }
      final remaining = duration - pos;
      if (remaining <= Duration.zero) {
        _crossfadeTimer?.cancel();
        _crossfadeTimer = null;
        return;
      }
      final vol =
          (remaining.inMilliseconds /
                  Duration(seconds: _crossfadeDurationSeconds).inMilliseconds)
              .clamp(0.0, 1.0);
      _crossfadeVolume = vol;
      _player.setVolume(vol);
    });
  }

  void _startFadeIn() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _crossfadeVolume = 0.0;
    _fadeInActive = true;
    _player.setVolume(0.0);
    _crossfadeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_fadeInActive || !_crossfadeEnabled) {
        _cancelCrossfade();
        return;
      }
      final vol = (_crossfadeVolume + 0.04).clamp(0.0, 1.0);
      _crossfadeVolume = vol;
      _player.setVolume(vol);
      if (vol >= 1.0) {
        _fadeInActive = false;
        _crossfadeTimer?.cancel();
        _crossfadeTimer = null;
      }
    });
  }

  void _cancelCrossfade() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _crossfadeVolume = 1.0;
    _fadeInActive = false;
    _player.setVolume(1.0);
  }

  Future<LyricsData?> _fetchLyricsWithFallback(Track track) async {
    final durationSeconds = track.durationMs != null
        ? track.durationMs! ~/ 1000
        : null;
    final serverFuture = _api
        .fetchLyrics(track)
        .timeout(const Duration(seconds: 12))
        .catchError((_) => null as LyricsData?);
    final lrclibFuture = _lrclibService.fetchLyrics(
      artist: track.artist,
      title: track.title,
      durationSeconds: durationSeconds,
    );
    final results = await Future.wait([serverFuture, lrclibFuture]);
    final server = results[0];
    final lrclib = results[1];
    if (server?.syncedLyrics?.isNotEmpty == true) return server;
    if (lrclib?.syncedLyrics?.isNotEmpty == true) return lrclib;
    return server ?? lrclib;
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return [
        const MediaItem(id: 'queue', title: "File d'attente", playable: false),
      ];
    }
    if (parentMediaId == 'queue') {
      return _buildQueueMediaItems();
    }
    return [];
  }

  @override
  Future<void> onTaskRemoved() async {
    // Ne rien détruire — la lecture doit continuer en arrière-plan.
  }

  // ─── Convex playback sync ────────────────────────────────────────────────

  void _syncPlaybackState({bool forcePosition = false}) {
    final convex = _convexService;
    final userId = _convexUserId;
    final track = currentTrack;
    if (convex == null || userId == null || track == null) return;

    final now = DateTime.now();
    final isPlaying = playbackState.value.playing;
    final positionMs = playbackState.value.position.inMilliseconds;

    // Throttle : sync position au max toutes les 5s sauf changement de track/état
    if (!forcePosition && _lastConvexPositionSync != null) {
      if (now.difference(_lastConvexPositionSync!).inSeconds < 5) return;
    }
    _lastConvexPositionSync = now;

    // Fire-and-forget — ne jamais bloquer la lecture
    unawaited(
      convex
          .syncPlaybackState(
            convexUserId: userId,
            track: track,
            isPlaying: isPlaying,
            positionMs: positionMs,
          )
          .catchError((_) {}),
    );
  }

  void _recordPlaybackEvent(String eventType) {
    final convex = _convexService;
    final userId = _convexUserId;
    final track = currentTrack;
    if (convex == null || userId == null || track == null) return;

    final positionMs = playbackState.value.position.inMilliseconds;
    final durationMs = track.durationMs ?? 0;
    final listenedMs = _trackStartTime != null
        ? DateTime.now().difference(_trackStartTime!).inMilliseconds
        : positionMs;
    final completionRatio = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    unawaited(
      convex
          .recordPlaybackEvent(
            convexUserId: userId,
            track: track,
            eventType: eventType,
            listenedMs: listenedMs,
            completionRatio: completionRatio,
          )
          .catchError((_) {}),
    );
  }
}

class _CachedResolvedStream {
  const _CachedResolvedStream({required this.stream, required this.expiresAt});

  final ResolvedStream stream;
  final DateTime expiresAt;
}

class TrackLoadException implements Exception {
  const TrackLoadException({required this.track, required this.cause});

  final Track track;
  final Object cause;

  @override
  String toString() =>
      'Impossible de lire "${track.title}" (${track.artist}): $cause';
}
