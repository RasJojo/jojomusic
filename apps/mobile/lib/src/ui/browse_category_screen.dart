import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/discovery_controller.dart';
import '../state/player_controller.dart';
import 'collection_screen.dart';
import 'podcast_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_bottom_bar.dart';

class BrowseCategoryScreen extends ConsumerWidget {
  const BrowseCategoryScreen({
    required this.category,
    required this.onAlbumSelected,
    required this.onArtistSelected,
    required this.onTrackAction,
    super.key,
  });

  final BrowseCategory category;
  final ValueChanged<Album> onAlbumSelected;
  final ValueChanged<Artist> onArtistSelected;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(browseCategoryProvider(category.categoryId));

    return JojoPageScaffold(
      topColor: _colorFromHex(category.colorHex),
      bottomNavigationBar: const ShellBottomBar(popToRootOnNavigate: true),
      child: result.when(
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
          children: [
            JojoPageHeader(
              title: data.category.title,
              subtitle: 'Thème',
              leading: JojoIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 18),
            JojoHeroPanel(
              label: 'Explorer',
              title: data.category.title,
              subtitle: data.category.subtitle,
              artworkUrl: data.category.artworkUrl,
              accentColor: _colorFromHex(category.colorHex),
              metadata: [
                '${data.tracks.length} titres',
                '${data.artists.length} artistes',
                '${data.albums.length} albums',
              ],
              actions: [
                FilledButton.icon(
                  onPressed: data.tracks.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CollectionScreen(
                                title: data.category.title,
                                subtitle: data.category.subtitle,
                                artworkUrl: data.tracks.first.displayArtworkUrl,
                                tracks: data.tracks,
                                onTrackAction: onTrackAction,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lire la sélection'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (data.podcasts.isNotEmpty) ...[
              JojoSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(
                      title: 'Podcasts',
                      subtitle: 'Voix et émissions liées à ce thème.',
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 282,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: data.podcasts.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final podcast = data.podcasts[index];
                          return JojoPosterCard(
                            title: podcast.title,
                            subtitle: podcast.publisher,
                            artworkUrl: podcast.artworkUrl,
                            badge: 'Podcast',
                            width: 188,
                            height: 176,
                            backgroundColor: const Color(0xFF15181F),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PodcastScreen(podcast: podcast),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (data.artists.isNotEmpty) ...[
              JojoSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(
                      title: 'Artistes',
                      subtitle:
                          'Les profils qui correspondent le mieux à ce thème.',
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 238,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: data.artists.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final artist = data.artists[index];
                          return JojoPosterCard(
                            title: artist.name,
                            subtitle: 'Artiste',
                            artworkUrl: artist.imageUrl,
                            badge: 'Artiste',
                            width: 164,
                            height: 136,
                            circularArtwork: true,
                            onTap: () => onArtistSelected(artist),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (data.albums.isNotEmpty) ...[
              JojoSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(
                      title: 'Albums',
                      subtitle: 'Des sorties alignées avec cette ambiance.',
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 272,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: data.albums.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          final album = data.albums[index];
                          return JojoPosterCard(
                            title: album.title,
                            subtitle: album.artist,
                            artworkUrl: album.artworkUrl,
                            badge: album.trackCount == null
                                ? 'Album'
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
              ),
              const SizedBox(height: 18),
            ],
            JojoSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const JojoSectionHeading(
                    title: 'Titres',
                    subtitle:
                        'Les morceaux exploitables pour une lecture immédiate.',
                  ),
                  const SizedBox(height: 12),
                  if (data.tracks.isEmpty)
                    const JojoStateMessage(
                      icon: Icons.music_off_rounded,
                      message: 'Aucun titre pour ce thème.',
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
            Center(child: Text('Erreur browse: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final buffer = StringBuffer();
  if (value.length == 7) {
    buffer.write('ff');
  }
  buffer.write(value.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
