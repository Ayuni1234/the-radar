import 'package:flutter/material.dart';

/// Which visual mode the app renders in.
enum RadarBrightness { dark, light }

/// One cohesive color palette.
///
/// The dark palette is the uploaded Stitch design system
/// ("Nocturnal Athletic / Pitchside Radar"): midnight-pitch surfaces, optic
/// pitch green, radar cyan and escrow Pi gold. The light palette is its
/// derived twin — same accents darkened for contrast on light neutrals,
/// same elevation ladder, no new hues.
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
    required this.panelLowest,
    required this.panelHighest,
    required this.lineStrong,
    required this.textFaint,
    required this.greenDeep,
    required this.goldBright,
    required this.cyanDeep,
  });

  final bool isDark;

  // Surfaces — the spec's Surface 0 → 3 ladder.
  final Color ink; // Surface 0 / page canvas
  final Color panelLowest; // deepest well (media, inputs)
  final Color panel; // Surface 1 / cards, sheets
  final Color panelHigh; // Surface 2 / interactive plates
  final Color panelHighest; // chips, raised pills
  final Color stroke; // 1px hairline
  final Color lineStrong; // heavier divider / rim

  final Color textPrimary;
  final Color textDim;
  final Color textFaint;

  // Accents.
  final Color radar; // Optic Pitch Green — live, primary action
  final Color greenDeep; // primary-fixed-dim
  final Color pi; // Escrow Pi Gold — money, bounties
  final Color gold;
  final Color goldBright;
  final Color info; // Radar Cyan — telemetry, GPS, coordinates
  final Color cyanDeep;
  final Color alert;

  /// Readable text/icon color on top of the green accent fill.
  final Color onAccent;

  /// Uploaded spec dark palette (`DESIGN.md` + every screen).
  static const RadarPalette dark = RadarPalette(
    isDark: true,
    ink: Color(0xFF0F131D),
    panelLowest: Color(0xFF0A0E17),
    panel: Color(0xFF1C2029),
    panelHigh: Color(0xFF262A34),
    panelHighest: Color(0xFF31353F),
    stroke: Color(0x14FFFFFF), // rgba(255,255,255,.08)
    lineStrong: Color(0x26FFFFFF), // rgba(255,255,255,.15)
    textPrimary: Color(0xFFDFE2F0),
    textDim: Color(0xFFB9CBB9),
    textFaint: Color(0xFF849584),
    radar: Color(0xFF00FF85),
    greenDeep: Color(0xFF00E476),
    pi: Color(0xFFFDB022),
    gold: Color(0xFFFDB022),
    goldBright: Color(0xFFFFBA48),
    info: Color(0xFF00E5FF),
    cyanDeep: Color(0xFF00DAF3),
    alert: Color(0xFFFF5C5C),
    onAccent: Color(0xFF003919),
  );

  /// Derived light twin: same layout, inverted elevation ladder, accents
  /// deepened just enough to keep AA contrast on light neutrals.
  static const RadarPalette light = RadarPalette(
    isDark: false,
    ink: Color(0xFFF5F7F2),
    panelLowest: Color(0xFFE9EFE6),
    panel: Color(0xFFFFFFFF),
    panelHigh: Color(0xFFEDF2EA),
    panelHighest: Color(0xFFE1E8DD),
    stroke: Color(0xFFD3DCCF),
    lineStrong: Color(0xFFB9C6B5),
    textPrimary: Color(0xFF0C1710),
    textDim: Color(0xFF52665A),
    textFaint: Color(0xFF6F8273),
    radar: Color(0xFF00A85C),
    greenDeep: Color(0xFF00914F),
    pi: Color(0xFF9A6200),
    gold: Color(0xFF9A6200),
    goldBright: Color(0xFFB87A05),
    info: Color(0xFF007C8F),
    cyanDeep: Color(0xFF006C7C),
    alert: Color(0xFFC62828),
    onAccent: Color(0xFFFFFFFF),
  );
}

/// The Radar themes. Colors are exposed as getters over [RadarTheme.current]
/// so every existing `RadarTheme.x` call site adapts automatically when the
/// active palette changes — no per-widget threading.
class RadarTheme {
  RadarTheme._();

  /// The palette the current frame renders with. Mutated by the theme
  /// controller *before* MaterialApp builds with the matching [ThemeData].
  static RadarPalette current = RadarPalette.dark;

  // Core palette (active mode).
  static Color get ink => current.ink;
  static Color get panelLowest => current.panelLowest;
  static Color get panel => current.panel;
  static Color get panelHigh => current.panelHigh;
  static Color get panelHighest => current.panelHighest;
  static Color get stroke => current.stroke;
  static Color get lineStrong => current.lineStrong;
  static Color get textPrimary => current.textPrimary;
  static Color get textDim => current.textDim;
  static Color get textFaint => current.textFaint;

  // Accents (active mode).
  static Color get radar => current.radar;
  static Color get greenDeep => current.greenDeep;
  static Color get pi => current.pi;
  static Color get gold => current.gold;
  static Color get goldBright => current.goldBright;
  static Color get alert => current.alert;
  static Color get info => current.info;
  static Color get cyanDeep => current.cyanDeep;

  /// Text/icon color that stays readable on top of the green accent fill.
  static Color get onAccent => current.onAccent;

  /// Dark "midnight pitch" theme.
  static ThemeData get dark => themeFor(RadarBrightness.dark);

  /// Derived light theme.
  static ThemeData get light => themeFor(RadarBrightness.light);

  /// Full [ThemeData] for a mode.
  static ThemeData themeFor(RadarBrightness mode) {
    final p = mode == RadarBrightness.dark ? RadarPalette.dark : RadarPalette.light;
    final base = p.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final scheme = (p.isDark
            ? ColorScheme.dark(
                surface: p.ink,
                primary: p.radar,
                secondary: p.info,
                error: p.alert,
                tertiary: p.gold,
                onSurface: p.textPrimary,
                onPrimary: p.onAccent,
                onSecondary: p.onAccent,
                onTertiary: p.onAccent,
              )
            : ColorScheme.light(
                surface: p.ink,
                primary: p.radar,
                secondary: p.info,
                error: p.alert,
                tertiary: p.gold,
                onSurface: p.textPrimary,
                onPrimary: p.onAccent,
                onSecondary: p.onAccent,
                onTertiary: p.onAccent,
              ))
        .copyWith(
      surfaceContainerLowest: p.panelLowest,
      surfaceContainerLow: p.panel,
      surfaceContainer: p.panel,
      surfaceContainerHigh: p.panelHigh,
      surfaceContainerHighest: p.panelHighest,
      outline: p.textFaint,
      outlineVariant: p.stroke,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.ink,
      canvasColor: p.ink,
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
        fontFamily: RadarFonts.body,
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.stroke),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.stroke, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panelHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: p.lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: p.lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: p.info),
        ),
        hintStyle: TextStyle(color: p.textDim.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.panelHighest,
        selectedColor: p.radar.withValues(alpha: p.isDark ? 0.16 : 0.14),
        side: BorderSide(color: p.stroke),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          color: p.textPrimary,
          fontFamily: RadarFonts.label,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.panelLowest,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? p.radar
                  : p.textDim,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              fontFamily: RadarFonts.label,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: states.contains(WidgetState.selected)
                  ? p.radar
                  : p.textDim,
            )),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.panelLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: p.textPrimary),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontFamily: RadarFonts.heading,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.radar,
          foregroundColor: p.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(
            fontFamily: RadarFonts.heading,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.6,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(
            fontFamily: RadarFonts.body,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.radar,
          textStyle: const TextStyle(
            fontFamily: RadarFonts.body,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.panelHighest,
        contentTextStyle: TextStyle(
          color: p.textPrimary,
          fontFamily: RadarFonts.body,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.stroke),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.panel,
        modalBackgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.radar),
      iconTheme: IconThemeData(color: p.textDim, size: 20),
    );
  }
}

/// The three families from the uploaded spec. Bundled under `assets/fonts`
/// so typography is identical offline (Pi Browser, no webfont fetch).
abstract final class RadarFonts {
  static const String heading = 'Barlow Condensed';
  static const String body = 'Plus Jakarta Sans';
  static const String label = 'Space Grotesk';
}

/// Screen-size buckets for the responsive shell.
enum WindowSize { compact, medium, expanded }

WindowSize windowSizeFor(double width) {
  if (width < 640) return WindowSize.compact;
  if (width < 1024) return WindowSize.medium;
  return WindowSize.expanded;
}
