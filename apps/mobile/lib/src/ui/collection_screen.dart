import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/player_controller.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_bottom_bar.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.onTrackAction,
    this.artworkUrl,
    super.key,
  });

  final String title;
  final String subtitle;
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
    return JojoPageScaffold(
      topColor: const Color(0xFF163032),
      bottomNavigationBar: const ShellBottomBar(popToRootOnNavigate: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
        children: [
          JojoPageHeader(
            title: title,
            subtitle: 'Collection',
            leading: JojoIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 18),
          JojoHeroPanel(
            label: 'Sélection',
            title: title,
            subtitle: subtitle,
            artworkUrl: artworkUrl,
            accentColor: const Color(0xFF163639),
            metadata: ['${tracks.length} titres'],
            actions: [
              FilledButton.icon(
                onPressed: tracks.isEmpty
                    ? null
                    : () => ref
                          .read(playerControllerProvider)
                          .playTrack(tracks.first, queue: tracks),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Lire'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          JojoSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const JojoSectionHeading(
                  title: 'Titres',
                  subtitle: 'La collection complète, prête à lancer.',
                ),
                const SizedBox(height: 12),
                if (tracks.isEmpty)
                  const JojoStateMessage(message: 'Aucun titre disponible.')
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
                        onMore: () =>
                            onTrackAction(context, entry.value, tracks),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
