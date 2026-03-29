import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../models/app_models.dart';
import '../state/downloads_controller.dart';
import '../state/library_controller.dart';
import '../state/player_controller.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_bottom_bar.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final downloadedPlaylistIds = ref.watch(downloadedPlaylistIdsProvider);
    final downloads = ref.watch(downloadsProvider);

    return JojoPageScaffold(
      topColor: const Color(0xFF183437),
      bottomNavigationBar: const ShellBottomBar(popToRootOnNavigate: true),
      child: library.when(
        data: (data) {
          final isFavoritesPlaylist = playlistId == favoritesPlaylistId;
          Playlist? playlist = isFavoritesPlaylist
              ? data.favoritesPlaylist
              : null;
          if (!isFavoritesPlaylist) {
            for (final item in data.playlists) {
              if (item.id == playlistId) {
                playlist = item;
                break;
              }
            }
          }
          if (playlist == null) {
            return const Center(child: Text('Playlist introuvable.'));
          }
          final currentPlaylist = playlist;
          final tracks = currentPlaylist.tracks
              .map((item) => item.track)
              .toList();
          final isDownloaded =
              downloadedPlaylistIds.asData?.value.contains(
                currentPlaylist.id,
              ) ??
              false;
          final playlistTrackKeys = tracks
              .map((track) => track.trackKey)
              .toSet();
          final offlineByTrackKey = {
            for (final offline in downloads.asData?.value ?? <OfflineTrack>[])
              if (playlistTrackKeys.contains(offline.trackKey))
                offline.trackKey: offline,
          };
          final downloadedCount = offlineByTrackKey.values
              .where((track) => track.status == 'downloaded')
              .length;
          final downloadingCount = offlineByTrackKey.values
              .where((track) => track.status == 'downloading')
              .length;
          final queuedCount = offlineByTrackKey.values
              .where((track) => track.status == 'queued')
              .length;
          final failedCount = offlineByTrackKey.values
              .where((track) => track.status == 'failed')
              .length;
          final offlineSummary = isDownloaded
              ? _buildOfflineSummary(
                  totalCount: tracks.length,
                  downloadedCount: downloadedCount,
                  downloadingCount: downloadingCount,
                  queuedCount: queuedCount,
                  failedCount: failedCount,
                )
              : 'Active ce mode pour garder toute la playlist disponible sans connexion.';

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
            children: [
              JojoPageHeader(
                title: currentPlaylist.name,
                subtitle: isFavoritesPlaylist ? 'Favoris' : 'Playlist',
                leading: JojoIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                trailing: isFavoritesPlaylist
                    ? null
                    : JojoIconButton(
                        icon: Icons.delete_outline_rounded,
                        onPressed: () => _confirmDeletePlaylist(
                          context,
                          ref,
                          currentPlaylist,
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              JojoHeroPanel(
                label: isFavoritesPlaylist ? 'Playlist auto' : 'Playlist perso',
                title: currentPlaylist.name,
                subtitle: currentPlaylist.description.isEmpty
                    ? isFavoritesPlaylist
                          ? 'Tes titres aimés, regroupés comme une playlist.'
                          : 'Ta sélection locale modifiable.'
                    : currentPlaylist.description,
                artworkUrl: currentPlaylist.displayArtworkUrl,
                accentColor: const Color(0xFF1A3D40),
                metadata: ['${currentPlaylist.tracks.length} titres'],
                actions: [
                  FilledButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => ref
                              .read(playerControllerProvider)
                              .playTrack(tracks.first, queue: tracks),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Lire la playlist'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              JojoSurfaceCard(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDownloaded
                            ? JojoColors.primary.withValues(alpha: 0.16)
                            : JojoColors.surfaceBright,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_for_offline_rounded,
                        color: isDownloaded
                            ? JojoColors.primary
                            : JojoColors.mutedStrong,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hors ligne',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isDownloaded
                                ? 'Les nouveaux titres ajoutés seront téléchargés automatiquement.'
                                : 'Active ce mode pour garder toute la playlist disponible sans connexion.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            offlineSummary,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isDownloaded
                                      ? JojoColors.text
                                      : JojoColors.mutedStrong,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: isDownloaded,
                      onChanged: (_) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(downloadsControllerProvider)
                              .togglePlaylistDownload(
                                playlist: currentPlaylist,
                                playlists: data.playlists,
                                likes: data.likes,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                isDownloaded
                                    ? 'Mode hors ligne désactivé pour ${currentPlaylist.name}.'
                                    : 'Mode hors ligne activé pour ${currentPlaylist.name}.',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Impossible de changer le mode hors ligne: $error',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              JojoSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(
                      title: 'Titres',
                      subtitle: 'Lecture directe et suppression par morceau.',
                    ),
                    const SizedBox(height: 12),
                    if (currentPlaylist.tracks.isEmpty)
                      const JojoStateMessage(
                        icon: Icons.queue_music_rounded,
                        message: 'Cette playlist est vide.',
                      )
                    else
                      ...currentPlaylist.tracks.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: JojoTrackTile(
                            track: entry.value.track,
                            index: entry.key,
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .playTrack(entry.value.track, queue: tracks),
                            statusIndicator: _OfflineTrackIndicator(
                              track:
                                  offlineByTrackKey[entry.value.track.trackKey],
                            ),
                            onMore: () => _showTrackActions(
                              context,
                              ref,
                              currentPlaylist,
                              entry.value,
                              isFavoritesPlaylist: isFavoritesPlaylist,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
        error: (error, stackTrace) =>
            Center(child: Text('Erreur playlist: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  String _buildOfflineSummary({
    required int totalCount,
    required int downloadedCount,
    required int downloadingCount,
    required int queuedCount,
    required int failedCount,
  }) {
    if (totalCount == 0) {
      return 'Playlist prête pour le hors ligne.';
    }
    if (downloadingCount > 0 || queuedCount > 0) {
      final parts = <String>['$downloadedCount/$totalCount prêts'];
      if (downloadingCount > 0) {
        parts.add('$downloadingCount en cours');
      }
      if (queuedCount > 0) {
        parts.add('$queuedCount en attente');
      }
      if (failedCount > 0) {
        parts.add('$failedCount à relancer');
      }
      return parts.join(' • ');
    }
    if (downloadedCount >= totalCount) {
      return 'Toute la playlist est disponible hors ligne.';
    }
    if (failedCount > 0) {
      return '$downloadedCount/$totalCount prêts • $failedCount en échec';
    }
    return '$downloadedCount/$totalCount titres disponibles hors ligne.';
  }

  Future<void> _showTrackActions(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    PlaylistTrackItem item,
    {required bool isFavoritesPlaylist}
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Lire maintenant'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await ref
                      .read(playerControllerProvider)
                      .playTrack(
                        item.track,
                        queue: playlist.tracks
                            .map((entry) => entry.track)
                            .toList(),
                      );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(
                  isFavoritesPlaylist
                      ? 'Retirer des favoris'
                      : 'Retirer de la playlist',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  if (isFavoritesPlaylist) {
                    await ref
                        .read(libraryControllerProvider.notifier)
                        .toggleLike(item.track);
                  } else {
                    await ref
                        .read(libraryControllerProvider.notifier)
                        .removeFromPlaylist(
                          playlistId: playlist.id,
                          trackKey: item.track.trackKey,
                        );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer la playlist'),
          content: Text('Supprimer "${playlist.name}" et tous ses titres ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await ref
        .read(libraryControllerProvider.notifier)
        .deletePlaylist(playlist.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _OfflineTrackIndicator extends StatelessWidget {
  const _OfflineTrackIndicator({required this.track});

  final OfflineTrack? track;

  @override
  Widget build(BuildContext context) {
    final current = track;
    if (current == null) {
      return const SizedBox.shrink();
    }

    switch (current.status) {
      case 'downloaded':
        return Tooltip(
          message: 'Disponible hors ligne',
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF34D27E),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF34D27E).withValues(alpha: 0.38),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      case 'downloading':
        final progress = current.progress.clamp(0.0, 1.0);
        return Tooltip(
          message: 'Téléchargement ${(progress * 100).round()}%',
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: progress > 0 && progress < 1 ? progress : null,
              strokeWidth: 2.3,
              color: JojoColors.primary,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        );
      case 'queued':
        return Tooltip(
          message: 'En attente de téléchargement',
          child: Icon(
            Icons.downloading_rounded,
            size: 18,
            color: JojoColors.mutedStrong,
          ),
        );
      case 'failed':
        return Tooltip(
          message: 'Téléchargement échoué',
          child: Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: JojoColors.secondary,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
