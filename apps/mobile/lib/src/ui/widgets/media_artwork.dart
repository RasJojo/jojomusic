import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/jojo_theme.dart';

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    this.url,
    this.size = 56,
    this.borderRadius = 12,
    this.icon = Icons.music_note,
    this.backgroundColor = const Color(0xFF1A4A45),
    this.isCircular = false,
  });

  final String? url;
  final double size;
  final double borderRadius;
  final IconData icon;
  final Color backgroundColor;
  final bool isCircular;

  @override
  Widget build(BuildContext context) {
    final radius = isCircular ? size / 2 : borderRadius;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [backgroundColor, JojoColors.surfaceBright],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: size * 0.5,
              height: size * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Icon(icon, color: JojoColors.text),
        ],
      ),
    );

    if (url == null || url!.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, value) => Stack(
          fit: StackFit.expand,
          children: [
            placeholder,
            Center(
              child: SizedBox(
                width: size * 0.24,
                height: size * 0.24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
        fadeInDuration: const Duration(milliseconds: 180),
        errorWidget: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}
