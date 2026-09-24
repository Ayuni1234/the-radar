import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export '../ui/radar_theme.dart' show RadarBrightness;

import '../ui/radar_theme.dart';

/// Persisted preference key for the last-selected theme mode.
const String kThemePrefKey = 'radar.theme_mode';

/// App theme mode: dark (the ops-room default) or light. Riverpod
/// NotifierProvider so any widget can read `themeModeProvider` and the header /
/// settings toggles can flip it in one line.
///
/// On mode change the controller also points [RadarTheme.current] at the
/// matching palette *before* MaterialApp rebuilds, so the legacy
/// `RadarTheme.<color>` getters (read during the same build) emit the new
/// palette and the whole UI — cards, sheets, dialogs, map canvases —
/// re-skins atomically.
final themeModeProvider =
    NotifierProvider<ThemeModeController, RadarBrightness>(
        ThemeModeController.new);

class ThemeModeController extends Notifier<RadarBrightness> {
  @override
  RadarBrightness build() => RadarBrightness.dark;

  void set(RadarBrightness mode) => state = mode;

  RadarBrightness toggle() =>
      state = state == RadarBrightness.dark
          ? RadarBrightness.light
          : RadarBrightness.dark;
}

/// Applies [mode] as the active theme: mutates the palette singleton, then
/// the provider state (which rebuilds MaterialApp). Returns the mode for
/// ergonomic toggles.
RadarBrightness setAppTheme(Ref ref, RadarBrightness mode) {
  RadarTheme.current =
      mode == RadarBrightness.dark ? RadarPalette.dark : RadarPalette.light;
  ref.read(themeModeProvider.notifier).set(mode);
  return mode;
}

/// Escape hatch for call sites holding no [Ref] (pure unit tests, stubs):
/// palette only, no provider notification.
void setAppThemeDirect(RadarBrightness mode) {
  RadarTheme.current =
      mode == RadarBrightness.dark ? RadarPalette.dark : RadarPalette.light;
}

/// Flips dark ↔ light and returns the new mode.
RadarBrightness toggleAppTheme(Ref ref) => setAppTheme(
    ref,
    ref.read(themeModeProvider) == RadarBrightness.dark
        ? RadarBrightness.light
        : RadarBrightness.dark);

/// Restores the persisted theme preference at startup (before the first
/// frame). Storage failures fall back to the dark default — theming must
/// never block the boot path.
Future<void> restoreThemePreference(ProviderContainer container) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kThemePrefKey);
    if (saved == 'light') {
      setAppThemeDirect(RadarBrightness.light);
      container.read(themeModeProvider.notifier).set(RadarBrightness.light);
    }
  } catch (_) {
    // First run or unavailable storage — dark default stands.
  }
}

/// Persists [mode]. Fire-and-forget; failures are non-fatal.
Future<void> persistThemePreference(RadarBrightness mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        kThemePrefKey, mode == RadarBrightness.light ? 'light' : 'dark');
  } catch (_) {
    // Preference simply does not persist this session.
  }
}
