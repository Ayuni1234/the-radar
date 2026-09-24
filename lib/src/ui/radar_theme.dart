import 'package:flutter/material.dart';

/// Which visual mode the app renders in.
enum RadarBrightness { dark, light }

/// One cohesive color palette. The dark palette is the original "ops-room"
/// look; the light palette mirrors it with clean whites, light greys and
/// high-contrast ink text while keeping the same accent identities.
class RadarPalette {
  const RadarPalette({
    required this.isDark,
    required this.ink,
    required this.panel,
    required this.panelHigh,
    required this.stroke,
    required this.textPrimary,
    required this.textDim,
    required this.radar,
    required this.pi,
    required this.gold,
    required this.alert,
    required this.info,
    required this.onAccent,
  });

  final bool isDark;

  // Surfaces.
  final Color ink; // page background
  final Color panel; // cards / panels
  final Color panelHigh; // raised surfaces / inputs
  final Color stroke; // hairlines
  final Color textPrimary;
  final Color textDim;

  // Accents.
  final Color radar; // live green
  final Color pi; // Pi purple
  final Color gold; // bounties / boosts
  final Color alert;
  final Color info;

  /// Readable text/icon color on top of the accent colors (dark ink on the
  /// neon dark-mode green; white on the deepened light-mode green).
  final Color onAccent;

  static final RadarPalette dark = RadarPalette(
    isDark: true,
    ink: const Color(0xFF0A0E1A),
    panel: const Color(0xFF111827),
    panelHigh: const Color(0xFF1B2437),
    stroke: const Color(0xFF2A3648),
    textPrimary: const Color(0xFFF3F6FB),
    textDim: const Color(0xFF93A1B7),
    radar: const Color(0xFF3DFFA2),
    pi: const Color(0xFF8E6BFF),
    gold: const Color(0xFFF5C043),
    alert: const Color(0xFFFF6B6B),
    info: const Color(0xFF4CC3FF),
    onAccent: const Color(0xFF0A0E1A),
  );

  static final RadarPalette light = RadarPalette(
    isDark: false,
    ink: const Color(0xFFF5F7FA),
    panel: const Color(0xFFFFFFFF),
    panelHigh: const Color(0xFFE9EEF5),
    stroke: const Color(0xFFD3DCE8),
    textPrimary: const Color(0xFF0F172A),
    textDim: const Color(0xFF5A6B85),
    // Accents deepen slightly for contrast on white surfaces.
    radar: const Color(0xFF0C9B6C),
    pi: const Color(0xFF6C4BD8),
    gold: const Color(0xFFB07C10),
    alert: const Color(0xFFD64550),
    info: const Color(0xFF1D7FC4),
    onAccent: const Color(0xFFFFFFFF),
  );
}

/// The Radar themes. Colors are exposed as getters over [RadarTheme.current]
/// so the ~1,200 existing `RadarTheme.x` call sites adapt automatically when
/// the active palette changes — no per-widget threading, no hardcoded
/// conflicts. Widgets reading these getters must not be `const`
/// (the analyzer enforces this) so theme switches repaint them.
class RadarTheme {
  RadarTheme._();

  /// The palette the current frame renders with. Mutated by the theme
  /// controller *before* MaterialApp builds with the matching [ThemeData];
  /// because MaterialApp rebuilds its subtree on a theme change, every
  /// getter read during build picks up the new values.
  static RadarPalette current = RadarPalette.dark;

  // Core palette (active mode).
  static Color get ink => current.ink;
  static Color get panel => current.panel;
  static Color get panelHigh => current.panelHigh;
  static Color get stroke => current.stroke;
  static Color get textPrimary => current.textPrimary;
  static Color get textDim => current.textDim;

  // Accents (active mode).
  static Color get radar => current.radar;
  static Color get pi => current.pi;
  static Color get gold => current.gold;
  static Color get alert => current.alert;
  static Color get info => current.info;

  /// Text/icon color that stays readable on top of accent fills.
  static Color get onAccent => current.onAccent;

  /// Dark "ops-room" theme.
  static ThemeData get dark => themeFor(RadarBrightness.dark);

  /// Light theme — clean whites, light greys, high-contrast text.
  static ThemeData get light => themeFor(RadarBrightness.light);

  /// Full [ThemeData] for a mode.
  static ThemeData themeFor(RadarBrightness mode) {
    final p =
        mode == RadarBrightness.dark ? RadarPalette.dark : RadarPalette.light;
    final base = p.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final scheme = p.isDark
        ? ColorScheme.dark(
            surface: p.ink,
            primary: p.radar,
            secondary: p.pi,
            error: p.alert,
            tertiary: p.gold,
            onSurface: p.textPrimary,
            onPrimary: p.onAccent,
            onSecondary: p.textPrimary,
            onTertiary: p.ink,
          )
        : ColorScheme.light(
            surface: p.ink,
            primary: p.radar,
            secondary: p.pi,
            error: p.alert,
            tertiary: p.gold,
            onSurface: p.textPrimary,
            onPrimary: p.onAccent,
            onSecondary: p.textPrimary,
            onTertiary: p.onAccent,
          );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.ink,
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
        fontFamily: 'Roboto',
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.stroke),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.stroke, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panelHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.radar),
        ),
        hintStyle: TextStyle(color: p.textDim),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.panelHigh,
        selectedColor: p.radar.withValues(alpha: p.isDark ? 0.18 : 0.14),
        side: BorderSide(color: p.stroke),
        labelStyle: TextStyle(color: p.textPrimary),
        secondaryLabelStyle: TextStyle(color: p.onAccent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.panel,
        indicatorColor: p.radar.withValues(alpha: p.isDark ? 0.18 : 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? p.radar
                  : p.textDim,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              color: states.contains(WidgetState.selected)
                  ? p.radar
                  : p.textDim,
            )),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: p.textPrimary),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.radar,
          foregroundColor: p.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.stroke),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme:
          TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.radar)),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.panelHigh,
        contentTextStyle: TextStyle(color: p.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.stroke),
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
