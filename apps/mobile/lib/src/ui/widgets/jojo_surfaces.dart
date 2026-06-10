import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/artwork_cache.dart';
import '../../models/app_models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../theme/jojo_theme.dart';
import 'media_artwork.dart';

// ─── iTunes artwork cache ─────────────────────────────────────────────────────

final _itunesCache = <String, String?>{};
final _itunesInFlight = <String, Future<String?>>{};

final _itunesDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 6),
  receiveTimeout: const Duration(seconds: 6),
));

// Strip "& ...", "feat. ...", etc. to get the primary artist
String _primaryArtist(String artist) =>
    artist.split(RegExp(r'\s*(?:&|,|feat\.?|ft\.?|featuring|avec)\s*', caseSensitive: false)).first.trim();

Future<String?> _fetchItunesArtwork(String artist, String title) async {
  final key = '$artist\x00$title';
  if (_itunesCache.containsKey(key)) return _itunesCache[key];
  if (_itunesInFlight.containsKey(key)) return _itunesInFlight[key];

  final future = () async {
    final primary = _primaryArtist(artist);
    final queries = <String>{
      if (primary != artist) '$primary $title',
      '$artist $title',
      title,
    };
    for (final q in queries) {
      try {
        final response = await _itunesDio.get<Map<String, dynamic>>(
          'https://itunes.apple.com/search',
          queryParameters: {'term': q, 'entity': 'song', 'limit': '5', 'media': 'music'},
        );
        final results = (response.data?['results'] as List<dynamic>?) ?? [];
        if (results.isNotEmpty) {
          final url = results.first['artworkUrl100'] as String?;
          if (url != null) return url.replaceFirst('100x100bb', '600x600bb');
        }
      } catch (_) {}
    }
    return null;
  }();

  _itunesInFlight[key] = future;
  final result = await future;
  _itunesCache[key] = result;
  _itunesInFlight.remove(key);
  return result;
}

class _TrackArtwork extends StatefulWidget {
  const _TrackArtwork({required this.track, required this.size});
  final Track track;
  final double size;

  @override
  State<_TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends State<_TrackArtwork> {
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_TrackArtwork old) {
    super.didUpdateWidget(old);
    if (old.track.trackKey != widget.track.trackKey) {
      _resolvedUrl = null;
      _resolve();
    }
  }

  void _resolve() {
    // 1. Direct URL from DB
    final direct = widget.track.displayArtworkUrl;
    if (direct != null) {
      _resolvedUrl = direct;
      return;
    }
    // 2. URL resolved at playback time (thumbnailUrl from YouTube resolve)
    final cached = resolvedArtworkCache[widget.track.trackKey];
    if (cached != null) {
      _resolvedUrl = cached;
      return;
    }
    // 3. iTunes fallback (async)
    final itunesKey = '${widget.track.artist}\x00${widget.track.title}';
    if (_itunesCache.containsKey(itunesKey)) {
      _resolvedUrl = _itunesCache[itunesKey];
      return;
    }
    _fetchItunesArtwork(widget.track.artist, widget.track.title).then((url) {
      if (mounted) setState(() => _resolvedUrl = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MediaArtwork(url: _resolvedUrl, size: widget.size, borderRadius: 16);
  }
}

class JojoPageScaffold extends StatelessWidget {
  const JojoPageScaffold({
    required this.child,
    super.key,
    this.topColor,
    this.bottomNavigationBar,
    this.maxContentWidth = 1320,
  });

  final Widget child;
  final Color? topColor;
  final Widget? bottomNavigationBar;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: bottomNavigationBar,
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: maxContentWidth == null
            ? child
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth!),
                  child: child,
                ),
              ),
      ),
    );
  }
}

class JojoSectionHeading extends StatelessWidget {
  const JojoSectionHeading({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
      ],
    );
  }
}

class JojoHeroPanel extends StatelessWidget {
  const JojoHeroPanel({
    required this.title,
    super.key,
    this.subtitle,
    this.label,
    this.artworkUrl,
    this.circularArtwork = false,
    this.accentColor = const Color(0xFF13312D),
    this.actions = const [],
    this.metadata = const [],
    this.headerTrailing,
  });

  final String title;
  final String? subtitle;
  final String? label;
  final String? artworkUrl;
  final bool circularArtwork;
  final Color accentColor;
  final List<Widget> actions;
  final List<String> metadata;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null && label!.isNotEmpty)
                      _MetaPill(label: label!, color: Colors.white),
                    if (label != null && label!.isNotEmpty)
                      const SizedBox(height: 14),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: metadata
                            .map(
                              (item) => _MetaPill(
                                label: item,
                                color: JojoColors.primary,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 18),
              MediaArtwork(
                url: artworkUrl,
                size: 124,
                borderRadius: 26,
                isCircular: circularArtwork,
                backgroundColor: const Color(0x33212424),
                icon: circularArtwork ? Icons.person : Icons.music_note,
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: actions),
          ],
        ],
      ),
        ),
      ),
    );

    if (headerTrailing == null) return card;
    return Stack(
      children: [
        card,
        Positioned(
          top: 10,
          right: 10,
          child: headerTrailing!,
        ),
      ],
    );
  }
}

class JojoSurfaceCard extends StatelessWidget {
  const JojoSurfaceCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.radius = 26,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class JojoPosterCard extends StatefulWidget {
  const JojoPosterCard({
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.artworkUrl,
    this.badge,
    this.width = 176,
    this.height = 176,
    this.circularArtwork = false,
    this.backgroundColor = JojoColors.surface,
  });

  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final String? badge;
  final double width;
  final double height;
  final bool circularArtwork;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  State<JojoPosterCard> createState() => _JojoPosterCardState();
}

class _JojoPosterCardState extends State<JojoPosterCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _pressed
        ? Colors.white.withValues(alpha: 0.42)
        : _hovered
        ? Colors.white.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.10);
    final cardColor = _hovered
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.07);
    return SizedBox(
      width: widget.width,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : (_hovered ? 1.012 : 1),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: cardColor,
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      MediaArtwork(
                        url: widget.artworkUrl,
                        size: math.min(widget.height, widget.width - 28.0),
                        borderRadius: 20,
                        isCircular: widget.circularArtwork,
                        icon: widget.circularArtwork
                            ? Icons.person
                            : Icons.music_note,
                      ),
                      if (widget.badge != null && widget.badge!.isNotEmpty)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _MetaPill(
                            label: widget.badge!,
                            color: JojoColors.secondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                widget.subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JojoTrackTile extends ConsumerStatefulWidget {
  const JojoTrackTile({
    required this.track,
    required this.onTap,
    super.key,
    this.index,
    this.onMore,
    this.queueLabel,
    this.trailing,
    this.statusIndicator,
    this.dense = true,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final int? index;
  final String? queueLabel;
  final Widget? trailing;
  final Widget? statusIndicator;
  final bool dense;

  @override
  ConsumerState<JojoTrackTile> createState() => _JojoTrackTileState();
}

class _JojoTrackTileState extends ConsumerState<JojoTrackTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).asData?.value;
    final isCurrent =
        mediaItem != null && mediaItemTrackKey(mediaItem) == widget.track.trackKey;
    final library = ref.watch(libraryControllerProvider).asData?.value;
    final isLiked = library?.isLiked(widget.track) ?? false;
    final playlistCount = library?.playlistIdsForTrack(widget.track).length ?? 0;

    return AnimatedScale(
      scale: _pressed ? 0.99 : (_hovered ? 1.006 : 1),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: ValueListenableBuilder<String?>(
        valueListenable: pendingTrackKeyListenable,
        builder: (context, pendingTrackKey, _) {
          final isLoading =
              pendingTrackKey == widget.track.trackKey && !isCurrent;
          final actionWidget = isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: JojoColors.secondary,
                  ),
                )
              : widget.trailing ??
                    (isCurrent
                        ? const Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.white,
                          )
                        : widget.onMore != null
                        ? IconButton(
                            onPressed: widget.onMore,
                            icon: const Icon(Icons.more_horiz_rounded),
                          )
                        : null);
          final libraryWidget =
              isLiked || playlistCount > 0
              ? _TrackLibraryIndicators(
                  isLiked: isLiked,
                  playlistCount: playlistCount,
                )
              : null;
          final borderColor = isLoading
              ? JojoColors.secondary.withValues(alpha: 0.78)
              : isCurrent
              ? Colors.white.withValues(alpha: 0.60)
              : _hovered
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08);
          final tileColor = isCurrent
              ? Colors.white.withValues(alpha: 0.12)
              : _hovered
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.04);

          return InkWell(
            onTap: widget.onTap,
            onHover: (value) {
              setState(() => _hovered = value);
              if (value) {
                unawaited(
                  ref.read(playerControllerProvider).prewarmTrack(widget.track),
                );
              }
            },
            onHighlightChanged: (value) => setState(() => _pressed = value),
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              padding: EdgeInsets.symmetric(
                horizontal: widget.dense ? 10 : 12,
                vertical: widget.dense ? 6 : 8,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: tileColor,
                border: Border.all(color: borderColor),
                boxShadow: [
                  if (_hovered || isCurrent)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: widget.dense ? 34 : 40,
                    decoration: BoxDecoration(
                      color: isLoading
                          ? JojoColors.secondary
                          : isCurrent
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 9),
                  if (widget.index != null)
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${widget.index! + 1}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: isCurrent
                                  ? Colors.white
                                  : JojoColors.mutedStrong,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    _TrackArtwork(
                      track: widget.track,
                      size: widget.dense ? 52 : 58,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.queueLabel ??
                              [widget.track.artist, widget.track.album]
                                  .whereType<String>()
                                  .where((value) => value.isNotEmpty)
                                  .join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.statusIndicator != null ||
                      libraryWidget != null ||
                      actionWidget != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.statusIndicator != null) ...[
                          widget.statusIndicator!,
                          if (libraryWidget != null || actionWidget != null)
                            const SizedBox(width: 6),
                        ],
                        if (libraryWidget != null) ...[
                          libraryWidget,
                          if (actionWidget != null) const SizedBox(width: 6),
                        ],
                        ...switch (actionWidget) {
                          final action? => [action],
                          null => [],
                        },
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class JojoQueueTile extends StatelessWidget {
  const JojoQueueTile({
    required this.item,
    required this.index,
    required this.onTap,
    this.isCurrent = false,
    super.key,
  });

  final MediaItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: isCurrent
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: isCurrent
                ? Colors.white.withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isCurrent ? Colors.white : JojoColors.mutedStrong,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 10),
            MediaArtwork(
              url: item.artUri?.toString(),
              size: 58,
              borderRadius: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [item.artist, item.album]
                        .whereType<String>()
                        .where((value) => value.isNotEmpty)
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isCurrent ? Icons.graphic_eq_rounded : Icons.chevron_right_rounded,
              color: isCurrent ? Colors.white : JojoColors.mutedStrong,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackLibraryIndicators extends StatelessWidget {
  const _TrackLibraryIndicators({
    required this.isLiked,
    required this.playlistCount,
  });

  final bool isLiked;
  final int playlistCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLiked)
          Tooltip(
            message: 'Déjà dans les favoris',
            child: Icon(
              Icons.favorite_rounded,
              size: 18,
              color: const Color(0xFFFF6B8E),
            ),
          ),
        if (isLiked && playlistCount > 0) const SizedBox(width: 6),
        if (playlistCount > 0)
          Tooltip(
            message: playlistCount == 1
                ? 'Déjà dans 1 playlist'
                : 'Déjà dans $playlistCount playlists',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.playlist_add_check_circle_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  if (playlistCount > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$playlistCount',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class JojoStateMessage extends StatelessWidget {
  const JojoStateMessage({
    required this.message,
    super.key,
    this.icon = Icons.music_note_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return JojoSurfaceCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class JojoPageHeader extends StatelessWidget {
  const JojoPageHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final useInlineDesktopHeader =
        mediaQuery.size.width >= 1180 && mediaQuery.size.shortestSide >= 700;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 14)],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: useInlineDesktopHeader
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
      ],
    );
  }
}

class JojoIconButton extends StatelessWidget {
  const JojoIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      shape: const CircleBorder(),
      child: IconButton(onPressed: onPressed, icon: Icon(icon)),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}


String formatCompactDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
