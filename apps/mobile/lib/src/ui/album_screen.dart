import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/album_controller.dart';
import '../state/player_controller.dart';
import 'artist_screen.dart';
import 'profile_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_chrome.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({
    required this.album,
    required this.onTrackAction,
    super.key,
  });

  final Album album;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(albumDetailsProvider(album));

    return ShellChrome(
      topColor: const Color(0xFF392113),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      child: details.when(
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
          children: [
            JojoPageHeader(
              title: data.album.title,
              subtitle: 'Page album',
              leading: JojoIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 18),
            JojoHeroPanel(
              label: 'Album',
              title: data.album.title,
              subtitle: data.album.summary?.isNotEmpty == true
                  ? data.album.summary!
                  : data.album.artist,
              artworkUrl: data.album.artworkUrl,
              accentColor: const Color(0xFF46301B),
              metadata: [
                if (data.album.releaseDate != null)
                  '${data.album.releaseDate!.year}',
                if ((data.album.trackCount ?? data.tracks.length) > 0)
                  '${data.album.trackCount ?? data.tracks.length} titres',
              ],
              actions: [
                FilledButton.icon(
                  onPressed: data.tracks.isEmpty
                      ? null
                      : () => ref
                            .read(playerControllerProvider)
                            .playTrack(data.tracks.first, queue: data.tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lire l’album'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistScreen(
                          artist: Artist(
                            artistKey: _artistKeyFromName(data.album.artist),
                            name: data.album.artist,
                          ),
                          onTrackAction: onTrackAction,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('Voir l’artiste'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            JojoSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const JojoSectionHeading(
                    title: 'Tracklist',
                    subtitle: 'Lecture séquentielle et actions par titre.',
                  ),
                  const SizedBox(height: 12),
                  if (data.tracks.isEmpty)
                    const JojoStateMessage(
                      icon: Icons.music_off_rounded,
                      message: 'Aucun titre disponible pour cet album.',
                    )
                  else
                    ...data.tracks.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: JojoTrackTile(
                          track: entry.value,
                          index: entry.key,
                          onTap: () => ref
                              .read(playerControllerProvider)
                              .playTrack(entry.value, queue: data.tracks),
                          onMore: () =>
                              onTrackAction(context, entry.value, data.tracks),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        error: (error, stackTrace) =>
            Center(child: Text('Erreur album: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

String _artistKeyFromName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
// Albums
