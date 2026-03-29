import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_models.dart';
import '../../state/library_controller.dart';
import '../../state/player_controller.dart';
import '../theme/jojo_theme.dart';
import 'media_artwork.dart';

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
    final lead = topColor ?? const Color(0xFF13312D);
    return Scaffold(
      bottomNavigationBar: bottomNavigationBar,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [lead, const Color(0xFF091617), JojoColors.canvas],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _BackdropGlow(
              alignment: Alignment.topRight,
              color: Color(0x3D61F5B9),
              size: 260,
            ),
            const _BackdropGlow(
              alignment: Alignment.topLeft,
              color: Color(0x20FE8A3E),
              size: 220,
            ),
            SafeArea(
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
          ],
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
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
    required this.subtitle,
    super.key,
    this.label,
    this.artworkUrl,
    this.circularArtwork = false,
    this.accentColor = const Color(0xFF13312D),
    this.actions = const [],
    this.metadata = const [],
  });

  final String title;
  final String subtitle;
  final String? label;
  final String? artworkUrl;
  final bool circularArtwork;
  final Color accentColor;
  final List<Widget> actions;
  final List<String> metadata;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.96),
            const Color(0xFF0A1718),
          ],
        ),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.24),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
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
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
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
    return Container(
      decoration: BoxDecoration(
        color: JojoColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class JojoPosterCard extends StatefulWidget {
  const JojoPosterCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
    this.artworkUrl,
    this.badge,
    this.width = 176,
    this.height = 176,
    this.circularArtwork = false,
    this.backgroundColor = JojoColors.surface,
  });

  final String title;
  final String subtitle;
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
        ? JojoColors.primary.withValues(alpha: 0.42)
        : _hovered
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0x1FFFFFFF);
    final cardColor = _hovered
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.035),
            widget.backgroundColor,
          )
        : widget.backgroundColor;
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
              boxShadow: [
                if (_hovered || _pressed)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 22,
                    offset: const Offset(0, 14),
                  ),
              ],
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
                        size: widget.height,
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
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
    this.dense = false,
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
                            color: JojoColors.primary,
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
              ? JojoColors.primary.withValues(alpha: 0.72)
              : _hovered
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0x14FFFFFF);
          final tileColor = isCurrent
              ? const Color(0x8A12312D)
              : _hovered
              ? const Color(0x8F122122)
              : const Color(0x660C1718);

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
                          ? JojoColors.primary
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
                                  ? JojoColors.primary
                                  : JojoColors.mutedStrong,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    MediaArtwork(
                      url:
                          widget.track.artworkUrl ??
                          widget.track.artistImageUrl,
                      size: widget.dense ? 52 : 58,
                      borderRadius: 16,
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: isCurrent ? JojoColors.primary : null,
                              ),
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isCurrent
                                    ? JojoColors.text.withValues(alpha: 0.86)
                                    : null,
                              ),
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
          color: isCurrent ? const Color(0x8A12312D) : const Color(0x660C1718),
          border: Border.all(
            color: isCurrent
                ? JojoColors.primary.withValues(alpha: 0.72)
                : const Color(0x14FFFFFF),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isCurrent ? JojoColors.primary : JojoColors.mutedStrong,
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isCurrent ? JojoColors.primary : null,
                    ),
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
              color: isCurrent ? JojoColors.primary : JojoColors.mutedStrong,
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
                color: JojoColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: JojoColors.primary.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.playlist_add_check_circle_rounded,
                    size: 16,
                    color: JojoColors.primary,
                  ),
                  if (playlistCount > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$playlistCount',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: JojoColors.primary,
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
              color: JojoColors.surfaceBright,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: JojoColors.primary),
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
          child: useInlineDesktopHeader
              ? Row(
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: JojoColors.muted),
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.headlineMedium),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ],
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
      color: const Color(0x660B1718),
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

class _BackdropGlow extends StatelessWidget {
  const _BackdropGlow({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent]),
          ),
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
