import 'package:flutter/material.dart';

/// The Radar dark "ops-room" theme.
class RadarTheme {
  RadarTheme._();

  // Core palette.
  static const Color ink = Color(0xFF0A0E1A); // page background
  static const Color panel = Color(0xFF111827); // cards / panels
  static const Color panelHigh = Color(0xFF1B2437); // raised surfaces
  static const Color stroke = Color(0xFF2A3648); // hairlines
  static const Color textPrimary = Color(0xFFF3F6FB);
  static const Color textDim = Color(0xFF93A1B7);

  // Accents.
  static const Color radar = Color(0xFF3DFFA2); // live green
  static const Color pi = Color(0xFF8E6BFF); // Pi purple
  static const Color gold = Color(0xFFF5C043); // bounties / boosts
  static const Color alert = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF4CC3FF);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.dark(
      surface: ink,
      primary: radar,
      secondary: pi,
      error: alert,
      tertiary: gold,
      onSurface: textPrimary,
      onPrimary: ink,
      onSecondary: textPrimary,
      onTertiary: ink,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
        fontFamily: 'Roboto',
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: stroke),
        ),
      ),
      dividerTheme: const DividerThemeData(color: stroke, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: radar),
        ),
        hintStyle: const TextStyle(color: textDim),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: panelHigh,
        selectedColor: radar.withValues(alpha: 0.18),
        side: const BorderSide(color: stroke),
        labelStyle: const TextStyle(color: textPrimary),
        secondaryLabelStyle: const TextStyle(color: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: radar.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? radar : textDim,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              color: states.contains(WidgetState.selected) ? radar : textDim,
            )),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: radar,
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: stroke),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: radar),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: panelHigh,
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: stroke),
        ),
      ),
    );
  }
}

/// Screen-size buckets for the responsive shell.
enum WindowSize { compact, medium, expanded }

WindowSize windowSizeFor(double width) {
  if (width < 640) return WindowSize.compact;
  if (width < 1024) return WindowSize.medium;
  return WindowSize.expanded;
}
