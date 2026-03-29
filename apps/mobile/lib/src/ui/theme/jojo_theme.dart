import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class JojoColors {
  static const canvas = Color(0xFF041010);
  static const surface = Color(0xFF0A1718);
  static const surfaceRaised = Color(0xFF102224);
  static const surfaceBright = Color(0xFF153033);
  static const line = Color(0x1FFFFFFF);
  static const primary = Color(0xFF61F5B9);
  static const primaryStrong = Color(0xFF1ED48F);
  static const secondary = Color(0xFFFE8A3E);
  static const tertiary = Color(0xFF5FD1FF);
  static const text = Color(0xFFF4FFFC);
  static const muted = Color(0xFFA0B8B1);
  static const mutedStrong = Color(0xFFC1D8D2);
}

ThemeData buildJojoTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: JojoColors.primary,
      secondary: JojoColors.secondary,
      surface: JojoColors.surface,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: JojoColors.text,
    ),
  );

  final bodyTextTheme = GoogleFonts.manropeTextTheme(
    base.textTheme,
  ).apply(bodyColor: JojoColors.text, displayColor: JojoColors.text);
  final heading = GoogleFonts.spaceGrotesk(
    color: JojoColors.text,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  return base.copyWith(
    scaffoldBackgroundColor: JojoColors.canvas,
    splashFactory: InkSparkle.splashFactory,
    textTheme: bodyTextTheme.copyWith(
      displayLarge: heading.copyWith(fontSize: 56, fontWeight: FontWeight.w700),
      displayMedium: heading.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: heading.copyWith(fontSize: 34, fontWeight: FontWeight.w700),
      headlineLarge: heading.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: heading.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: heading.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: bodyTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleMedium: bodyTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      bodyLarge: bodyTextTheme.bodyLarge?.copyWith(
        color: JojoColors.mutedStrong,
        height: 1.35,
      ),
      bodyMedium: bodyTextTheme.bodyMedium?.copyWith(
        color: JojoColors.mutedStrong,
        height: 1.35,
      ),
      bodySmall: bodyTextTheme.bodySmall?.copyWith(
        color: JojoColors.muted,
        height: 1.3,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: JojoColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: JojoColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    dividerTheme: const DividerThemeData(
      color: JojoColors.line,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: JojoColors.primary,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: bodyTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: JojoColors.text,
        side: const BorderSide(color: JojoColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: JojoColors.text,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF081415),
      height: 84,
      indicatorColor: JojoColors.surfaceBright,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return bodyTextTheme.bodySmall!.copyWith(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? JojoColors.text : JojoColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? JojoColors.text : JojoColors.muted,
          size: 24,
        );
      }),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStateProperty.all(JojoColors.surfaceRaised),
      elevation: WidgetStateProperty.all(0),
      shadowColor: WidgetStateProperty.all(Colors.transparent),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      hintStyle: WidgetStateProperty.all(
        bodyTextTheme.bodyLarge?.copyWith(color: JojoColors.muted),
      ),
      textStyle: WidgetStateProperty.all(
        bodyTextTheme.bodyLarge?.copyWith(color: JojoColors.text),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JojoColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: bodyTextTheme.bodyMedium?.copyWith(color: JojoColors.muted),
      labelStyle: bodyTextTheme.bodyMedium?.copyWith(color: JojoColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: JojoColors.primary, width: 1.2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: JojoColors.surface,
      modalBackgroundColor: JojoColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: JojoColors.text,
      textColor: JojoColors.text,
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: JojoColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}
