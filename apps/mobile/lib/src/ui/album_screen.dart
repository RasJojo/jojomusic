import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ytmusic/ytmusic_models.dart';
import '../models/app_models.dart';
import '../state/album_controller.dart';
import '../state/library_controller.dart';
import '../state/player_controller.dart';
import 'artist_screen.dart';
import 'profile_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/media_artwork.dart';
import 'widgets/shell_chrome.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({
    required this.ytAlbum,
    required this.onTrackAction,
    super.key,
  });

  final YtAlbum ytAlbum;
  final Future<void> Function(BuildContext, Track, List<Track>) onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(ytAlbumDetailProvider(ytAlbum.browseId));

    return ShellChrome(
      topColor: const Color(0xFF2A1A0D),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      headerTitle: ytAlbum.title,
      showBackButton: true,
      showProfileShortcut: false,
      child: details.when(
        data: (data) {
          if (data == null) {
            return Center(
              child: Text('Album "${ytAlbum.title}" introuvable.'),
            );
          }
          final tracks = data.tracks.map((t) => t.toTrack()).toList();
          final effectiveTitle = (data.title == 'Playlist' || data.title == 'Unknown Album')
              ? ytAlbum.title
              : data.title;
          final effectiveArtist = (data.artist.isEmpty || data.artist == 'Unknown')
              ? ytAlbum.artist
              : data.artist;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 148),
            children: [

              // ── Header album style Apple Music ────────────────────────────
              Center(
                child: MediaArtwork(
                  url: data.artworkUrl ?? ytAlbum.artworkUrl,
                  size: 160,
                  borderRadius: 16,
                  icon: Icons.album_rounded,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                effectiveTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [effectiveArtist, if (data.year != null) data.year!].join(' · '),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 18),

              // Boutons d'action centrés
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => ref
                              .read(playerControllerProvider)
                              .playTrack(tracks.first, queue: tracks),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Lire'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistScreen(
                          browseId: '',
                          artistName: effectiveArtist,
                          onTrackAction: onTrackAction,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.person_outline_rounded),
                    label: const Text('Artiste'),
                  ),
                  const SizedBox(width: 4),
                  Builder(
                    builder: (context) {
                      final library = ref.watch(libraryControllerProvider);
                      final saved =
                          library.asData?.value.isAlbumSaved(ytAlbum.browseId) ??
                          false;
                      return IconButton(
                        tooltip: saved
                            ? 'Retirer de la bibliothèque'
                            : 'Ajouter à la bibliothèque',
                        onPressed: () {
                          final album = Album(
                            albumKey: ytAlbum.browseId,
                            title: effectiveTitle,
                            artist: effectiveArtist,
                            artworkUrl: data.artworkUrl ?? ytAlbum.artworkUrl,
                            provider: 'youtube',
                            externalId: ytAlbum.browseId,
                          );
                          ref
                              .read(libraryControllerProvider.notifier)
                              .toggleSaveAlbum(album);
                        },
                        icon: Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_outline_rounded,
                          color: saved
                              ? Theme.of(context).colorScheme.secondary
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── Tracklist sans carte ───────────────────────────────────────
              if (tracks.isEmpty)
                const JojoStateMessage(
                  icon: Icons.music_off_rounded,
                  message: 'Aucun titre disponible pour cet album.',
                )
              else
                ...tracks.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: JojoTrackTile(
                      track: entry.value,
                      onTap: () => ref
                          .read(playerControllerProvider)
                          .playTrack(entry.value, queue: tracks),
                      onMore: () =>
                          onTrackAction(context, entry.value, tracks),
                    ),
                  ),
                ),
            ],
          );
        },
        error: (e, _) => Center(child: Text('Erreur album: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
