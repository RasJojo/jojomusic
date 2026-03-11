import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import 'profile_screen.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_chrome.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(currentQueueProvider);
    final playback = ref.watch(playbackStateProvider);

    return ShellChrome(
      topColor: const Color(0xFF173638),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      child: queue.when(
        data: (items) {
          final currentIndex = playback.asData?.value.queueIndex ?? 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
            children: [
              JojoPageHeader(
                title: 'File d’attente',
                subtitle: 'La lecture continue avec des titres similaires.',
                leading: JojoIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 18),
              JojoSurfaceCard(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: JojoColors.surfaceBright,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: JojoColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        items.isEmpty
                            ? 'Aucun morceau dans la file pour le moment.'
                            : '${items.length} titres alignés. Les derniers morceaux ajoutent automatiquement une suite proche de ce que tu écoutes.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                      title: 'Lecture suivante',
                      subtitle: 'Sélectionne un titre pour sauter directement.',
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const JojoStateMessage(
                        icon: Icons.music_off_rounded,
                        message: 'La file d’attente est vide.',
                      )
                    else
                      ...items.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: JojoQueueTile(
                            item: entry.value,
                            index: entry.key,
                            isCurrent: entry.key == currentIndex,
                            onTap: () => ref
                                .read(playerControllerProvider)
                                .playQueueItem(entry.key),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Erreur file d’attente: $error')),
      ),
    );
  }
}
// Queue
