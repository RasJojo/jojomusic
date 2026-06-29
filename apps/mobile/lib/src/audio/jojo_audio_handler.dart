import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:drift/drift.dart' show Value;
import 'package:just_audio/just_audio.dart' as ja;

import '../config/app_environment.dart';
import '../data/api_service.dart';
import '../data/app_database.dart';
import '../data/artwork_cache.dart';
import '../data/convex_service.dart';
import '../data/itunes_preview_resolver.dart';
import '../data/lrclib_service.dart';
import '../data/sponsorblock_service.dart';
import '../data/stream_resolver.dart';
import '../data/ytmusic/ytmusic_client.dart';
import '../models/app_models.dart';

class JojoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static const _streamLoadTimeout = Duration(seconds: 10);
  static const _serverResolveFastTimeout = Duration(seconds: 5);
  static const _itunesPreviewLookupTimeout = Duration(milliseconds: 1500);
  static const _fallbackResolveTimeout = Duration(seconds: 22);
  static const _queueSkipLookahead = 8;

  JojoAudioHandler({
    required AppEnvironment environment,
    required AppDatabase database,
  }) : _environment = environment,
       _database = database,
       _player = ja.AudioPlayer() {
    _api = ApiService(environment: _environment);
    _localResolver = LocalStreamResolver();
    _itunesPreviewResolver = ItunesPreviewResolver();
    _ytClient = YtMusicClient();
    _lrclibService = LrclibService();
    _sponsorBlockService = SponsorBlockService();
    _subPlayerState = _player.playerStateStream.listen(_broadcastState);
    _subDuration = _player.durationStream.listen((duration) {
      if (duration != null) {
        _syncCurrentTrackMetadata(durationMs: duration.inMilliseconds);
      }
    });
    _subPosition = _player.positionStream.listen((position) {
      final currentState = playbackState.value;
      final playerState = _player.playerState;
      if (currentState.processingState == AudioProcessingState.error &&
          _player.playing &&
          playerState.processingState == ja.ProcessingState.ready) {
        _broadcastState(playerState);
        return;
      }
      playbackState.add(
        currentState.copyWith(
          updatePosition: position,
          bufferedPosition: _player.bufferedPosition,
        ),
      );
      _maybeHandleImplicitCompletion(position: position);
      if (_sponsorBlockEnabled) _checkSponsorSegment(position);
      if (_crossfadeEnabled) _maybeTriggerCrossfade(position);
    });
    _subProcessingState = _player.processingStateStream.distinct().listen((
      state,
    ) {
      if (state == ja.ProcessingState.completed) {
        unawaited(_handleQueueCompletion());
      }
    });
    // BUG #3 fix: removed _syncNativeCurrentIndex from playbackEventStream to
    // avoid 4-5 redundant calls per index change. The single authoritative
    // listener is currentIndexStream.distinct() below.
    _subPlaybackEvent = _player.playbackEventStream.listen((event) {
      _syncActiveAudioSource(forcePublish: true);
    });
    _subCurrentIndex = _player.currentIndexStream.distinct().listen(
      _handleNativeCurrentIndex,
    );
    _subSequenceState = _player.sequenceStateStream.listen((sequence) {
      _syncNativeSequenceState(sequence, forcePublish: true);
    });
    // BUG #3 fix: removed _syncNativeCurrentIndex from periodic timer — the
    // distinct() listener above is the sole authority for index sync.
    // BUG #2 fix: store the timer reference so it can be cancelled on stop().
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
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
  late ItunesPreviewResolver _itunesPreviewResolver;
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
  bool _isHandlingCompletion = false;
  Future<void> _playerMutationChain = Future<void>.value();

  late LrclibService _lrclibService;
  late SponsorBlockService _sponsorBlockService;
  bool _sponsorBlockEnabled = false;
  List<SponsorSegment> _currentSegments = [];
  bool _isSkippingSegment = false;

  bool _crossfadeEnabled = false;
  int _crossfadeDurationSeconds = 5;
  Timer? _crossfadeTimer;
  // BUG #2 fix: keep a reference to cancel the 900ms watchdog on stop().
  Timer? _watchdogTimer;
  double _crossfadeVolume = 1.0;
  bool _fadeInActive = false;

  // BUG #1 fix: store subscriptions so they can be cancelled in stop().
  late StreamSubscription<ja.PlayerState> _subPlayerState;
  late StreamSubscription<Duration?> _subDuration;
  late StreamSubscription<Duration> _subPosition;
  late StreamSubscription<ja.ProcessingState> _subProcessingState;
  late StreamSubscription<ja.PlaybackEvent> _subPlaybackEvent;
  late StreamSubscription<int?> _subCurrentIndex;
  late StreamSubscription<ja.SequenceState?> _subSequenceState;

  final Map<String, Future<ResolvedStream>> _resolveInFlight = {};
  final Map<String, _CachedResolvedStream> _resolvedStreamCache = {};
  final Map<String, String?> _resolvedSourceByTrackKey = {};
  String? _currentResolvedSource;

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
      // containsKey catches the null result case (track has no lyrics) so we
      // don't re-fetch on every call for known-empty tracks.
      if (_lyricsCache.containsKey(track.trackKey)) {
        return _lyricsCache[track.trackKey];
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
      // Store even null results so repeated calls don't re-hit the API.
      _lyricsCache[track.trackKey] = lyrics;
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
    if (sourceUrl.trim().isEmpty) {
      _broadcastLoadError(Exception('URL audio non disponible pour "$title"'));
      return;
    }
    _isLoadingTrack = true;
    final loadGeneration = ++_loadGeneration;
    ++_completionCallToken;
    _playerMutationChain = Future<void>.value();
    _queueTracks.clear();
    // BUG #4 fix: do NOT assign _currentIndex = 0 here — wait until setUrl
    // succeeds so a failed load doesn't leave _currentIndex pointing at an
    // invalid index. Reset to -1 so currentTrack returns null on error.
    _currentIndex = -1;
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
        // BUG #4 fix: assign _currentIndex only after setUrl succeeds.
        // BUG #12 fix: generation guard already checked above before this point.
        _currentIndex = 0;
        mediaItem.add(queue.value.first);
        _broadcastState(_player.playerState);
        // BUG #12 fix: guard again after each async step.
        if (loadGeneration != _loadGeneration) return;
        await _player.play();
        _broadcastState(_player.playerState);
      });
    } catch (error) {
      if (loadGeneration == _loadGeneration) {
        _broadcastLoadError(error);
      }
      rethrow;
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
    // Cancel all player stream subscriptions so the handler can be GC'd.
    await _subPlayerState.cancel();
    await _subDuration.cancel();
    await _subPosition.cancel();
    await _subProcessingState.cancel();
    await _subPlaybackEvent.cancel();
    await _subCurrentIndex.cancel();
    await _subSequenceState.cancel();
    // Cancel timers.
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    // Note: _localResolver.dispose() intentionally omitted — disposing
    // YoutubeExplode's HTTP client breaks the fallback resolver if stop() is
    // called and then playback resumes in the same session.
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

  Future<void> _loadAt(
    int index, {
    Duration? initialPosition,
    bool broadcastErrors = true,
  }) async {
    if (index < 0 || index >= _queueTracks.length) {
      return;
    }
    _isLoadingTrack = true;
    _cancelCrossfade();
    final loadGeneration = ++_loadGeneration;
    ++_completionCallToken;
    // BUG #13 fix: save the old index so we can restore it if setAudioSources
    // fails. We optimistically set _currentIndex = index here for UI/broadcast
    // purposes, but restore on a definitive load failure to keep the index
    // pointing at a valid (previously playing) track rather than a broken one.
    final previousIndex = _currentIndex;
    _currentIndex = index;
    _currentResolvedSource = null;
    _completionGuardTrackKey = null;
    _completionGuardAt = null;
    _pauseRequestedManually = false;
    final track = _queueTracks[index];
    // Sync état de lecture vers Convex (nouveau morceau)
    _syncPlaybackState(forcePosition: true);
    try {
      await _interruptCurrentPlayback();
      if (loadGeneration != _loadGeneration) return;
      // Emit without artwork immediately so the player UI appears during loading.
      // Artwork is intentionally omitted here to avoid triggering a preloadArtwork
      // download that would race with the authoritative emit after play().
      mediaItem.add(
        MediaItem(
          id: _mediaItemId(track, index: index),
          title: track.title,
          artist: track.artist,
          album: track.album,
          duration: track.durationMs == null
              ? null
              : Duration(milliseconds: track.durationMs!),
          extras: {
            'track_key': track.trackKey,
            'queue_index': index,
            if (track.externalId != null) 'external_id': track.externalId,
            if (track.provider.isNotEmpty) 'provider': track.provider,
          },
        ),
      );
      _broadcastLoadingState();
      final ja.AudioSource audioSource;
      try {
        audioSource = await _audioSourceForTrack(index, track);
      } catch (error) {
        if (broadcastErrors && loadGeneration == _loadGeneration) {
          _broadcastLoadError(error);
          // BUG #13 fix: restore the previous index on stream-resolution failure
          // so _currentIndex does not point at a broken track.
          _currentIndex = previousIndex;
        } else if (loadGeneration == _loadGeneration) {
          _currentIndex = previousIndex;
        }
        throw TrackLoadException(track: track, cause: error);
      }
      if (loadGeneration != _loadGeneration) return;
      // BUG #8 fix: reset progress tracking AFTER stream resolution succeeds,
      // not before, to avoid the watchdog falsely firing for the new track key
      // at position 0 during slow network resolution (≥4 s triggers dead-track).
      _lastProgressTrackKey = _queueTracks[index].trackKey;
      _lastProgressPositionMs = 0;
      _lastProgressAt = DateTime.now();
      _trackStartTime = DateTime.now();

      final startPosition = initialPosition ?? Duration.zero;
      try {
        await _player
            .setAudioSources(
              [audioSource],
              initialIndex: 0,
              initialPosition: startPosition,
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
                initialPosition: startPosition,
              )
              .timeout(_streamLoadTimeout);
        } on ja.PlayerInterruptedException {
          return;
        } catch (retryError) {
          try {
            final previewSource = await _audioSourceForTrack(
              index,
              track,
              forcePreview: true,
            );
            if (loadGeneration != _loadGeneration) return;
            await _player
                .setAudioSources(
                  [previewSource],
                  initialIndex: 0,
                  initialPosition: startPosition,
                )
                .timeout(_streamLoadTimeout);
          } on ja.PlayerInterruptedException {
            return;
          } catch (_) {
            if (broadcastErrors && loadGeneration == _loadGeneration) {
              _broadcastLoadError(
                retryError is TimeoutException ? retryError : error,
              );
              // BUG #13 fix: restore the previous index so _currentIndex does not
              // point at a track that failed to load. Only restore when we are
              // still the active generation (a newer _loadAt will set its own index).
              _currentIndex = previousIndex;
            } else if (loadGeneration == _loadGeneration) {
              _currentIndex = previousIndex;
            }
            throw TrackLoadException(
              track: track,
              cause: retryError is TimeoutException ? retryError : error,
            );
          }
        }
      }

      if (loadGeneration != _loadGeneration) return;
      _nativeQueueBaseIndex = index;
      _nativeQueuePreparedUntil = index;
      final newMediaItem = _toMediaItem(_queueTracks[index], index: index);
      queue.add(_buildQueueMediaItems());
      _broadcastState(_player.playerState);
      unawaited(preloadLyricsForTrack(track));
      if (!_isCurrentResolvedPreview) {
        unawaited(_prepareNativeUpcoming(index, loadGeneration));
      }
      final videoId = track.externalId ?? track.trackKey;
      if (_sponsorBlockEnabled &&
          RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
        unawaited(_loadSponsorSegments(videoId));
      } else {
        if (_sponsorBlockEnabled) {
          debugPrint(
            '[SponsorBlock] skipped — videoId "$videoId" does not match YouTube ID pattern',
          );
        }
        _currentSegments = [];
      }
      if (!_pauseRequestedManually) {
        if (_crossfadeEnabled) _startFadeIn();
        await _player.play();
      }
      // Emit mediaItem once, after play(), so the iOS audio session is active
      // when audio_service calls setMediaItem. preloadArtwork:true downloads
      // artwork synchronously before passing to iOS — a single emit here avoids
      // concurrent downloads that can complete out of order.
      if (loadGeneration == _loadGeneration) {
        mediaItem.add(newMediaItem);
        _broadcastState(_player.playerState);
      }
      // Second emit 600ms later for the gap between play() returning and iOS
      // session being fully live (Control Center refresh window).
      final capturedGen = loadGeneration;
      final capturedItem = newMediaItem;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (_loadGeneration == capturedGen) {
          mediaItem.add(capturedItem);
          _broadcastState(_player.playerState);
        }
      });
    } finally {
      // BUG #8 fix: a stale generation (loadGeneration < _loadGeneration) must
      // NOT reset _isLoadingTrack because a newer _loadAt() already claimed it.
      // An equal generation means we are the active load — always reset it so
      // the flag never gets stuck true if this generation throws or returns early.
      if (loadGeneration == _loadGeneration) {
        _isLoadingTrack = false;
      }
      // If loadGeneration < _loadGeneration, the newer call already set
      // _isLoadingTrack = true and will reset it in its own finally block.
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
    // BUG #7 fix: keep the invariant _nativeQueuePreparedUntil >= _nativeQueueBaseIndex
    // so that _prepareNativeUpcoming doesn't think sources were already prepared.
    // Both fields track the same "nothing has been prepared yet" state at interrupt.
    _nativeQueueBaseIndex = _currentIndex;
    _nativeQueuePreparedUntil = _currentIndex;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: _currentIndex < 0 ? null : _currentIndex,
        errorCode: null,
        errorMessage: null,
      ),
    );
  }

  Future<ja.AudioSource> _audioSourceForTrack(
    int index,
    Track track, {
    bool forceRefresh = false,
    bool forcePreview = false,
  }) async {
    final offline = await _database.findOfflineTrack(track.trackKey);
    final offlinePath = await _readyOfflinePath(offline);
    if (offlinePath != null) {
      return ja.AudioSource.uri(
        Uri.file(offlinePath),
        tag: _toMediaItem(track, index: index),
      );
    }

    if (forceRefresh) {
      _resolvedStreamCache.remove(track.trackKey);
    }
    final ResolvedStream resolved;
    if (forcePreview) {
      final preview =
          _previewResolvedStreamForTrack(track) ??
          await _itunesPreviewResolver
              .resolve(track)
              .timeout(_itunesPreviewLookupTimeout, onTimeout: () => null)
              .catchError((_) => null);
      if (preview == null) {
        throw FormatException('preview audio unavailable: ${track.trackKey}');
      }
      resolved = preview;
      _cacheResolvedTrack(track, resolved);
    } else {
      resolved = await _resolveTrack(track, reuseInFlight: false);
    }
    if (resolved.thumbnailUrl != null) {
      resolvedArtworkCache[track.trackKey] = resolved.thumbnailUrl!;
    }
    _resolvedSourceByTrackKey[track.trackKey] = resolved.source;
    if (index == _currentIndex) {
      _currentResolvedSource = resolved.source;
      _syncCurrentTrackMetadata(
        artworkUrl: resolved.thumbnailUrl,
        durationMs: resolved.durationMs,
      );
    } else if (index >= 0 && index < _queueTracks.length) {
      // Pre-populate resolved artwork + duration into _queueTracks for upcoming
      // tracks. This ensures that when gapless advance fires _publishQueueIndex,
      // _toMediaItem reads the correct artwork and duration — not null/stale values.
      final t = _queueTracks[index];
      Track updated = t;
      if (resolved.thumbnailUrl != null && t.artworkUrl == null) {
        updated = updated.copyWith(artworkUrl: resolved.thumbnailUrl);
      }
      if (resolved.durationMs != null && t.durationMs == null) {
        updated = updated.copyWith(durationMs: resolved.durationMs);
      }
      if (!identical(updated, t)) _queueTracks[index] = updated;
    }
    // Build tag from the (now-updated) track data so the native AudioSource tag
    // carries the resolved artwork URI — read by _syncNativeSequenceState on
    // gapless advance to route the correct queue index.
    final tagTrack = (index >= 0 && index < _queueTracks.length)
        ? _queueTracks[index]
        : track;
    return ja.AudioSource.uri(
      _streamUri(resolved.streamUrl),
      tag: _toMediaItem(tagTrack, index: index),
    );
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
    // BUG #2 fix: when no audio source is loaded the sequence is empty and
    // currentSource is null — skip the sync to avoid a potential crash inside
    // _syncNativeSequenceState when it tries to read currentSource?.tag.
    if (_player.audioSource == null) return;
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
    _currentResolvedSource =
        _resolvedSourceByTrackKey[_queueTracks[queueIndex].trackKey];
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
      if (_autoplayEnabled &&
          index >= 0 &&
          index < _queueTracks.length &&
          _queueTracks.length - index <= 3) {
        unawaited(_ensureAutoplayTail(seed: _queueTracks[index]));
      }
      return;
    }

    final sources = <ja.AudioSource>[];
    var preparedUntil = _nativeQueuePreparedUntil;
    for (var i = _nativeQueuePreparedUntil + 1; i <= targetIndex; i++) {
      if (loadGeneration != _loadGeneration) return;
      try {
        final source = await _audioSourceForTrack(i, _queueTracks[i]);
        if (_isPreviewSource(
          _resolvedSourceByTrackKey[_queueTracks[i].trackKey],
        )) {
          break;
        }
        sources.add(source);
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

    if (_autoplayEnabled &&
        index >= 0 &&
        index < _queueTracks.length &&
        _queueTracks.length - index <= 3) {
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
        // BUG #3 fix: bound each action so a hung operation never blocks the
        // mutation chain permanently.
        await action().timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw TimeoutException('_mutatePlayer action timeout'),
        );
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

  Future<ResolvedStream> _resolveTrack(
    Track track, {
    bool reuseInFlight = true,
  }) {
    final cached = _resolvedStreamCache[track.trackKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return Future.value(cached.stream);
    }

    if (reuseInFlight) {
      final inFlight = _resolveInFlight[track.trackKey];
      if (inFlight != null) return inFlight;
    }

    final future = _doResolveTrack(track);
    _resolveInFlight[track.trackKey] = future;
    return future.whenComplete(() {
      if (identical(_resolveInFlight[track.trackKey], future)) {
        _resolveInFlight.remove(track.trackKey);
      }
    });
  }

  Future<ResolvedStream> _doResolveTrack(Track track) async {
    try {
      final resolved = await _resolveBackendAndLocal(track);
      _cacheResolvedTrack(track, resolved);
      return resolved;
    } catch (_) {
      final preview = _previewResolvedStreamForTrack(track);
      if (preview != null) {
        _cacheResolvedTrack(track, preview);
        return preview;
      }

      final itunesPreview = await _itunesPreviewResolver
          .resolve(track)
          .timeout(_itunesPreviewLookupTimeout, onTimeout: () => null)
          .catchError((_) => null);
      if (itunesPreview != null) {
        _cacheResolvedTrack(track, itunesPreview);
        return itunesPreview;
      }
      rethrow;
    }
  }

  Future<ResolvedStream> _resolveBackendAndLocal(Track track) {
    final completer = Completer<ResolvedStream>();
    final errors = <Object>[];
    ResolvedStream? previewFallback;
    var pending = 2;

    void completeWith(ResolvedStream resolved) {
      pending -= 1;
      if (completer.isCompleted) return;
      if (!_isPreviewStream(resolved)) {
        completer.complete(resolved);
        return;
      }
      previewFallback ??= resolved;
      if (pending == 0) {
        completer.complete(previewFallback!);
      }
    }

    void fail(Object error) {
      errors.add(error);
      pending -= 1;
      if (pending == 0 && !completer.isCompleted) {
        final fallback = previewFallback;
        if (fallback != null) {
          completer.complete(fallback);
        } else {
          completer.completeError(errors.first);
        }
      }
    }

    unawaited(() async {
      try {
        final resolved = await _api
            .resolveTrack(track)
            .timeout(_serverResolveFastTimeout);
        completeWith(resolved);
      } catch (error) {
        fail(error);
      }
    }());
    unawaited(() async {
      try {
        final resolved = await _localResolver
            .resolve(track)
            .timeout(_fallbackResolveTimeout);
        completeWith(resolved);
      } catch (error) {
        fail(error);
      }
    }());

    return completer.future;
  }

  ResolvedStream? _previewResolvedStreamForTrack(Track track) {
    final previewUrl = track.previewUrl?.trim();
    if (previewUrl == null || previewUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(previewUrl);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    return ResolvedStream(
      streamUrl: previewUrl,
      title: track.title,
      artist: track.artist,
      source: 'itunes_preview',
      thumbnailUrl: track.artworkUrl ?? track.artistImageUrl,
      durationMs: null,
    );
  }

  void _cacheResolvedTrack(Track track, ResolvedStream resolved) {
    final ttl = _isPreviewStream(resolved)
        ? const Duration(seconds: 10)
        : _isManagedMediaUrl(resolved.streamUrl)
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

  bool _isPreviewStream(ResolvedStream stream) =>
      _isPreviewSource(stream.source);

  bool get _isCurrentResolvedPreview =>
      _isPreviewSource(_currentResolvedSource);

  bool _isPreviewSource(String? source) =>
      source?.endsWith('_preview') ?? false;

  Future<void> _prefetchQueueAround(int index) async {
    for (final offset in [1, 2]) {
      final nextIndex = index + offset;
      if (nextIndex >= 0 && nextIndex < _queueTracks.length) {
        unawaited(_resolveTrack(_queueTracks[nextIndex]));
      }
    }
    if (_autoplayEnabled &&
        index >= 0 &&
        index < _queueTracks.length &&
        _queueTracks.length - index <= 3) {
      unawaited(_ensureAutoplayTail(seed: _queueTracks[index]));
    }
  }

  Future<void> _handleQueueCompletion() async {
    // BUG #10 fix: guard against concurrent re-entry (processingStateStream +
    // watchdog timer can both fire for the same completion event).
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;
    final completingTrack = currentTrack;
    final completingPositionMs = _player.position.inMilliseconds;
    _recordPlaybackEventForTrack(
      'completed',
      completingTrack,
      completingPositionMs,
    );
    if (_isCurrentResolvedPreview) {
      _broadcastState(_player.playerState);
      _isHandlingCompletion = false;
      return;
    }
    final token = ++_completionCallToken;
    try {
      // Race guard: if gapless has upcoming tracks prepared, wait 350 ms for
      // currentIndexStream to fire. If _currentIndex advances in that window,
      // gapless handled the transition — bail out. If not, gapless failed
      // silently (expired URL, iOS throttled) — fall through and hard-load.
      if (_nativeQueuePreparedUntil > _currentIndex) {
        final capturedIndex = _currentIndex;
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (_currentIndex != capturedIndex) return;
      }
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
    } finally {
      // BUG #10 fix: always release the re-entry guard.
      _isHandlingCompletion = false;
    }
  }

  Future<void> _tryLoadNext(int token) async {
    // Try several consecutive tracks starting from the next one.
    // If a track fails to load (network / stream error), skip it and try the
    // next one rather than stopping — this prevents silence mid-playlist.
    final startIndex = _currentIndex + 1;
    for (int skip = 0; skip < _queueSkipLookahead; skip++) {
      final candidateIndex = startIndex + skip;
      if (candidateIndex >= _queueTracks.length) break;
      if (_completionCallToken != token) return;
      // Two attempts per candidate (transient network errors).
      for (int attempt = 0; attempt < 2; attempt++) {
        if (_completionCallToken != token) return;
        try {
          await _loadAt(candidateIndex, broadcastErrors: false);
          return;
        } catch (_) {
          // _loadAt increments _completionCallToken once at its start.
          // If it changed by exactly 1, that was our own call — stay in sync
          // so the next attempt's token check doesn't abort prematurely.
          // If it changed by more, an external action (manual skip) fired — abort.
          if (_completionCallToken > token + 1) return;
          token = _completionCallToken;
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
    // Safety net: if the sequenceStateStream subscription missed a gapless
    // advance event, the native player is already on the next track but
    // _currentIndex still points to the old one. Detect this by comparing the
    // tag on the currently-playing AudioSource against _currentIndex and call
    // _syncNativeSequenceState to recover. This fires at most every 900 ms so
    // it's a cheap catch-all for any missed subscription delivery.
    if (!_isLoadingTrack) {
      final seq = _player.sequenceState;
      final tag = seq.currentSource?.tag;
      if (tag is MediaItem) {
        final tagIndex = _queueIndexForMediaItem(
          tag,
          nativeIndex: seq.currentIndex,
        );
        if (tagIndex != null && tagIndex != _currentIndex) {
          _syncNativeSequenceState(seq, forcePublish: true);
        }
      }
    }
    final track = currentTrack;
    final duration = _effectiveTrackDuration();
    if (track == null ||
        duration == null ||
        duration <= const Duration(seconds: 1)) {
      return;
    }
    // BUG #14 note: _player.position is read synchronously here. After an
    // interruption (stop/seek), just_audio may briefly return a stale position
    // until the next position update event arrives. This is acceptable for the
    // watchdog heuristics (remaining-time checks) since they use a >=2 s slack.
    // If the position were required to be exact at this point, use Duration.zero
    // explicitly instead.
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
      // Re-resolve stream from scratch (URL expired / network cut).
      // Use _lastProgressPositionMs (updated every 900ms while playing) as the
      // resume position because _player.position may already be 0 in idle state.
      _playerMutationChain = Future<void>.value();
      final lastKnownMs = _lastProgressPositionMs ?? 0;
      final resumeAt = lastKnownMs > 500
          ? Duration(milliseconds: lastKnownMs)
          : null;
      unawaited(_loadAt(_currentIndex, initialPosition: resumeAt));
    } else {
      // BUG #10 fix: skip if _handleQueueCompletion is already running to
      // prevent the second watchdog tick from racing into it concurrently.
      if (_isHandlingCompletion) return;
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
      if (_resolvedSourceByTrackKey[track.trackKey] != null)
        'resolved_source': _resolvedSourceByTrackKey[track.trackKey],
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
    // Also refresh playbackState so the UI position/duration display updates
    // atomically with the new duration — without this the slider stays at
    // 0:00 / 0:00 until the next positionStream tick.
    _broadcastState(_player.playerState);
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
        errorCode: null,
        errorMessage: null,
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
        errorCode: null,
        errorMessage: null,
      ),
    );
  }

  void _broadcastLoadError(Object error) {
    if (_player.playing &&
        _player.audioSource != null &&
        _player.processingState == ja.ProcessingState.ready) {
      _broadcastState(_player.playerState);
      return;
    }
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
    // Invalidate the native upcoming source buffer so it's rebuilt in the new
    // order. Without this, just_audio's internal sequence retains the old order
    // and gapless advance plays the wrong track.
    if (_nativeQueuePreparedUntil > _currentIndex) {
      final currentNativeIndex = _currentIndex - _nativeQueueBaseIndex;
      final preparedCount = _nativeQueuePreparedUntil - _currentIndex;
      unawaited(
        _mutatePlayer(() async {
          for (var i = preparedCount; i >= 1; i--) {
            try {
              await _player.removeAudioSourceAt(currentNativeIndex + i);
            } catch (_) {}
          }
          _nativeQueuePreparedUntil = _currentIndex;
        }),
      );
    }
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
        unawaited(() async {
          try {
            await _player.seek(seg.end);
          } finally {
            _isSkippingSegment = false;
          }
        }());
        return;
      }
    }
  }

  Future<void> _loadSponsorSegments(String videoId) async {
    try {
      _currentSegments = await _sponsorBlockService.fetchSegments(videoId);
    } catch (error) {
      // BUG #9 fix: log SponsorBlock fetch failures so they are visible in
      // debug output rather than silently degrading.
      debugPrint(
        '[SponsorBlock] failed to load segments for "$videoId": $error',
      );
      _currentSegments = [];
    }
  }

  void _maybeTriggerCrossfade(Duration position) {
    if (_crossfadeTimer != null) return;
    if (_isCurrentResolvedPreview) return;
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
    // Capture the timer reference locally so the callback can guard against
    // being orphaned if _startFadeOut is called again before this timer fires
    // its final tick (BUG #15 fix).
    Timer? myTimer;
    myTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (_crossfadeTimer != myTimer) {
        myTimer?.cancel();
        return;
      }
      final duration = _effectiveTrackDuration();
      final pos = _player.position;
      if (duration == null || !_crossfadeEnabled) {
        _cancelCrossfade();
        return;
      }
      final remaining = duration - pos;
      if (remaining <= Duration.zero) {
        myTimer?.cancel();
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
    _crossfadeTimer = myTimer;
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
    // BUG #6 fix: use _player.position (authoritative current position) instead
    // of playbackState.value.position which may be an extrapolated/stale value.
    final positionMs = _player.position.inMilliseconds;

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
    // BUG #6 fix: use _player.position (synchronous) for fresh position value.
    _recordPlaybackEventForTrack(
      eventType,
      currentTrack,
      _player.position.inMilliseconds,
    );
  }

  /// Records a playback event for an explicitly supplied [track] and
  /// [positionMs]. Use this overload when the current state may have already
  /// advanced to the next track (e.g. at queue-completion time).
  void _recordPlaybackEventForTrack(
    String eventType,
    Track? track,
    int positionMs,
  ) {
    final convex = _convexService;
    final userId = _convexUserId;
    if (convex == null || userId == null || track == null) return;

    final durationMs = track.durationMs ?? 0;
    // BUG #15 fix: if _trackStartTime is null (handler was constructed but no
    // track has started yet), fall back to positionMs as the listened duration.
    // Log a warning so the missing start time is visible during debugging.
    // Also clamp to 0 so a stale/negative value never propagates to Convex.
    final rawListenedMs = _trackStartTime != null
        ? DateTime.now().difference(_trackStartTime!).inMilliseconds
        : positionMs;
    if (_trackStartTime == null) {
      debugPrint(
        '[JojoAudioHandler] _trackStartTime was null when recording '
        '"$eventType" for "${track.title}" — using positionMs ($positionMs ms) '
        'as listenedMs fallback',
      );
    }
    final listenedMs = rawListenedMs < 0 ? 0 : rawListenedMs;
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
