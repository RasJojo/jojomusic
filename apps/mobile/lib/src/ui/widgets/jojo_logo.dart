import 'package:flutter/material.dart';

class JojoLogo extends StatelessWidget {
  const JojoLogo({
    super.key,
    this.size = 48,
    this.borderRadius,
    this.backgroundColor,
    this.padding,
  });

  final double size;
  final double? borderRadius;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final useCircle = borderRadius == null;
    final logo = useCircle
        ? ClipOval(
            child: Image.asset(
              'assets/branding/jojomusique-logo.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius!),
            child: Image.asset(
              'assets/branding/jojomusique-logo.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );

    if (backgroundColor == null && padding == null) {
      return logo;
    }

    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: useCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: useCircle ? null : BorderRadius.circular(borderRadius!),
      ),
      child: logo,
    );
  }
}
