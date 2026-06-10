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

    return ShellChrome(
      topColor: const Color(0xFF18383A),
      popToRootOnNavigate: true,
      onProfilePressed: () => openProfileScreen(context),
      child: FutureBuilder<LyricsData?>(
        future: _lyricsFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState != ConnectionState.done;
          final lyrics = snapshot.data;
          final hasSynced =
              lyrics?.syncedLyrics?.trim().isNotEmpty ?? false;

          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Column(
                  children: [
                    JojoPageHeader(
                      title: 'Paroles',
                      subtitle: isLoading
                          ? 'Préchargement en cours...'
                          : (lyrics?.artist ??
                              widget.mediaItem.artist ??
                              ''),
                      leading: JojoIconButton(
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      trailing: JojoIconButton(
                        icon: Icons.refresh_rounded,
                        onPressed: () {
                          setState(() {
                            _lyricsFuture =
                                _loadLyrics(forceRefresh: true);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!useDesktopLyrics)
                      JojoHeroPanel(
                        label: 'Mode paroles',
                        title: widget.mediaItem.title,
                        subtitle:
                            widget.mediaItem.artist ?? 'Artiste inconnu',
                        artworkUrl: widget.mediaItem.artUri?.toString(),
                        accentColor: const Color(0xFF18413F),
                        metadata: [
                          if (isLoading) 'Chargement',
                          if (!isLoading && hasSynced) 'Synchronisées',
                          if (!isLoading && !hasSynced && lyrics != null)
                            'Texte brut',
                        ],
                      )
                    else
                      JojoSurfaceCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.mediaItem.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.mediaItem.artist ??
                                        'Artiste inconnu',
                                    style:
                                        Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            ),
                            if (!isLoading && hasSynced)
                              _MetaChip(label: 'Synchronisées'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: JojoColors.primary,
                        ),
                      )
                    : snapshot.hasError
                    ? JojoStateMessage(
                        icon: Icons.lyrics_outlined,
                        message:
                            'Impossible de charger les paroles: ${snapshot.error}',
                      )
                    : lyrics == null ||
                          ((lyrics.plainLyrics?.isEmpty ?? true) &&
                              !hasSynced)
                    ? const JojoStateMessage(
                        icon: Icons.lyrics_outlined,
                        message: 'Aucune parole trouvée pour ce morceau.',
                      )
                    : hasSynced
                    ? _SyncedLyricsView(lyrics: lyrics)
                    : _PlainLyricsView(
                        lyrics: lyrics,
                        bottomPadding:
                            useDesktopLyrics ? 40 : 148,
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
}

// ─── Synced (LRC) Lyrics View ─────────────────────────────────────────────────

class _LrcLine {
  const _LrcLine({required this.timestamp, required this.text});
  final Duration timestamp;
  final String text;
}

List<_LrcLine> _parseLrc(String lrc) {
  final lines = <_LrcLine>[];
  for (final rawLine in lrc.split('\n')) {
    final match =
        RegExp(r'\[(\d+):(\d+)[\.:](\d+)\](.*)').firstMatch(rawLine);
    if (match == null) continue;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final subRaw = match.group(3)!;
    // BUG #9 fix: handle 1-, 2-, and 3-digit sub-second fields correctly.
    //   1 digit  → tenths of a second  → multiply by 100 to get ms
    //   2 digits → centiseconds        → multiply by 10 to get ms
    //   3 digits → milliseconds        → use as-is
    // The old code used padRight(2,'0').substring(0,2) which silently
    // truncated 3-digit values (e.g. "123" → "12" → 120 ms instead of 123 ms).
    final int milliseconds;
    if (subRaw.length == 3) {
      milliseconds = int.parse(subRaw);
    } else if (subRaw.length == 2) {
      milliseconds = int.parse(subRaw) * 10;
    } else {
      milliseconds = int.parse(subRaw) * 100;
    }
    final text = match.group(4)!.trim();
    if (text.isEmpty) continue;
    lines.add(
      _LrcLine(
        timestamp: Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        ),
        text: text,
      ),
    );
  }
  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return lines;
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  const _SyncedLyricsView({required this.lyrics});
  final LyricsData lyrics;

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  late final List<_LrcLine> _lines;
  late final List<GlobalKey> _lineKeys;
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _lines = _parseLrc(widget.lyrics.syncedLyrics ?? '');
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ref.watch(playbackStateProvider).asData?.value.updatePosition ??
        Duration.zero;

    int newIndex = -1;
    for (int i = _lines.length - 1; i >= 0; i--) {
      if (position >= _lines[i].timestamp) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }

    if (_lines.isEmpty) {
      return _PlainLyricsView(lyrics: widget.lyrics, bottomPadding: 148);
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 160),
      child: Column(
        children: [
          for (int i = 0; i < _lines.length; i++)
            GestureDetector(
              key: _lineKeys[i],
              onTap: () => ref
                  .read(playerControllerProvider)
                  .seek(_lines[i].timestamp),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                style: (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
                  color: i == _currentIndex
                      ? JojoColors.text
                      : JojoColors.muted,
                  fontWeight: i == _currentIndex
                      ? FontWeight.w800
                      : FontWeight.w600,
                  fontSize: i == _currentIndex ? 22 : 18,
                  height: 1.55,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(_lines[i].text, textAlign: TextAlign.center),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _scrollToCurrent() {
    if (_currentIndex < 0 || !mounted) return;
    final key = _lineKeys[_currentIndex];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.35,
      );
    }
  }
}

// ─── Plain Lyrics View ────────────────────────────────────────────────────────

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.lyrics, this.bottomPadding = 40});
  final LyricsData lyrics;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final lines = _extractDisplayLines(lyrics);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomPadding),
      child: JojoSurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
        child: Column(
          children: [
            for (final line in lines) ...[
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
    );
  }

  static List<String> _extractDisplayLines(LyricsData lyrics) {
    final source = (lyrics.syncedLyrics?.trim().isNotEmpty ?? false)
        ? lyrics.syncedLyrics!
        : (lyrics.plainLyrics ?? '');
    return source
        .split('\n')
        .map(
          (line) =>
              line.replaceAll(RegExp(r'\[[^\]]+\]'), '').trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
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
