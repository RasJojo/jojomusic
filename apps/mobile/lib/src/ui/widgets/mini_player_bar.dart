import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../lyrics_screen.dart';
import '../queue_screen.dart';
import '../theme/jojo_theme.dart';
import 'jojo_logo.dart';
import 'jojo_surfaces.dart';
import 'media_artwork.dart';
import 'track_playlist_picker_sheet.dart';

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
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final isPlaying = playbackState.asData?.value.playing ?? false;
    final isLiked =
        library?.likes.any((track) => track.trackKey == mediaItemTrackKey(item)) ??
        false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF143434), Color(0xFF0A1718)],
          ),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useRootNavigator: true,
            showDragHandle: true,
            backgroundColor: JojoColors.surface,
            builder: (context) => const _PlayerSheet(),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 390;
                final artworkSize = compact ? 42.0 : 50.0;
                final iconSize = compact ? 24.0 : 28.0;
                final playSize = compact ? 44.0 : 50.0;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
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
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: currentTrack == null
                              ? null
                              : () => ref
                                    .read(libraryControllerProvider.notifier)
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
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopPlayerPanel extends ConsumerStatefulWidget {
  const DesktopPlayerPanel({
    super.key,
    this.width = 340,
  });

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
    final queue = ref.watch(currentQueueProvider).asData?.value ?? const [];
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final library = ref.watch(libraryControllerProvider).asData?.value;

    return Container(
      width: widget.width,
      decoration: const BoxDecoration(
        color: Color(0xB3071213),
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
                                style: Theme.of(context).textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                mediaItem.artist ?? '',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: JojoColors.mutedStrong),
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
                                onChanged: (value) =>
                                    setState(() => _dragValueMs = value),
                                onChangeEnd: (value) async {
                                  setState(() => _dragValueMs = null);
                                  await ref
                                      .read(playerControllerProvider)
                                      .seek(
                                        Duration(milliseconds: value.round()),
                                      );
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
                                    icon: Icons.replay_rounded,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .seekRelative(
                                          const Duration(seconds: -15),
                                        ),
                                  ),
                                  _DesktopIconButton(
                                    icon: Icons.skip_previous_rounded,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .skipPrevious(),
                                  ),
                                  Container(
                                    width: 68,
                                    height: 68,
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
                                        size: 36,
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
                                    icon: Icons.forward_rounded,
                                    onPressed: () => ref
                                        .read(playerControllerProvider)
                                        .seekRelative(
                                          const Duration(seconds: 15),
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        JojoSurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Actions',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: currentTrack == null
                                        ? null
                                        : () => ref
                                              .read(
                                                libraryControllerProvider
                                                    .notifier,
                                              )
                                              .toggleLike(currentTrack),
                                    icon: Icon(
                                      isLiked
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: isLiked
                                          ? const Color(0xFFFF6B8E)
                                          : null,
                                    ),
                                    label: Text(isLiked ? 'Liké' : 'Liker'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: currentTrack == null
                                        ? null
                                        : () => showTrackPlaylistPickerSheet(
                                            context,
                                            ref,
                                            track: currentTrack,
                                            preferDownloaded: true,
                                          ),
                                    icon: const Icon(
                                      Icons.playlist_add_rounded,
                                    ),
                                    label: const Text('Ajouter'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _openingQueue
                                        ? null
                                        : () => _openQueuePage(context),
                                    icon: const Icon(
                                      Icons.queue_music_rounded,
                                    ),
                                    label: const Text('File d’attente'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _openingLyrics
                                        ? null
                                        : () => _openLyricsPage(
                                            context,
                                            mediaItem,
                                          ),
                                    icon: _openingLyrics
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                            ),
                                          )
                                        : const Icon(Icons.lyrics_outlined),
                                    label: const Text('Paroles'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                currentTrack == null
                                    ? 'Épisode ou source directe • ajout playlist indisponible'
                                    : '${queue.length} titres dans la file • la lecture continue automatiquement',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
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
    if (_openingLyrics) {
      return;
    }
    setState(() => _openingLyrics = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => LyricsScreen(mediaItem: mediaItem),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingLyrics = false);
      }
    }
  }

  Future<void> _openQueuePage(BuildContext context) async {
    if (_openingQueue) {
      return;
    }
    setState(() => _openingQueue = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const QueueScreen()),
      );
    } finally {
      if (mounted) {
        setState(() => _openingQueue = false);
      }
    }
  }
}

class _DesktopPlayerPlaceholder extends StatelessWidget {
  const _DesktopPlayerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return JojoSurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: JojoColors.surfaceBright,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: JojoLogo(size: 38, borderRadius: 14),
            ),
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
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 28,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: JojoColors.surfaceBright,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Icon(icon, color: JojoColors.text, size: 28),
      ),
    );
  }
}

class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet();

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  double? _dragValueMs;
  bool _openingLyrics = false;
  bool _openingQueue = false;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playback = ref.watch(playbackStateProvider).asData?.value;
    final queue = ref.watch(currentQueueProvider).asData?.value ?? const [];
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final library = ref.watch(libraryControllerProvider).asData?.value;

    if (mediaItem == null || playback == null) {
      return const SizedBox(height: 240);
    }

    final maxMs = (mediaItem.duration?.inMilliseconds ?? 1).clamp(1, 1 << 31);
    final currentMs = playback.updatePosition.inMilliseconds.clamp(0, maxMs);
    final sliderValue = (_dragValueMs ?? currentMs.toDouble())
        .clamp(0.0, maxMs.toDouble())
        .toDouble();
    final isLiked =
        currentTrack != null && (library?.isLiked(currentTrack) ?? false);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF163837), Color(0xFF0A1718), Color(0xFF050E0E)],
        ),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactWidth = constraints.maxWidth < 430;
            final compactHeight = constraints.maxHeight < 780;
            final artworkSize = math.min(
              compactWidth
                  ? constraints.maxWidth * 0.56
                  : constraints.maxWidth * 0.62,
              compactHeight ? 220.0 : 280.0,
            );
            final horizontalPadding = compactWidth ? 14.0 : 20.0;
            final cardSpacing = compactHeight ? 12.0 : 18.0;
            final seekButtonWidth = compactWidth ? 86.0 : 104.0;
            final iconSize = compactWidth ? 32.0 : 38.0;
            final playIconSize = compactWidth ? 40.0 : 48.0;

            return Padding(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                children: [
                  JojoSurfaceCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        MediaArtwork(
                          url: mediaItem.artUri?.toString(),
                          size: artworkSize,
                          borderRadius: 28,
                        ),
                        SizedBox(height: compactHeight ? 16 : 22),
                        Text(
                          mediaItem.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mediaItem.artist ?? '',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: JojoColors.mutedStrong),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: cardSpacing),
                  JojoSurfaceCard(
                    child: Column(
                      children: [
                        Slider(
                          value: sliderValue,
                          max: maxMs.toDouble(),
                          onChanged: (value) =>
                              setState(() => _dragValueMs = value),
                          onChangeEnd: (value) async {
                            setState(() => _dragValueMs = null);
                            await ref
                                .read(playerControllerProvider)
                                .seek(Duration(milliseconds: value.round()));
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                _formatDuration(
                                  Duration(milliseconds: sliderValue.round()),
                                ),
                              ),
                              const Spacer(),
                              Text(_formatDuration(Duration(milliseconds: maxMs))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: compactWidth ? 6 : 10,
                          runSpacing: 10,
                          children: [
                            _SeekRelativeButton(
                              width: seekButtonWidth,
                              label: '-15 s',
                              icon: Icons.replay_rounded,
                              onPressed: () => ref
                                  .read(playerControllerProvider)
                                  .seekRelative(const Duration(seconds: -15)),
                            ),
                            IconButton(
                              onPressed: () => ref
                                  .read(playerControllerProvider)
                                  .skipPrevious(),
                              iconSize: iconSize,
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            Container(
                              decoration: const BoxDecoration(
                                color: JojoColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () => ref
                                    .read(playerControllerProvider)
                                    .togglePlayPause(),
                                iconSize: playIconSize,
                                color: Colors.black,
                                icon: Icon(
                                  playback.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => ref
                                  .read(playerControllerProvider)
                                  .skipNext(),
                              iconSize: iconSize,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                            _SeekRelativeButton(
                              width: seekButtonWidth,
                              label: '+15 s',
                              icon: Icons.forward_rounded,
                              onPressed: () => ref
                                  .read(playerControllerProvider)
                                  .seekRelative(const Duration(seconds: 15)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: currentTrack == null
                                  ? null
                                  : () => ref
                                        .read(libraryControllerProvider.notifier)
                                        .toggleLike(currentTrack),
                              icon: Icon(
                                isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: isLiked
                                    ? const Color(0xFFFF6B8E)
                                    : null,
                              ),
                              label: Text(isLiked ? 'Liké' : 'Liker'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: currentTrack == null
                                  ? null
                                  : () => showTrackPlaylistPickerSheet(
                                      context,
                                      ref,
                                      track: currentTrack,
                                      preferDownloaded: true,
                                    ),
                              icon: const Icon(Icons.playlist_add_rounded),
                              label: const Text('Ajouter'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _openingQueue
                                  ? null
                                  : () => _openQueuePage(context),
                              icon: const Icon(Icons.queue_music_rounded),
                              label: const Text('File d’attente'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _openingLyrics
                                  ? null
                                  : () => _openLyricsPage(context, mediaItem),
                              icon: _openingLyrics
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Icon(Icons.lyrics_outlined),
                              label: const Text('Paroles'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            currentTrack == null
                                ? 'Épisode ou source directe • playlists indisponibles'
                                : '${queue.length} titres dans la file • la lecture se prolonge automatiquement',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openLyricsPage(
    BuildContext context,
    MediaItem mediaItem,
  ) async {
    if (_openingLyrics) {
      return;
    }
    setState(() => _openingLyrics = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => LyricsScreen(mediaItem: mediaItem),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingLyrics = false);
      }
    }
  }

  Future<void> _openQueuePage(BuildContext context) async {
    if (_openingQueue) {
      return;
    }
    setState(() => _openingQueue = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const QueueScreen()),
      );
    } finally {
      if (mounted) {
        setState(() => _openingQueue = false);
      }
    }
  }
}

class _SeekRelativeButton extends StatelessWidget {
  const _SeekRelativeButton({
    required this.width,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final double width;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          foregroundColor: JojoColors.text,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = value.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '${value.inMinutes}:$seconds';
}
