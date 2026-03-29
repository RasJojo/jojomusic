import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_models.dart';
import '../../state/downloads_controller.dart';
import '../../state/library_controller.dart';
import '../theme/jojo_theme.dart';

Future<void> showTrackPlaylistPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required Track track,
  bool preferDownloaded = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: JojoColors.surface,
    builder: (context) => _TrackPlaylistPickerSheet(
      track: track,
      preferDownloaded: preferDownloaded,
    ),
  );
}

class _TrackPlaylistPickerSheet extends ConsumerStatefulWidget {
  const _TrackPlaylistPickerSheet({
    required this.track,
    required this.preferDownloaded,
  });

  final Track track;
  final bool preferDownloaded;

  @override
  ConsumerState<_TrackPlaylistPickerSheet> createState() =>
      _TrackPlaylistPickerSheetState();
}

class _TrackPlaylistPickerSheetState
    extends ConsumerState<_TrackPlaylistPickerSheet> {
  bool _busy = false;
  bool _selectionInitialized = false;
  Set<String> _selectedPlaylistIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryControllerProvider);
    final downloadedPlaylistIds =
        ref.watch(downloadedPlaylistIdsProvider).asData?.value ??
        const <String>{};

    return SafeArea(
      child: library.when(
        data: (data) {
          if (!_selectionInitialized) {
            _selectedPlaylistIds = data.playlistIdsForTrack(widget.track);
            _selectionInitialized = true;
          }
          final sortedPlaylists = [...data.playlists]
            ..sort((left, right) {
              final leftDownloaded = downloadedPlaylistIds.contains(left.id);
              final rightDownloaded = downloadedPlaylistIds.contains(right.id);
              if (widget.preferDownloaded &&
                  leftDownloaded != rightDownloaded) {
                return leftDownloaded ? -1 : 1;
              }
              return left.name.toLowerCase().compareTo(right.name.toLowerCase());
            });

          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              8,
              18,
              MediaQuery.of(context).padding.bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ajouter à une playlist',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tileColor: const Color(0xFF122324),
                  leading: const Icon(Icons.add_circle_outline_rounded),
                  title: const Text('Nouvelle playlist'),
                  subtitle: const Text(
                    'Crée une playlist et ajoute ce titre tout de suite.',
                  ),
                  onTap: _busy ? null : () => _showCreatePlaylistDialog(context),
                ),
                const SizedBox(height: 12),
                if (sortedPlaylists.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.queue_music_rounded),
                    title: Text('Aucune playlist pour le moment'),
                    subtitle: Text(
                      'Crée-en une pour organiser ce morceau.',
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.46,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sortedPlaylists.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final playlist = sortedPlaylists[index];
                        final isChecked = _selectedPlaylistIds.contains(
                          playlist.id,
                        );
                        final isOffline = downloadedPlaylistIds.contains(
                          playlist.id,
                        );
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          tileColor: const Color(0x99121E1F),
                          leading: Checkbox.adaptive(
                            value: isChecked,
                            onChanged: _busy
                                ? null
                                : (_) => _togglePlaylist(playlist, isChecked),
                          ),
                          title: Text(playlist.name),
                          subtitle: Text(
                            isOffline
                                ? 'Playlist hors ligne • ajout = téléchargement auto'
                                : 'Playlist standard',
                          ),
                          trailing: isOffline
                              ? const Icon(
                                  Icons.download_done_rounded,
                                  color: JojoColors.primary,
                                )
                              : null,
                          onTap: _busy
                              ? null
                              : () => _togglePlaylist(playlist, isChecked),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => SizedBox(
          height: 220,
          child: Center(child: Text('Impossible de charger les playlists: $error')),
        ),
      ),
    );
  }

  Future<void> _togglePlaylist(Playlist playlist, bool isChecked) async {
    final previousSelection = Set<String>.from(_selectedPlaylistIds);
    setState(() {
      _busy = true;
      if (isChecked) {
        _selectedPlaylistIds.remove(playlist.id);
      } else {
        _selectedPlaylistIds.add(playlist.id);
      }
    });
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .toggleTrackInPlaylist(playlist: playlist, track: widget.track);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isChecked
                ? 'Retiré de ${playlist.name}.'
                : 'Ajouté à ${playlist.name}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _selectedPlaylistIds = previousSelection;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible de mettre à jour ${playlist.name}: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nouvelle playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Par exemple: Nuit, Mada, Focus',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                setState(() => _busy = true);
                try {
                  final playlist = await ref
                      .read(libraryControllerProvider.notifier)
                      .createPlaylistWithTrack(
                        name: name,
                        track: widget.track,
                      );
                  if (mounted) {
                    setState(() {
                      _selectionInitialized = true;
                      _selectedPlaylistIds.add(playlist.id);
                    });
                  }
                } finally {
                  if (mounted) {
                    setState(() => _busy = false);
                  }
                }
              },
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
  }
}
