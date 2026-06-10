import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/jojo_theme.dart';

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    this.url,
    this.fallbackUrl,
    this.size = 56,
    this.borderRadius = 12,
    this.icon = Icons.music_note,
    this.backgroundColor = const Color(0xFF1A4A45),
    this.isCircular = false,
  });

  final String? url;
  final String? fallbackUrl;
  final double size;
  final double borderRadius;
  final IconData icon;
  final Color backgroundColor;
  final bool isCircular;

  @override
  Widget build(BuildContext context) {
    final radius = isCircular ? size / 2 : borderRadius;
    final placeholder = _Placeholder(
      size: size,
      radius: radius,
      backgroundColor: backgroundColor,
      icon: icon,
    );

    final effectiveUrl = (url != null && url!.isNotEmpty) ? url : fallbackUrl;

    if (effectiveUrl == null || effectiveUrl.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: effectiveUrl,
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
        errorWidget: (context, error, stackTrace) {
          // Primary URL failed — try the YouTube thumbnail fallback
          final fb = fallbackUrl;
          if (fb != null && fb.isNotEmpty && fb != effectiveUrl) {
            return CachedNetworkImage(
              imageUrl: fb,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (context, error, stack) => placeholder,
            );
          }
          return placeholder;
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.size,
    required this.radius,
    required this.backgroundColor,
    required this.icon,
  });

  final double size;
  final double radius;
  final Color backgroundColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
}
