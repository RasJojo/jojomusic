import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/artist_controller.dart';
import '../state/player_controller.dart';
import 'album_screen.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_bottom_bar.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({
    required this.artist,
    required this.onTrackAction,
    super.key,
  });

  final Artist artist;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(artistDetailsProvider(artist.name));

    return JojoPageScaffold(
      topColor: const Color(0xFF123229),
      bottomNavigationBar: const ShellBottomBar(popToRootOnNavigate: true),
      child: details.when(
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
          children: [
            JojoPageHeader(
              title: data.artist.name,
              subtitle: 'Page artiste',
              leading: JojoIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 18),
            JojoHeroPanel(
              label: 'Artiste',
              title: data.artist.name,
              subtitle: data.artist.summary?.isNotEmpty == true
                  ? data.artist.summary!
                  : 'Titres populaires, sorties et artistes proches.',
              artworkUrl: data.artist.imageUrl,
              circularArtwork: true,
              accentColor: const Color(0xFF183E31),
              metadata: [
                if ((data.artist.listeners ?? 0) > 0)
                  '${data.artist.listeners} auditeurs',
                '${data.topTracks.length} titres phares',
                '${data.topAlbums.length} sorties',
              ],
              actions: [
                FilledButton.icon(
                  onPressed: data.topTracks.isEmpty
                      ? null
                      : () => ref
                            .read(playerControllerProvider)
                            .playTrack(
                              data.topTracks.first,
                              queue: data.topTracks,
                            ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lancer'),
                ),
                OutlinedButton.icon(
                  onPressed: data.topTracks.isEmpty
                      ? null
                      : () => onTrackAction(
                          context,
                          data.topTracks.first,
                          data.topTracks,
                        ),
                  icon: const Icon(Icons.more_horiz_rounded),
                  label: const Text('Actions'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _ArtistTrackSection(
              tracks: data.topTracks,
              onTrackAction: onTrackAction,
            ),
            const SizedBox(height: 18),
            _AlbumSection(
              albums: data.topAlbums,
              onAlbumSelected: (album) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AlbumScreen(album: album, onTrackAction: onTrackAction),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            _SimilarArtistsSection(
              artists: data.similarArtists,
              onSelectArtist: (artist) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArtistScreen(
                      artist: artist,
                      onTrackAction: onTrackAction,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        error: (error, stackTrace) =>
            Center(child: Text('Erreur artiste: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ArtistTrackSection extends ConsumerWidget {
  const _ArtistTrackSection({
    required this.tracks,
    required this.onTrackAction,
  });

  final List<Track> tracks;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Titres populaires',
            subtitle: 'Ce qui ressort le plus vite pour cet artiste.',
          ),
          const SizedBox(height: 12),
          if (tracks.isEmpty)
            const JojoStateMessage(
              icon: Icons.music_off_rounded,
              message: 'Aucun titre disponible pour cet artiste.',
            )
          else
            ...tracks.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: JojoTrackTile(
                  track: entry.value,
                  index: entry.key,
                  onTap: () => ref
                      .read(playerControllerProvider)
                      .playTrack(entry.value, queue: tracks),
                  onMore: () => onTrackAction(context, entry.value, tracks),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumSection extends StatelessWidget {
  const _AlbumSection({required this.albums, required this.onAlbumSelected});

  final List<Album> albums;
  final ValueChanged<Album> onAlbumSelected;

  @override
  Widget build(BuildContext context) {
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Sorties',
            subtitle: 'Albums, EPs et singles liés à cet artiste.',
          ),
          const SizedBox(height: 14),
          if (albums.isEmpty)
            const JojoStateMessage(
              icon: Icons.album_outlined,
              message: 'Aucune sortie disponible.',
            )
          else
            SizedBox(
              height: 276,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: albums.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return JojoPosterCard(
                    title: album.title,
                    subtitle: [
                      album.artist,
                      if (album.releaseDate != null)
                        '${album.releaseDate!.year}',
                    ].join(' • '),
                    artworkUrl: album.artworkUrl,
                    badge: album.trackCount == null
                        ? 'Sortie'
                        : '${album.trackCount} titres',
                    width: 176,
                    height: 160,
                    onTap: () => onAlbumSelected(album),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SimilarArtistsSection extends StatelessWidget {
  const _SimilarArtistsSection({
    required this.artists,
    required this.onSelectArtist,
  });

  final List<Artist> artists;
  final ValueChanged<Artist> onSelectArtist;

  @override
  Widget build(BuildContext context) {
    return JojoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JojoSectionHeading(
            title: 'Artistes proches',
            subtitle: 'Pour continuer sur la même couleur musicale.',
          ),
          const SizedBox(height: 14),
          if (artists.isEmpty)
            const JojoStateMessage(
              icon: Icons.people_outline_rounded,
              message: 'Aucun artiste proche trouvé.',
            )
          else
            SizedBox(
              height: 238,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return JojoPosterCard(
                    title: artist.name,
                    subtitle: artist.listeners == null
                        ? 'Artiste'
                        : '${artist.listeners} auditeurs',
                    artworkUrl: artist.imageUrl,
                    badge: 'Artiste',
                    width: 164,
                    height: 136,
                    circularArtwork: true,
                    backgroundColor: JojoColors.surfaceRaised,
                    onTap: () => onSelectArtist(artist),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
