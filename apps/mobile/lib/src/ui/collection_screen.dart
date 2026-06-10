import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/player_controller.dart';
import 'profile_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/media_artwork.dart';
import 'widgets/shell_chrome.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({
    required this.title,
    required this.tracks,
    this.subtitle,
    required this.onTrackAction,
    this.artworkUrl,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final List<Track> tracks;
  final Future<void> Function(
    BuildContext context,
    Track track,
    List<Track> queue,
  )
  onTrackAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellChrome(
      topColor: const Color(0xFF163032),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      headerTitle: title,
      showBackButton: true,
      showProfileShortcut: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 148),
        children: [
          // ── Header style AlbumScreen ──────────────────────────────────────
          Center(
            child: MediaArtwork(
              url: artworkUrl,
              size: 160,
              borderRadius: 16,
              icon: Icons.playlist_play_rounded,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white60,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${tracks.length} titre${tracks.length != 1 ? 's' : ''}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 18),
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
                onPressed: tracks.isEmpty
                    ? null
                    : () {
                        final shuffled = [...tracks]..shuffle();
                        ref
                            .read(playerControllerProvider)
                            .playTrack(shuffled.first, queue: shuffled);
                      },
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Aléatoire'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Tracklist ─────────────────────────────────────────────────────
          if (tracks.isEmpty)
            const JojoStateMessage(message: 'Aucun titre disponible.')
          else
            ...tracks.map((track) {
              final t = (track.artworkUrl == null || track.artworkUrl!.isEmpty) && artworkUrl != null
                  ? track.copyWith(artworkUrl: artworkUrl)
                  : track;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: JojoTrackTile(
                  track: t,
                  onTap: () => ref.read(playerControllerProvider).playTrack(t, queue: tracks),
                  onMore: () => onTrackAction(context, track, tracks),
                ),
              );
            }),
        ],
      ),
    );
  }
}
