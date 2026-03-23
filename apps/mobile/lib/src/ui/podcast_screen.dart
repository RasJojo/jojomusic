import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/discovery_controller.dart';
import '../state/library_controller.dart';
import '../state/player_controller.dart';
import 'profile_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/media_artwork.dart';
import 'widgets/shell_chrome.dart';

class PodcastScreen extends ConsumerWidget {
  const PodcastScreen({required this.podcast, super.key});

  final Podcast podcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(podcastDetailsProvider(podcast.podcastKey));
    final library = ref.watch(libraryControllerProvider).asData?.value;

    return ShellChrome(
      topColor: const Color(0xFF331925),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      child: details.when(
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
          children: [
            JojoPageHeader(
              title: data.podcast.title,
              subtitle: 'Podcast',
              leading: JojoIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 18),
            JojoHeroPanel(
              label: 'Show',
              title: data.podcast.title,
              subtitle: data.podcast.description?.isNotEmpty == true
                  ? data.podcast.description!
                  : data.podcast.publisher,
              artworkUrl: data.podcast.artworkUrl,
              accentColor: const Color(0xFF3C2030),
              metadata: [
                data.podcast.publisher,
                if ((data.podcast.episodeCount ?? data.episodes.length) > 0)
                  '${data.podcast.episodeCount ?? data.episodes.length} épisodes',
              ],
              actions: [
                FilledButton.icon(
                  onPressed: () => ref
                      .read(libraryControllerProvider.notifier)
                      .togglePodcastFollow(data.podcast),
                  icon: Icon(
                    library?.isPodcastFollowed(data.podcast) ?? false
                        ? Icons.check_rounded
                        : Icons.add_rounded,
                  ),
                  label: Text(
                    library?.isPodcastFollowed(data.podcast) ?? false
                        ? 'Suivi'
                        : 'Suivre',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            JojoSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const JojoSectionHeading(
                    title: 'Épisodes',
                    subtitle:
                        'Les épisodes disponibles et leur date de publication.',
                  ),
                  const SizedBox(height: 12),
                  if (data.episodes.isEmpty)
                    const JojoStateMessage(
                      icon: Icons.podcasts_rounded,
                      message:
                          'Aucun épisode exploitable trouvé pour ce podcast.',
                    )
                  else
                    ...data.episodes.map(
                      (episode) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => ref
                              .read(playerControllerProvider)
                              .playPodcastEpisode(episode),
                          borderRadius: BorderRadius.circular(22),
                          child: Ink(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: const Color(0x6617131B),
                              border: Border.all(
                                color: const Color(0x14FFFFFF),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MediaArtwork(
                                  url:
                                      episode.artworkUrl ??
                                      data.podcast.artworkUrl,
                                  size: 64,
                                  borderRadius: 18,
                                  backgroundColor: const Color(0xFF4D1D34),
                                  icon: Icons.mic_rounded,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        episode.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          if (episode.publishedAt != null)
                                            formatCompactDate(
                                              episode.publishedAt,
                                            ),
                                          if (episode.durationSeconds != null)
                                            '${(episode.durationSeconds! / 60).round()} min',
                                        ].join(' • '),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.play_circle_fill_rounded),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        error: (error, stackTrace) =>
            Center(child: Text('Erreur podcast: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
// Podcasts
