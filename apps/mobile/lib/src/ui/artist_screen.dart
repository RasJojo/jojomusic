import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/artist_controller.dart';
import '../state/player_controller.dart';
import 'album_screen.dart';
import 'profile_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_chrome.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({
    required this.browseId,
    required this.artistName,
    required this.onTrackAction,
    this.imageUrl,
    super.key,
  });

  final String browseId;
  final String artistName;
  final String? imageUrl;
  final Future<void> Function(BuildContext, Track, List<Track>) onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = browseId.isNotEmpty
        ? ref.watch(ytArtistDetailProvider(browseId))
        : ref.watch(ytArtistByNameProvider(artistName));

    return ShellChrome(
      topColor: const Color(0xFF123229),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      headerTitle: artistName,
      showBackButton: true,
      showProfileShortcut: false,
      child: details.when(
        data: (data) {
          if (data == null) {
            return Center(child: Text('Artiste "$artistName" introuvable.'));
          }
          final tracks = data.songs.map((t) => t.toTrack()).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 148),
            children: [
              // ── Header artiste style Apple Music ──────────────────────────
              _ArtistHeader(
                name: data.name,
                imageUrl: data.imageUrl,
                subscribers: data.subscribers,
                tracks: tracks,
                onPlay: () => ref
                    .read(playerControllerProvider)
                    .playTrack(tracks.first, queue: tracks),
                onMore: tracks.isEmpty
                    ? null
                    : () => onTrackAction(context, tracks.first, tracks),
              ),

              // ── Titres populaires ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JojoSectionHeading(title: 'Titres populaires'),
                    const SizedBox(height: 12),
                    if (tracks.isEmpty)
                      const JojoStateMessage(
                        icon: Icons.music_off_rounded,
                        message: 'Aucun titre disponible pour cet artiste.',
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
                ),
              ),

              // ── Albums ────────────────────────────────────────────────────
              if (data.albums.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 28, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const JojoSectionHeading(title: 'Sorties'),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 260,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: data.albums.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            final album = data.albums[index];
                            return JojoPosterCard(
                              title: album.title,
                              subtitle: album.year ?? '',
                              artworkUrl: album.artworkUrl,
                              width: 160,
                              height: 148,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AlbumScreen(
                                    ytAlbum: album,
                                    onTrackAction: onTrackAction,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
        error: (e, _) => Center(child: Text('Erreur artiste: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.name,
    required this.tracks,
    required this.onPlay,
    this.imageUrl,
    this.subscribers,
    this.onMore,
  });

  final String name;
  final String? imageUrl;
  final String? subscribers;
  final List<Track> tracks;
  final VoidCallback onPlay;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Artwork pleine largeur en fond
        SizedBox(
          height: 300,
          width: double.infinity,
          child: imageUrl != null
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const ColoredBox(color: Colors.black),
                )
              : const ColoredBox(color: Colors.black),
        ),
        // Dégradé bas
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xFF091617)],
                stops: [0.4, 1.0],
              ),
            ),
          ),
        ),
        // Nom + infos + boutons en bas
        Positioned(
          bottom: 0,
          left: 18,
          right: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  shadows: [
                    const Shadow(
                      color: Colors.black54,
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              if (subscribers != null) ...[
                const SizedBox(height: 4),
                Text(
                  subscribers!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: tracks.isEmpty ? null : onPlay,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Lancer'),
                  ),
                  if (onMore != null) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: onMore,
                      icon: const Icon(Icons.more_horiz_rounded),
                      label: const Text('Actions'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ],
    );
  }
}
