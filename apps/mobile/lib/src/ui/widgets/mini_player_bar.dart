import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_models.dart';
import '../../state/downloads_controller.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../theme/jojo_theme.dart';
import 'jojo_surfaces.dart';
import 'media_artwork.dart';

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider);
    final playbackState = ref.watch(playbackStateProvider);

    if (mediaItem.asData?.value == null) {
      return const SizedBox.shrink();
    }

    final item = mediaItem.asData!.value!;
    final isPlaying = playbackState.asData?.value.playing ?? false;
    final progress = (() {
      final duration = item.duration?.inMilliseconds ?? 0;
      final position =
          playbackState.asData?.value.updatePosition.inMilliseconds ?? 0;
      if (duration <= 0) {
        return 0.0;
      }
      return (position / duration).clamp(0.0, 1.0);
    })();

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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          JojoColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                          onPressed: () =>
                              ref.read(playerControllerProvider).skipPrevious(),
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            size: iconSize,
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
                          onPressed: () =>
                              ref.read(playerControllerProvider).skipNext(),
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: iconSize,
                          ),
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

class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet();

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  double? _dragValueMs;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playback = ref.watch(playbackStateProvider).asData?.value;
    final queue = ref.watch(currentQueueProvider).asData?.value ?? const [];
    final currentTrack = ref.read(playerControllerProvider).currentQueueTrack();
    final library = ref.watch(libraryControllerProvider).asData?.value;
    final downloadedPlaylistIds =
        ref.watch(downloadedPlaylistIdsProvider).asData?.value ??
        const <String>{};

    if (mediaItem == null || playback == null) {
      return const SizedBox(height: 240);
    }

    final maxMs = (mediaItem.duration?.inMilliseconds ?? 1).clamp(1, 1 << 31);
    final currentMs = playback.updatePosition.inMilliseconds.clamp(0, maxMs);
    final sliderValue = (_dragValueMs ?? currentMs.toDouble())
        .clamp(0.0, maxMs.toDouble())
        .toDouble();
    final isLiked =
        currentTrack != null &&
        (library?.likes.any((item) => item.trackKey == currentTrack.trackKey) ??
            false);

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
              compactWidth ? constraints.maxWidth * 0.56 : constraints.maxWidth * 0.62,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: JojoColors.mutedStrong,
                      ),
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
                          onPressed: () =>
                              ref.read(playerControllerProvider).skipPrevious(),
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
                          onPressed: () =>
                              ref.read(playerControllerProvider).skipNext(),
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
                          ),
                          label: Text(isLiked ? 'Liké' : 'Liker'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: currentTrack == null
                              ? null
                              : () => _showPlaylistPicker(
                                  context,
                                  track: currentTrack,
                                  playlists: library?.playlists ?? const [],
                                  downloadedPlaylistIds: downloadedPlaylistIds,
                                  preferDownloaded: false,
                                ),
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: const Text('Ajouter'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: currentTrack == null
                              ? null
                              : () => _showPlaylistPicker(
                                  context,
                                  track: currentTrack,
                                  playlists: library?.playlists ?? const [],
                                  downloadedPlaylistIds: downloadedPlaylistIds,
                                  preferDownloaded: true,
                                ),
                          icon: const Icon(Icons.download_for_offline_rounded),
                          label: const Text('Hors ligne'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _showLyricsSheet,
                          icon: const Icon(Icons.lyrics_outlined),
                          label: const Text('Paroles'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        currentTrack == null
                            ? 'Épisode ou source directe • actions playlist indisponibles'
                            : '${queue.length} titres dans la file',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: cardSpacing),
              Expanded(
                child: JojoSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File d’attente',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: queue.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = queue[index];
                            final isCurrent = index == playback.queueIndex;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: MediaArtwork(
                                url: item.artUri?.toString(),
                                size: 52,
                                borderRadius: 16,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: isCurrent
                                    ? Theme.of(context).textTheme.titleSmall
                                          ?.copyWith(color: JojoColors.primary)
                                    : null,
                              ),
                              subtitle: Text(
                                item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isCurrent
                                  ? const Icon(
                                      Icons.graphic_eq_rounded,
                                      color: JojoColors.primary,
                                    )
                                  : null,
                              onTap: () => ref
                                  .read(playerControllerProvider)
                                  .playQueueItem(index),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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

  Future<void> _showLyricsSheet() async {
    final lyrics = await ref
        .read(playerControllerProvider)
        .fetchLyricsForCurrentTrack();
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Text(lyrics?.plainLyrics ?? 'Aucune parole trouvée.'),
          ),
        );
      },
    );
  }

  Future<void> _showPlaylistPicker(
    BuildContext context, {
    required Track track,
    required List<Playlist> playlists,
    required Set<String> downloadedPlaylistIds,
    required bool preferDownloaded,
  }) async {
    final sortedPlaylists = [...playlists]
      ..sort((left, right) {
        final leftDownloaded = downloadedPlaylistIds.contains(left.id);
        final rightDownloaded = downloadedPlaylistIds.contains(right.id);
        if (preferDownloaded && leftDownloaded != rightDownloaded) {
          return leftDownloaded ? -1 : 1;
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Nouvelle playlist'),
                subtitle: const Text(
                  'Crée une playlist puis ajoute immédiatement ce titre.',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showCreatePlaylistDialog(track);
                },
              ),
              if (sortedPlaylists.isEmpty)
                const ListTile(
                  leading: Icon(Icons.queue_music_rounded),
                  title: Text('Aucune playlist pour le moment'),
                  subtitle: Text(
                    'Crée-en une, puis active le hors ligne depuis la page playlist.',
                  ),
                )
              else
                ...sortedPlaylists.map(
                  (playlist) => ListTile(
                    leading: Icon(
                      downloadedPlaylistIds.contains(playlist.id)
                          ? Icons.download_done_rounded
                          : Icons.playlist_add_rounded,
                    ),
                    title: Text(playlist.name),
                    subtitle: Text(
                      downloadedPlaylistIds.contains(playlist.id)
                          ? 'Playlist hors ligne • ajout = téléchargement auto'
                          : 'Playlist standard',
                    ),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(context).pop();
                      await ref
                          .read(libraryControllerProvider.notifier)
                          .addToPlaylist(playlistId: playlist.id, track: track);
                      if (!mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            downloadedPlaylistIds.contains(playlist.id)
                                ? 'Ajouté à ${playlist.name}. Téléchargement hors ligne lancé.'
                                : 'Ajouté à ${playlist.name}.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreatePlaylistDialog(Track track) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nouvelle playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Par exemple: Nuit, Mada offline, Rap FR',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.of(context).pop();
                await ref
                    .read(libraryControllerProvider.notifier)
                    .createPlaylistWithTrack(name: name, track: track);
                if (!mounted) {
                  return;
                }
                messenger.showSnackBar(
                  SnackBar(content: Text('$name créée et titre ajouté.')),
                );
              },
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
    controller.dispose();
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
