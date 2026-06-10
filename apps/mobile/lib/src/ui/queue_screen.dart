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
    final currentIndex = ref.watch(
      playbackStateProvider.select((s) => s.asData?.value.queueIndex ?? 0),
    );

    return ShellChrome(
      topColor: const Color(0xFF173638),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      child: queue.when(
        data: (items) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
            children: [
              JojoPageHeader(
                title: "File d'attente",
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
                            : '${items.length} titres alignés. Glisse pour réorganiser.',
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
                      subtitle: 'Glisse pour réorganiser, tap pour sauter.',
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const JojoStateMessage(
                        icon: Icons.music_off_rounded,
                        message: "La file d'attente est vide.",
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) => ref
                            .read(playerControllerProvider)
                            .reorderQueue(oldIndex, newIndex),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isCurrent = index == currentIndex;
                          return Padding(
                            key: ValueKey(item.id),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: JojoQueueTile(
                                    item: item,
                                    index: index,
                                    isCurrent: isCurrent,
                                    onTap: () => ref
                                        .read(playerControllerProvider)
                                        .playQueueItem(index),
                                  ),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: JojoColors.muted,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text("Erreur file d'attente: $error")),
      ),
    );
  }
}
