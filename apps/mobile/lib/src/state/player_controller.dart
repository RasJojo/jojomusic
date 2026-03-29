import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'home_controller.dart';
import 'providers.dart';

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return ref.watch(audioHandlerProvider).playbackState;
});

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return ref.watch(audioHandlerProvider).mediaItem;
});

final currentQueueProvider = StreamProvider<List<MediaItem>>((ref) {
  return ref.watch(audioHandlerProvider).queue;
});

final playerControllerProvider = Provider<PlayerController>((ref) {
  return PlayerController(ref);
});

final pendingTrackKeyListenable = ValueNotifier<String?>(null);

class PlayerController {
  const PlayerController(this.ref);

  final Ref ref;

  Future<void> playTrack(Track track, {required List<Track> queue}) async {
    final handler = ref.read(audioHandlerProvider);
    final index = queue.indexWhere((item) => item.trackKey == track.trackKey);
    pendingTrackKeyListenable.value = track.trackKey;
    unawaited(handler.preloadLyricsForTrack(track));
    try {
      await handler.loadQueue(queue, initialIndex: index < 0 ? 0 : index);
      pendingTrackKeyListenable.value = null;
      unawaited(
        ref
            .read(apiProvider)
            .reportPlayback(eventType: 'play_started', track: track),
      );
      ref.invalidate(homeControllerProvider);
    } finally {
      pendingTrackKeyListenable.value = null;
    }
  }

  Future<void> playPodcastEpisode(PodcastEpisode episode) async {
    if (episode.audioUrl == null || episode.audioUrl!.isEmpty) {
      return;
    }
    await ref
        .read(audioHandlerProvider)
        .playDirectSource(
          id: episode.episodeKey,
          title: episode.title,
          artist: episode.publisher ?? episode.podcastTitle,
          album: episode.podcastTitle,
          artworkUrl: episode.artworkUrl,
          durationMs: episode.durationSeconds == null
              ? null
              : episode.durationSeconds! * 1000,
          sourceUrl: episode.audioUrl!,
        );
    await ref
        .read(apiProvider)
        .reportPlayback(
          eventType: 'play_started',
          track: Track(
            trackKey: episode.episodeKey,
            title: episode.title,
            artist: episode.publisher ?? episode.podcastTitle,
            album: episode.podcastTitle,
            artworkUrl: episode.artworkUrl,
            durationMs: episode.durationSeconds == null
                ? null
                : episode.durationSeconds! * 1000,
            provider: 'podcast',
            externalId: episode.externalUrl,
          ),
        );
    ref.invalidate(homeControllerProvider);
  }

  Future<void> togglePlayPause() async {
    final state = ref.read(playbackStateProvider).asData?.value;
    final handler = ref.read(audioHandlerProvider);
    if (state?.playing ?? false) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> skipNext() => ref.read(audioHandlerProvider).skipToNext();

  Future<void> skipPrevious() =>
      ref.read(audioHandlerProvider).skipToPrevious();

  Future<void> seek(Duration position) =>
      ref.read(audioHandlerProvider).seek(position);

  Future<void> seekRelative(Duration delta) async {
    final playback = ref.read(playbackStateProvider).asData?.value;
    final currentItem = ref.read(currentMediaItemProvider).asData?.value;
    if (playback == null || currentItem == null) {
      return;
    }
    final maxPosition = currentItem.duration ?? Duration.zero;
    var nextPosition = playback.updatePosition + delta;
    if (nextPosition < Duration.zero) {
      nextPosition = Duration.zero;
    }
    if (maxPosition > Duration.zero && nextPosition > maxPosition) {
      nextPosition = maxPosition;
    }
    await seek(nextPosition);
  }

  Future<void> playQueueItem(int index) =>
      ref.read(audioHandlerProvider).skipToQueueItem(index);

  Track? currentQueueTrack() => ref.read(audioHandlerProvider).currentTrack;

  Future<LyricsData?> fetchLyricsForCurrentTrack() async {
    final mediaItem = ref.read(currentMediaItemProvider).asData?.value;
    if (mediaItem == null) {
      return null;
    }
    return fetchLyricsForMediaItem(mediaItem, forceRefresh: true);
  }

  Future<LyricsData?> fetchLyricsForMediaItem(
    MediaItem mediaItem, {
    bool forceRefresh = false,
  }) {
    final track = Track(
      trackKey: mediaItem.id,
      title: mediaItem.title,
      artist: mediaItem.artist ?? 'Unknown artist',
      album: mediaItem.album,
      artworkUrl: mediaItem.artUri?.toString(),
      durationMs: mediaItem.duration?.inMilliseconds,
    );
    return ref
        .read(audioHandlerProvider)
        .fetchLyricsForTrack(track, forceRefresh: forceRefresh);
  }

  Future<void> preloadLyricsForTrack(Track track) {
    return ref.read(audioHandlerProvider).preloadLyricsForTrack(track);
  }

  Future<void> prewarmTrack(Track track) {
    return ref.read(audioHandlerProvider).prewarmTrack(track);
  }

  Future<void> preloadLyricsForMediaItem(MediaItem mediaItem) {
    final track = Track(
      trackKey: mediaItem.id,
      title: mediaItem.title,
      artist: mediaItem.artist ?? 'Unknown artist',
      album: mediaItem.album,
      artworkUrl: mediaItem.artUri?.toString(),
      durationMs: mediaItem.duration?.inMilliseconds,
    );
    return preloadLyricsForTrack(track);
  }
}
