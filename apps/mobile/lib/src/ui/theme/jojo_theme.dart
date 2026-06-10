import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class JojoColors {
  static const canvas = Colors.black;
  static const surface = Color(0x14FFFFFF); // 8% white glass
  static const surfaceRaised = Color(0x1FFFFFFF); // 12% white glass
  static const surfaceBright = Color(0x29FFFFFF); // 16% white glass
  static const line = Color(0x1FFFFFFF);
  static const primary = Colors.white;
  static const primaryStrong = Colors.white;
  static const secondary = Color(0xFFFE8A3E);
  static const tertiary = Color(0xFF5FD1FF);
  static const danger = Color(0xFFFF6B6B);
  static const text = Colors.white;
  static const muted = Color(0x80FFFFFF); // 50% white
  static const mutedStrong = Color(0xB3FFFFFF); // 70% white
}

ThemeData buildJojoTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      primaryContainer: Color(0x29FFFFFF),
      secondary: JojoColors.secondary,
      secondaryContainer: Color(0x1FFFFFFF),
      tertiary: JojoColors.tertiary,
      surface: Colors.black,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: Color(0xB3FFFFFF),
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
      backgroundColor: Colors.black,
      height: 64,
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
        borderSide: const BorderSide(color: Colors.white, width: 1.2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF0D0D0D),
      modalBackgroundColor: Color(0xFF0D0D0D),
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
      backgroundColor: const Color(0xFF161616),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}
