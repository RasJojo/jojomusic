import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:just_audio/just_audio.dart' as ja;

import '../config/app_environment.dart';
import '../data/app_database.dart';
import '../data/api_service.dart';
import '../models/app_models.dart';

class JojoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  JojoAudioHandler({
    required AppEnvironment environment,
    required AppDatabase database,
  }) : _environment = environment,
       _database = database,
       _player = ja.AudioPlayer() {
    _api = ApiService(environment: _environment);
    _player.playerStateStream.listen(_broadcastState);
    _player.playbackEventStream.listen(_handlePlaybackEvent);
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
    });
    _player.processingStateStream.distinct().listen((state) {
      if (state == ja.ProcessingState.completed) {
        unawaited(_handleQueueCompletion());
      } else {
        _maybeHandleImplicitCompletion();
      }
    });
    _completionWatchdog = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _watchdogForCompletion();
    });
  }

  final AppEnvironment _environment;
  final AppDatabase _database;
  final ja.AudioPlayer _player;
  late final ApiService _api;
  final List<Track> _queueTracks = [];
  final Map<String, _ResolvedTrackCacheEntry> _resolvedTrackCache = {};
  final Map<String, Future<ResolvedStream>> _resolveInFlight = {};
  final Map<String, LyricsData?> _lyricsCache = {};
  final Map<String, Future<LyricsData?>> _lyricsInFlight = {};
  late final Timer _completionWatchdog;
  int _currentIndex = -1;
  bool _isHandlingQueueCompletion = false;
  bool _autoplayEnabled = true;
  bool _isExtendingQueue = false;
  bool _pauseRequestedManually = false;
  String? _lastAutoplaySeedKey;
  String? _completionGuardTrackKey;
  DateTime? _completionGuardAt;
  String? _lastProgressTrackKey;
  int? _lastProgressPositionMs;
  DateTime? _lastProgressAt;
  int _loadGeneration = 0;
  Future<void> _playerMutationChain = Future<void>.value();

  Future<void> loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoplay = true,
  }) async {
    if (tracks.isEmpty) {
      return;
    }
    _autoplayEnabled = autoplay;
    _lastAutoplaySeedKey = null;
    _queueTracks
      ..clear()
      ..addAll(tracks);
    queue.add(_buildQueueMediaItems());
    await _loadAt(initialIndex);
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

    final future = _api.fetchLyrics(track);
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
        extras: {
          'track_key': id,
          'artwork_url': artworkUrl,
        },
      ),
    ]);
    await _mutatePlayer(() async {
      await _safeStopPlayer();
      await _player.setUrl(sourceUrl);
      mediaItem.add(queue.value.first);
      _broadcastState(_player.playerState);
      await _player.play();
      _broadcastState(_player.playerState);
    });
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

  @override
  Future<void> skipToNext() async {
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
    final loadGeneration = ++_loadGeneration;
    _currentIndex = index;
    _completionGuardTrackKey = null;
    _completionGuardAt = null;
    _lastProgressTrackKey = _queueTracks[index].trackKey;
    _lastProgressPositionMs = 0;
    _lastProgressAt = DateTime.now();
    _pauseRequestedManually = false;
    final track = _queueTracks[index];
    await _safeStopPlayer();
    _broadcastLoadingState();
    final offline = await _database.findOfflineTrack(track.trackKey);
    final offlinePath = await _readyOfflinePath(offline);
    ResolvedStream? resolved;
    final source = offlinePath != null
        ? Uri.file(offlinePath).toString()
        : (resolved = await _resolveTrack(track)).streamUrl;

    if (loadGeneration != _loadGeneration) {
      return;
    }

    if (resolved != null) {
      _syncCurrentTrackMetadata(
        artworkUrl: resolved.thumbnailUrl,
        durationMs: resolved.durationMs,
      );
    }

    await _mutatePlayer(() async {
      if (loadGeneration != _loadGeneration) {
        return;
      }

      if (source.startsWith('file://')) {
        await _player.setFilePath(Uri.parse(source).toFilePath());
      } else {
        await _player.setUrl(source);
      }

      if (loadGeneration != _loadGeneration) {
        await _safeStopPlayer();
        return;
      }

      mediaItem.add(_toMediaItem(_queueTracks[index], index: index));
      _broadcastState(_player.playerState);
      unawaited(preloadLyricsForTrack(track));
      unawaited(_prefetchQueueAround(index));
      await _player.play();
      _broadcastState(_player.playerState);
    });
  }

  Future<void> _safeStopPlayer() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _mutatePlayer(Future<void> Function() action) {
    final completer = Completer<void>();
    _playerMutationChain = _playerMutationChain
        .catchError((_) {})
        .then((_) async {
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

  Future<ResolvedStream> _resolveTrack(Track track) async {
    final cached = _resolvedTrackCache[track.trackKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.stream;
    }

    final inflight = _resolveInFlight[track.trackKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _api.resolveTrack(track);
    _resolveInFlight[track.trackKey] = future;
    try {
      final resolved = await future;
      _resolvedTrackCache[track.trackKey] = _ResolvedTrackCacheEntry(
        stream: resolved,
        expiresAt: DateTime.now().add(const Duration(minutes: 18)),
      );
      return resolved;
    } finally {
      _resolveInFlight.remove(track.trackKey);
    }
  }

  Future<void> _prefetchQueueAround(int index) async {
    final upcoming = <Track>[];
    for (final offset in [1, 2]) {
      final nextIndex = index + offset;
      if (nextIndex >= 0 && nextIndex < _queueTracks.length) {
        upcoming.add(_queueTracks[nextIndex]);
      }
    }
    for (final track in upcoming) {
      if (!_resolvedTrackCache.containsKey(track.trackKey)) {
        unawaited(_resolveTrack(track));
      }
    }
    if (_autoplayEnabled && _queueTracks.length - index <= 3) {
      unawaited(_ensureAutoplayTail(seed: _queueTracks[index]));
    }
  }

  Future<void> _handleQueueCompletion() async {
    if (_isHandlingQueueCompletion) {
      return;
    }
    _isHandlingQueueCompletion = true;
    try {
      if (_currentIndex < _queueTracks.length - 1) {
        await _loadAt(_currentIndex + 1);
      } else if (_autoplayEnabled) {
        await _ensureAutoplayTail(seed: currentTrack);
        if (_currentIndex < _queueTracks.length - 1) {
          await _loadAt(_currentIndex + 1);
        } else {
          await stop();
        }
      } else {
        await stop();
      }
    } catch (_) {
      await stop();
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        _isHandlingQueueCompletion = false;
      });
    }
  }

  void _handlePlaybackEvent(ja.PlaybackEvent event) {
    final duration = _effectiveTrackDuration();
    if (_currentIndex < 0 || duration == null || duration == Duration.zero) {
      return;
    }
    final atEnd = event.updatePosition >= duration - const Duration(milliseconds: 250);
    final completed =
        event.processingState == ja.ProcessingState.completed ||
        (atEnd &&
            !_player.playing &&
            event.processingState == ja.ProcessingState.ready);
    if (completed) {
      unawaited(_handleQueueCompletion());
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
    unawaited(_handleQueueCompletion());
  }

  void _watchdogForCompletion() {
    if (_pauseRequestedManually || _isHandlingQueueCompletion) {
      return;
    }
    final track = currentTrack;
    final duration = _effectiveTrackDuration();
    if (track == null || duration == null || duration <= const Duration(seconds: 1)) {
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
        remaining <= const Duration(seconds: 3) &&
        _progressHasStalled(track.trackKey, position, const Duration(seconds: 2));
    if (!looksFinished && !looksStalledAtTail) {
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
    unawaited(_handleQueueCompletion());
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
    if (previousPositionMs == null || (positionMs - previousPositionMs).abs() >= 400) {
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

    _isExtendingQueue = true;
    try {
      final tracks = await _api.fetchSimilarTracks(
        seedTrack,
        limit: 10,
        excludeTrackKeys: _queueTracks
            .map((track) => track.trackKey)
            .toList(growable: false),
      );
      if (tracks.isEmpty) {
        return;
      }
      _queueTracks.addAll(tracks);
      _lastAutoplaySeedKey = seedTrack.trackKey;
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
      if (track.externalId != null) 'external_id': track.externalId,
      if (track.provider.isNotEmpty) 'provider': track.provider,
      if (track.displayArtworkUrl != null) 'artwork_url': track.displayArtworkUrl,
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
      ),
    );
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
  Future<void> onTaskRemoved() async {
    _completionWatchdog.cancel();
    await super.onTaskRemoved();
  }
}

class _ResolvedTrackCacheEntry {
  const _ResolvedTrackCacheEntry({
    required this.stream,
    required this.expiresAt,
  });

  final ResolvedStream stream;
  final DateTime expiresAt;
}
// Audio
