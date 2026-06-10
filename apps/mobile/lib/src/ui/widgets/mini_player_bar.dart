import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../models/app_models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../../state/settings_controller.dart';
import '../lyrics_screen.dart';
import '../queue_screen.dart';
import '../settings_screen.dart';
import '../theme/jojo_theme.dart';
import 'jojo_surfaces.dart';
import 'media_artwork.dart';
import 'track_playlist_picker_sheet.dart';

// ─── Mini Player Bar ──────────────────────────────────────────────────────────

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final library = ref.watch(libraryControllerProvider).asData?.value;

    if (mediaItem.asData?.value == null) {
      return const SizedBox.shrink();
    }

    final item = mediaItem.asData!.value!;
    final playback = playbackState.asData?.value;
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final isPlaying = playback?.playing ?? false;
    final isError = playback?.processingState == AudioProcessingState.error;
    final subtitle = isError
        ? playback?.errorMessage ?? 'Lecture impossible'
        : item.artist ?? '';
    final isLiked =
        library?.likes.any((t) => t.trackKey == mediaItemTrackKey(item)) ??
        false;

    final maxMs = (item.duration?.inMilliseconds ?? 0).toDouble();
    final currentMs =
        (playbackState.asData?.value.updatePosition.inMilliseconds ?? 0)
            .toDouble();
    final progress = maxMs > 0 ? (currentMs / maxMs).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withValues(alpha: 0.09),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _openPlayerSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 390;
                        final artworkSize = compact ? 42.0 : 50.0;
                        final iconSize = compact ? 24.0 : 28.0;
                        final playSize = compact ? 44.0 : 50.0;

                        return Row(
                          children: [
                            MediaArtwork(
                              url: item.artUri?.toString(),
                              size: artworkSize,
                              borderRadius: compact ? 13 : 15,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: isError
                                              ? JojoColors.danger
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: currentTrack == null
                                  ? null
                                  : () => ref
                                        .read(
                                          libraryControllerProvider.notifier,
                                        )
                                        .toggleLike(currentTrack),
                              icon: Icon(
                                isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: iconSize,
                                color: isLiked ? const Color(0xFFFF6B8E) : null,
                              ),
                            ),
                            Container(
                              width: playSize,
                              height: playSize,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: JojoColors.primary,
                              ),
                              child: IconButton(
                                onPressed: () => ref
                                    .read(playerControllerProvider)
                                    .togglePlayPause(),
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: compact ? 24 : 28,
                                ),
                                color: Colors.black,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: currentTrack == null
                                  ? null
                                  : () => showTrackPlaylistPickerSheet(
                                      context,
                                      ref,
                                      track: currentTrack,
                                      preferDownloaded: true,
                                    ),
                              icon: Icon(Icons.add_rounded, size: iconSize),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // Progress bar
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white10,
                  color: JojoColors.primary,
                  minHeight: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPlayerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) => const _PlayerSheet(),
    );
  }
}

// ─── Desktop Player Panel ─────────────────────────────────────────────────────

class DesktopPlayerPanel extends ConsumerStatefulWidget {
  const DesktopPlayerPanel({super.key, this.width = 340});

  final double width;

  @override
  ConsumerState<DesktopPlayerPanel> createState() => _DesktopPlayerPanelState();
}

class _DesktopPlayerPanelState extends ConsumerState<DesktopPlayerPanel> {
  double? _dragValueMs;
  bool _openingLyrics = false;
  bool _openingQueue = false;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playback = ref.watch(playbackStateProvider).asData?.value;
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final library = ref.watch(libraryControllerProvider).asData?.value;
    final shuffleActive =
        ref.watch(shuffleActiveProvider).asData?.value ?? false;
    final repeatMode =
        ref.watch(repeatModeProvider).asData?.value ??
        AudioServiceRepeatMode.none;
    final isError = playback?.processingState == AudioProcessingState.error;
    final subtitle = isError
        ? playback?.errorMessage ?? 'Lecture impossible'
        : mediaItem?.artist ?? '';

    return Container(
      width: widget.width,
      decoration: const BoxDecoration(
        color: Color(0xE6000000),
        border: Border(right: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: mediaItem == null || playback == null
              ? const _DesktopPlayerPlaceholder()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final maxMs = (mediaItem.duration?.inMilliseconds ?? 1)
                        .clamp(1, 1 << 31);
                    final currentMs = playback.updatePosition.inMilliseconds
                        .clamp(0, maxMs);
                    final sliderValue = (_dragValueMs ?? currentMs.toDouble())
                        .clamp(0.0, maxMs.toDouble())
                        .toDouble();
                    final isLiked =
                        currentTrack != null &&
                        (library?.isLiked(currentTrack) ?? false);
                    final artworkSize = math.min(
                      constraints.maxWidth - 40,
                      constraints.maxHeight > 920 ? 288.0 : 248.0,
                    );

                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        Text(
                          'Lecture en cours',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: JojoColors.mutedStrong,
                                letterSpacing: 0.2,
                              ),
                        ),
                        const SizedBox(height: 14),
                        JojoSurfaceCard(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              MediaArtwork(
                                url: mediaItem.artUri?.toString(),
                                size: artworkSize,
                                borderRadius: 30,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                mediaItem.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: isError
                                          ? JojoColors.danger
                                          : JojoColors.mutedStrong,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        JojoSurfaceCard(
                          child: Column(
                            children: [
                              Slider(
                                value: sliderValue,
                                max: maxMs.toDouble(),
                                onChanged: (v) =>
                                    setState(() => _dragValueMs = v),
                                onChangeEnd: (v) async {
                                  setState(() => _dragValueMs = null);
                                  await ref
                                      .read(playerControllerProvider)
                                      .seek(Duration(milliseconds: v.round()));
                                },
                              ),
                              Row(
                                children: [
                                  Text(
                                    _formatDuration(
                                      Duration(
                                        milliseconds: sliderValue.round(),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(
                                      Duration(milliseconds: maxMs),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _DesktopIconButton(
                                    icon: shuffleActive
                                        ? Icons.shuffle_on_rounded
                                        : Icons.shuffle_rounded,
                                    color: shuffleActive
                                        ? JojoColors.primary
                                        : null,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .toggleShuffle(),
                                  ),
                                  _DesktopIconButton(
                                    icon: Icons.skip_previous_rounded,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .skipPrevious(),
                                  ),
                                  Container(
                                    width: 58,
                                    height: 58,
                                    decoration: const BoxDecoration(
                                      color: JojoColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      onPressed: () => ref
                                          .read(playerControllerProvider)
                                          .togglePlayPause(),
                                      icon: Icon(
                                        playback.playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 30,
                                      ),
                                      color: Colors.black,
                                    ),
                                  ),
                                  _DesktopIconButton(
                                    icon: Icons.skip_next_rounded,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .skipNext(),
                                  ),
                                  _DesktopIconButton(
                                    icon:
                                        repeatMode == AudioServiceRepeatMode.one
                                        ? Icons.repeat_one_rounded
                                        : Icons.repeat_rounded,
                                    color:
                                        repeatMode !=
                                            AudioServiceRepeatMode.none
                                        ? JojoColors.primary
                                        : null,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .cycleRepeatMode(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Compact action icons row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              onPressed: currentTrack == null
                                  ? null
                                  : () => ref
                                        .read(
                                          libraryControllerProvider.notifier,
                                        )
                                        .toggleLike(currentTrack),
                              icon: Icon(
                                isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: isLiked
                                    ? const Color(0xFFFF6B8E)
                                    : JojoColors.mutedStrong,
                              ),
                              iconSize: 24,
                            ),
                            IconButton(
                              onPressed: currentTrack == null
                                  ? null
                                  : () => showTrackPlaylistPickerSheet(
                                      context,
                                      ref,
                                      track: currentTrack,
                                      preferDownloaded: true,
                                    ),
                              icon: const Icon(Icons.playlist_add_rounded),
                              iconSize: 24,
                              color: JojoColors.mutedStrong,
                            ),
                            IconButton(
                              onPressed: _openingQueue
                                  ? null
                                  : () => _openQueuePage(context),
                              icon: const Icon(Icons.queue_music_rounded),
                              iconSize: 24,
                              color: JojoColors.mutedStrong,
                            ),
                            IconButton(
                              onPressed: _openingLyrics
                                  ? null
                                  : () => _openLyricsPage(context, mediaItem),
                              icon: const Icon(Icons.lyrics_rounded),
                              iconSize: 24,
                              color: JojoColors.mutedStrong,
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                              icon: const Icon(Icons.tune_rounded),
                              iconSize: 24,
                              color: JojoColors.mutedStrong,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Lyrics preview card
                        _LyricsPreview(
                          mediaItem: mediaItem,
                          playback: playback,
                          onTap: () => _openLyricsPage(context, mediaItem),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _openLyricsPage(
    BuildContext context,
    MediaItem mediaItem,
  ) async {
    if (_openingLyrics) return;
    setState(() => _openingLyrics = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => LyricsScreen(mediaItem: mediaItem),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingLyrics = false);
    }
  }

  Future<void> _openQueuePage(BuildContext context) async {
    if (_openingQueue) return;
    setState(() => _openingQueue = true);
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const QueueScreen()));
    } finally {
      if (mounted) setState(() => _openingQueue = false);
    }
  }
}

class _DesktopPlayerPlaceholder extends StatelessWidget {
  const _DesktopPlayerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.multitrack_audio_rounded,
            size: 36,
            color: JojoColors.mutedStrong,
          ),
          const SizedBox(height: 18),
          Text(
            'Lance un titre',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Sur grand écran, le lecteur reste ici en permanence pour garder la navigation et les paroles visibles en même temps.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DesktopIconButton extends StatelessWidget {
  const _DesktopIconButton({
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 28,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(icon, color: color ?? Colors.white, size: 24),
      ),
    );
  }
}

// ─── Full Player Sheet ────────────────────────────────────────────────────────

class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet();

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  double? _dragValueMs;
  bool _openingQueue = false;
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playback = ref.watch(playbackStateProvider).asData?.value;

    if (mediaItem == null || playback == null) {
      return const SizedBox(height: 240);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Tab indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TabDot(active: _currentPage == 0, label: 'Lecteur'),
                const SizedBox(width: 16),
                _TabDot(active: _currentPage == 1, label: 'Paroles'),
              ],
            ),
          ),

          // PageView: player / lyrics
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (p) => setState(() => _currentPage = p),
              children: [
                _PlayerPage(
                  mediaItem: mediaItem,
                  playback: playback,
                  accentColor: Colors.white,
                  dragValueMs: _dragValueMs,
                  onDragValueChanged: (v) => setState(() => _dragValueMs = v),
                  onDragEnd: (v) async {
                    setState(() => _dragValueMs = null);
                    await ref
                        .read(playerControllerProvider)
                        .seek(Duration(milliseconds: v.round()));
                  },
                  openingQueue: _openingQueue,
                  onOpenQueue: () => _openQueuePage(context),
                  onOpenLyrics: () => _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                ),
                _LyricsPage(mediaItem: mediaItem),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQueuePage(BuildContext context) async {
    if (_openingQueue) return;
    setState(() => _openingQueue = true);
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const QueueScreen()));
    } finally {
      if (mounted) setState(() => _openingQueue = false);
    }
  }
}

// ─── Player Page ──────────────────────────────────────────────────────────────

class _PlayerPage extends ConsumerStatefulWidget {
  const _PlayerPage({
    required this.mediaItem,
    required this.playback,
    required this.accentColor,
    required this.dragValueMs,
    required this.onDragValueChanged,
    required this.onDragEnd,
    required this.openingQueue,
    required this.onOpenQueue,
    required this.onOpenLyrics,
  });

  final MediaItem mediaItem;
  final PlaybackState playback;
  final Color accentColor;
  final double? dragValueMs;
  final ValueChanged<double> onDragValueChanged;
  final ValueChanged<double> onDragEnd;
  final bool openingQueue;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;

  @override
  ConsumerState<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<_PlayerPage> {
  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final videoId = currentTrack?.externalId ?? '';
    final canvasUrl = videoId.isNotEmpty
        ? ref.watch(canvasUrlProvider(videoId)).asData?.value
        : null;
    final library = ref.watch(libraryControllerProvider).asData?.value;
    final shuffleActive =
        ref.watch(shuffleActiveProvider).asData?.value ?? false;
    final repeatMode =
        ref.watch(repeatModeProvider).asData?.value ??
        AudioServiceRepeatMode.none;
    final sleepEnd = ref.watch(sleepTimerProvider);

    final isPlaying = widget.playback.playing;
    final isError =
        widget.playback.processingState == AudioProcessingState.error;
    final subtitle = isError
        ? widget.playback.errorMessage ?? 'Lecture impossible'
        : widget.mediaItem.artist ?? '';
    final isLiked =
        currentTrack != null && (library?.isLiked(currentTrack) ?? false);
    final maxMs = (widget.mediaItem.duration?.inMilliseconds ?? 1).clamp(
      1,
      1 << 31,
    );
    final currentMs = widget.playback.updatePosition.inMilliseconds.clamp(
      0,
      maxMs,
    );
    final sliderValue = (widget.dragValueMs ?? currentMs.toDouble())
        .clamp(0.0, maxMs.toDouble())
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 400;
        final vCompact = constraints.maxHeight < 700;
        final bottomPad = MediaQuery.of(context).padding.bottom + 16;

        // ── Artwork widget ───────────────────────────────────────────────────
        final artworkSize = math.min(
          compact ? constraints.maxWidth * 0.72 : constraints.maxWidth * 0.78,
          vCompact ? 210.0 : 300.0,
        );

        final artworkWidget = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withAlpha(100),
                blurRadius: 50,
                spreadRadius: 5,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: AnimatedScale(
            scale: isPlaying ? 1.0 : 0.92,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: MediaArtwork(
                url: widget.mediaItem.artUri?.toString(),
                size: artworkSize,
                borderRadius: 0,
              ),
            ),
          ),
        );

        // ── Controls column (shared between layouts) ─────────────────────────
        Widget controlsColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title + Artist + Like
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.mediaItem.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: isError
                                  ? JojoColors.danger
                                  : JojoColors.mutedStrong,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: IconButton(
                    key: ValueKey(isLiked),
                    onPressed: currentTrack == null
                        ? null
                        : () => ref
                              .read(libraryControllerProvider.notifier)
                              .toggleLike(currentTrack),
                    iconSize: 30,
                    icon: Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isLiked
                          ? const Color(0xFFFF6B8E)
                          : JojoColors.muted,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: vCompact ? 14 : 20),

            // Progress Slider
            Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 18,
                    ),
                    activeTrackColor: JojoColors.primary,
                    inactiveTrackColor: const Color(0x26FFFFFF),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white12,
                  ),
                  child: Slider(
                    value: sliderValue,
                    max: maxMs.toDouble(),
                    onChanged: widget.onDragValueChanged,
                    onChangeEnd: widget.onDragEnd,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(
                          Duration(milliseconds: sliderValue.round()),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        _formatDuration(Duration(milliseconds: maxMs)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: vCompact ? 12 : 18),

            // Controls: Shuffle | Prev | Play | Next | Repeat
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ControlIconButton(
                  icon: Icons.shuffle_rounded,
                  onPressed: () =>
                      ref.read(playerControllerProvider).toggleShuffle(),
                  active: shuffleActive,
                  size: 28,
                ),
                _ControlIconButton(
                  icon: Icons.skip_previous_rounded,
                  onPressed: () =>
                      ref.read(playerControllerProvider).skipPrevious(),
                  size: 38,
                ),
                GestureDetector(
                  onTap: () =>
                      ref.read(playerControllerProvider).togglePlayPause(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: JojoColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: JojoColors.primary.withAlpha(80),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 42,
                      color: Colors.black,
                    ),
                  ),
                ),
                _ControlIconButton(
                  icon: Icons.skip_next_rounded,
                  onPressed: () =>
                      ref.read(playerControllerProvider).skipNext(),
                  size: 38,
                ),
                _ControlIconButton(
                  icon: repeatMode == AudioServiceRepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  onPressed: () =>
                      ref.read(playerControllerProvider).cycleRepeatMode(),
                  active: repeatMode != AudioServiceRepeatMode.none,
                  size: 28,
                ),
              ],
            ),

            SizedBox(height: vCompact ? 16 : 20),

            // Action icons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: currentTrack == null
                      ? null
                      : () => showTrackPlaylistPickerSheet(
                          context,
                          ref,
                          track: currentTrack,
                          preferDownloaded: true,
                        ),
                  icon: const Icon(Icons.playlist_add_rounded),
                  iconSize: 26,
                  color: JojoColors.mutedStrong,
                  tooltip: 'Ajouter à une playlist',
                ),
                IconButton(
                  onPressed: widget.openingQueue ? null : widget.onOpenQueue,
                  icon: const Icon(Icons.queue_music_rounded),
                  iconSize: 26,
                  color: JojoColors.mutedStrong,
                  tooltip: 'File de lecture',
                ),
                IconButton(
                  onPressed: widget.onOpenLyrics,
                  icon: const Icon(Icons.lyrics_rounded),
                  iconSize: 26,
                  color: JojoColors.mutedStrong,
                  tooltip: 'Paroles',
                ),
                _MoreOptionsButton(sleepEnd: sleepEnd, iconOnly: true),
              ],
            ),

            SizedBox(height: vCompact ? 8 : 14),

            // Lyrics preview card
            _LyricsPreview(
              mediaItem: widget.mediaItem,
              playback: widget.playback,
              onTap: widget.onOpenLyrics,
            ),
          ],
        );

        // ── Layout : artwork en haut, contrôles en bas ──────────────────────
        final hPad = compact ? 20.0 : 28.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (canvasUrl != null) _CanvasBackground(url: canvasUrl),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                hPad,
                vCompact ? 8 : 16,
                hPad,
                bottomPad,
              ),
              child: Column(
                children: [
                  Center(child: artworkWidget),
                  SizedBox(height: vCompact ? 20 : 28),
                  controlsColumn,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Canvas Background ────────────────────────────────────────────────────────

class _CanvasBackground extends StatefulWidget {
  const _CanvasBackground({required this.url});
  final String url;

  @override
  State<_CanvasBackground> createState() => _CanvasBackgroundState();
}

class _CanvasBackgroundState extends State<_CanvasBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_CanvasBackground old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _init();
    }
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await ctrl.initialize();
      ctrl
        ..setLooping(true)
        ..setVolume(0);
      await ctrl.play();
      if (mounted) {
        setState(() {
          _controller = ctrl;
          _ready = true;
        });
      } else {
        ctrl.dispose();
      }
    } catch (_) {
      ctrl.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (!_ready || ctrl == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: Opacity(
        opacity: 0.28,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        ),
      ),
    );
  }
}

// ─── Lyrics Page (in player sheet) ───────────────────────────────────────────

class _LyricsPage extends ConsumerStatefulWidget {
  const _LyricsPage({required this.mediaItem});

  final MediaItem mediaItem;

  @override
  ConsumerState<_LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends ConsumerState<_LyricsPage> {
  late Future<LyricsData?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = ref
        .read(playerControllerProvider)
        .fetchLyricsForMediaItem(widget.mediaItem);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsData?>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: JojoColors.primary),
          );
        }
        final lyrics = snapshot.data;
        final hasSynced = lyrics?.syncedLyrics?.trim().isNotEmpty ?? false;
        if (lyrics == null ||
            (lyrics.plainLyrics?.isEmpty ?? true) && !hasSynced) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lyrics_outlined,
                    size: 48,
                    color: JojoColors.muted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune parole disponible',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: JojoColors.mutedStrong,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (hasSynced) {
          return _SyncedLyricsView(lyrics: lyrics);
        }
        return _PlainLyricsView(lyrics: lyrics);
      },
    );
  }
}

// ─── Synced (LRC) Lyrics View ─────────────────────────────────────────────────

class _LrcLine {
  const _LrcLine({required this.timestamp, required this.text});
  final Duration timestamp;
  final String text;
}

List<_LrcLine> _parseLrc(String lrc) {
  final lines = <_LrcLine>[];
  for (final rawLine in lrc.split('\n')) {
    final match = RegExp(r'\[(\d+):(\d+)[\.:](\d+)\](.*)').firstMatch(rawLine);
    if (match == null) continue;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final subRaw = match.group(3)!.padRight(2, '0');
    final hundredths = int.parse(subRaw.substring(0, 2));
    final text = match.group(4)!.trim();
    if (text.isEmpty) continue;
    lines.add(
      _LrcLine(
        timestamp: Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: hundredths * 10,
        ),
        text: text,
      ),
    );
  }
  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return lines;
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  const _SyncedLyricsView({required this.lyrics});
  final LyricsData lyrics;

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  late final List<_LrcLine> _lines;
  late final List<GlobalKey> _lineKeys;
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _lines = _parseLrc(widget.lyrics.syncedLyrics ?? '');
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(playbackStateProvider).asData?.value.updatePosition ??
        Duration.zero;

    // Find current line
    int newIndex = -1;
    for (int i = _lines.length - 1; i >= 0; i--) {
      if (position >= _lines[i].timestamp) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }

    if (_lines.isEmpty) {
      return _PlainLyricsView(lyrics: widget.lyrics);
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 28),
      child: Column(
        children: [
          for (int i = 0; i < _lines.length; i++) ...[
            GestureDetector(
              key: _lineKeys[i],
              onTap: () =>
                  ref.read(playerControllerProvider).seek(_lines[i].timestamp),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                style:
                    (Theme.of(context).textTheme.titleLarge ??
                            const TextStyle())
                        .copyWith(
                          color: i == _currentIndex
                              ? Colors.white
                              : Colors.white38,
                          fontWeight: i == _currentIndex
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: i == _currentIndex ? 22 : 18,
                          height: 1.4,
                        ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(_lines[i].text, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _scrollToCurrent() {
    if (_currentIndex < 0 || !mounted) return;
    final key = _lineKeys[_currentIndex];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.38,
      );
    }
  }
}

// ─── Plain Lyrics View ────────────────────────────────────────────────────────

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.lyrics});
  final LyricsData lyrics;

  @override
  Widget build(BuildContext context) {
    final text = (lyrics.plainLyrics?.trim().isNotEmpty ?? false)
        ? lyrics.plainLyrics!
        : (lyrics.syncedLyrics ?? '')
              .split('\n')
              .map((l) => l.replaceAll(RegExp(r'\[[^\]]+\]'), '').trim())
              .where((l) => l.isNotEmpty)
              .join('\n');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: JojoColors.mutedStrong,
          height: 1.8,
        ),
      ),
    );
  }
}

class _RemainingTime extends StatefulWidget {
  const _RemainingTime({required this.sleepEnd});
  final DateTime sleepEnd;

  @override
  State<_RemainingTime> createState() => _RemainingTimeState();
}

class _RemainingTimeState extends State<_RemainingTime> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.sleepEnd.difference(DateTime.now());
    if (remaining.isNegative) return const Text('0:00');
    final m = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = remaining.inHours;
    return Text(h > 0 ? '$h:$m:$s' : '$m:$s');
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _TabDot extends StatelessWidget {
  const _TabDot({required this.active, required this.label});
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: active ? Colors.white : Colors.white38,
          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          letterSpacing: active ? 0.5 : 0,
        ),
      ),
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  const _ControlIconButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.size = 28,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      iconSize: size,
      icon: Icon(icon, color: active ? Colors.white : JojoColors.muted),
    );
  }
}

// ─── Lyrics Preview ──────────────────────────────────────────────────────────

class _LyricsPreview extends ConsumerStatefulWidget {
  const _LyricsPreview({
    required this.mediaItem,
    required this.playback,
    required this.onTap,
  });
  final MediaItem mediaItem;
  final PlaybackState playback;
  final VoidCallback onTap;

  @override
  ConsumerState<_LyricsPreview> createState() => _LyricsPreviewState();
}

class _LyricsPreviewState extends ConsumerState<_LyricsPreview> {
  Future<LyricsData?>? _lyricsFuture;
  String? _lastTrackId;

  @override
  void didUpdateWidget(_LyricsPreview old) {
    super.didUpdateWidget(old);
    final newId = widget.mediaItem.id;
    if (newId != _lastTrackId) {
      _lastTrackId = newId;
      _lyricsFuture = ref
          .read(playerControllerProvider)
          .fetchLyricsForMediaItem(widget.mediaItem);
    }
  }

  @override
  void initState() {
    super.initState();
    _lastTrackId = widget.mediaItem.id;
    _lyricsFuture = ref
        .read(playerControllerProvider)
        .fetchLyricsForMediaItem(widget.mediaItem);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsData?>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final lyrics = snapshot.data;
        if (lyrics == null) return const SizedBox.shrink();

        // Try synced lyrics first
        final synced = lyrics.syncedLyrics?.trim();
        if (synced != null && synced.isNotEmpty) {
          final lines = _parseLrc(synced);
          if (lines.isNotEmpty) {
            final posMs = widget.playback.updatePosition.inMilliseconds;
            int currentIndex = -1;
            for (int i = 0; i < lines.length; i++) {
              if (lines[i].timestamp.inMilliseconds <= posMs) {
                currentIndex = i;
              } else {
                break;
              }
            }
            final previewLines = <_LrcLine>[];
            for (
              int i = currentIndex;
              i < lines.length && previewLines.length < 4;
              i++
            ) {
              if (i >= 0) previewLines.add(lines[i]);
            }
            if (previewLines.isNotEmpty) {
              return _buildPreviewCard(
                context,
                previewLines.map((l) => l.text).toList(),
                0,
              );
            }
          }
        }

        // Fallback: plain lyrics (static preview)
        final plain = lyrics.plainLyrics?.trim();
        if (plain == null || plain.isEmpty) return const SizedBox.shrink();
        final plainLines = plain
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(4)
            .toList();
        if (plainLines.isEmpty) return const SizedBox.shrink();
        return _buildPreviewCard(context, plainLines, null);
      },
    );
  }

  Widget _buildPreviewCard(
    BuildContext context,
    List<String> lines,
    int? activeIndex,
  ) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(18)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aperçu des paroles',
              style: TextStyle(
                color: JojoColors.mutedStrong,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  lines[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (activeIndex == null || i == activeIndex)
                        ? Colors.white.withAlpha(230)
                        : (i == activeIndex + 1)
                        ? Colors.white.withAlpha(150)
                        : Colors.white.withAlpha(75),
                    fontWeight: (activeIndex == null || i == activeIndex)
                        ? FontWeight.w700
                        : FontWeight.normal,
                    fontSize: (activeIndex == null || i == activeIndex)
                        ? 17
                        : 14,
                    height: 1.35,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: widget.onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                side: BorderSide(color: Colors.white.withAlpha(60)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Afficher les paroles',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── More Options Button ─────────────────────────────────────────────────────

class _MoreOptionsButton extends ConsumerWidget {
  const _MoreOptionsButton({required this.sleepEnd, this.iconOnly = false});
  final DateTime? sleepEnd;
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(settingsProvider).playbackSpeed;
    final isTimerActive = sleepEnd != null;
    if (iconOnly) {
      return IconButton(
        onPressed: () => _showMenu(context, ref, speed, isTimerActive),
        icon: Icon(
          isTimerActive ? Icons.bedtime_rounded : Icons.more_horiz_rounded,
          color: isTimerActive ? JojoColors.primary : JojoColors.mutedStrong,
        ),
        iconSize: 26,
        tooltip: 'Plus',
      );
    }
    return FilledButton.tonalIcon(
      style: isTimerActive
          ? FilledButton.styleFrom(
              backgroundColor: JojoColors.primary.withAlpha(40),
              foregroundColor: JojoColors.primary,
            )
          : null,
      onPressed: () => _showMenu(context, ref, speed, isTimerActive),
      icon: Icon(
        isTimerActive ? Icons.bedtime_rounded : Icons.more_horiz_rounded,
        color: isTimerActive ? JojoColors.primary : null,
      ),
      label: isTimerActive
          ? _RemainingTime(sleepEnd: sleepEnd!)
          : const Text('Plus'),
    );
  }

  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    double speed,
    bool isTimerActive,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(
                speed == 1.0 ? 'Vitesse normale (1×)' : 'Vitesse $speed×',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _showSpeedDialog(context, ref, speed);
              },
            ),
            if (isTimerActive)
              ListTile(
                leading: const Icon(
                  Icons.cancel_outlined,
                  color: Color(0xFFFF6B8E),
                ),
                title: const Text('Annuler la minuterie'),
                onTap: () {
                  ref.read(sleepTimerProvider.notifier).cancel();
                  Navigator.of(ctx).pop();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.bedtime_rounded),
                title: const Text('Minuterie de sommeil'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showSleepDialog(context, ref);
                },
              ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Réglages'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context, WidgetRef ref, double current) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vitesse de lecture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                title: Text(s == 1.0 ? 'Normale (1×)' : '$s×'),
                trailing: current == s
                    ? const Icon(Icons.check_rounded, color: JojoColors.primary)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setPlaybackSpeed(s);
                  ref.read(playerControllerProvider).setSpeed(s);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSleepDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Minuterie de sommeil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in [
              (const Duration(minutes: 15), '15 minutes'),
              (const Duration(minutes: 30), '30 minutes'),
              (const Duration(minutes: 45), '45 minutes'),
              (const Duration(hours: 1), '1 heure'),
              (const Duration(hours: 2), '2 heures'),
            ])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(preset.$2),
                onTap: () {
                  ref.read(sleepTimerProvider.notifier).set(preset.$1);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _formatDuration(Duration value) {
  final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = value.inHours;
  if (h > 0) return '$h:$m:$s';
  return '${value.inMinutes}:$s';
}
