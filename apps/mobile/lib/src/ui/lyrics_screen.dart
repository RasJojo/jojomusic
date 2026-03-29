import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../state/player_controller.dart';
import 'profile_screen.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_chrome.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({required this.mediaItem, super.key});

  final MediaItem mediaItem;

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  late Future<LyricsData?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _loadLyrics();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final useDesktopLyrics =
        mediaQuery.size.width >= 1180 && mediaQuery.size.shortestSide >= 700;
    final lines = _extractDisplayLines;
    return ShellChrome(
      topColor: const Color(0xFF18383A),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      child: FutureBuilder<LyricsData?>(
        future: _lyricsFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState != ConnectionState.done;
          final lyrics = snapshot.data;
          final items = lines(lyrics);

          return ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              16,
              18,
              useDesktopLyrics ? 40 : 148,
            ),
            children: [
              JojoPageHeader(
                title: 'Paroles',
                subtitle: isLoading
                    ? 'Préchargement en cours...'
                    : (lyrics?.artist ?? widget.mediaItem.artist ?? ''),
                leading: JojoIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                trailing: JojoIconButton(
                  icon: Icons.refresh_rounded,
                  onPressed: () {
                    setState(() {
                      _lyricsFuture = _loadLyrics(forceRefresh: true);
                    });
                  },
                ),
              ),
              const SizedBox(height: 18),
              if (!useDesktopLyrics) ...[
                JojoHeroPanel(
                  label: 'Mode paroles',
                  title: widget.mediaItem.title,
                  subtitle: widget.mediaItem.artist ?? 'Artiste inconnu',
                  artworkUrl: widget.mediaItem.artUri?.toString(),
                  accentColor: const Color(0xFF18413F),
                  metadata: [
                    if (isLoading) 'Chargement',
                    if (!isLoading && items.isNotEmpty) '${items.length} lignes',
                  ],
                ),
                const SizedBox(height: 18),
              ] else
                JojoSurfaceCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.mediaItem.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.mediaItem.artist ?? 'Artiste inconnu',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _DesktopMetaChip(
                            label: isLoading
                                ? 'Chargement'
                                : '${items.length} lignes',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              if (isLoading)
                const JojoSurfaceCard(
                  child: SizedBox(
                    height: 260,
                    child: Center(
                      child: CircularProgressIndicator(color: JojoColors.primary),
                    ),
                  ),
                )
              else if (snapshot.hasError)
                JojoStateMessage(
                  icon: Icons.lyrics_outlined,
                  message: 'Impossible de charger les paroles: ${snapshot.error}',
                )
              else if (items.isEmpty)
                const JojoStateMessage(
                  icon: Icons.lyrics_outlined,
                  message: 'Aucune parole trouvée pour ce morceau.',
                )
              else
                JojoSurfaceCard(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
                  child: Column(
                    children: [
                      for (final line in items) ...[
                        Text(
                          line,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<LyricsData?> _loadLyrics({bool forceRefresh = false}) {
    return ref
        .read(playerControllerProvider)
        .fetchLyricsForMediaItem(
          widget.mediaItem,
          forceRefresh: forceRefresh,
        );
  }

  List<String> _extractDisplayLines(LyricsData? lyrics) {
    final source = (lyrics?.syncedLyrics?.trim().isNotEmpty ?? false)
        ? lyrics!.syncedLyrics!
        : (lyrics?.plainLyrics ?? '');
    return source
        .split('\n')
        .map(
          (line) => line
              .replaceAll(RegExp(r'\[[^\]]+\]'), '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

class _DesktopMetaChip extends StatelessWidget {
  const _DesktopMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: JojoColors.surfaceBright,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: JojoColors.mutedStrong,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
