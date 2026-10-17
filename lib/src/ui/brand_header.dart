import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_brand.dart';
import '../state/theme_controller.dart';
import 'radar_theme.dart';
import 'shell.dart' show RadarMark;

/// Dynamic branded title bar used by every screen and the login/splash.
///
/// Renders the official app name from [AppBrand] (never a hardcoded or
/// outdated brand string) with the radar mark, plus optional Pi balance and
/// theme toggle actions — mirroring the hackathon mockup headers
/// ("brand + 𝛑 50.00𝛑 + theme + bell").
class BrandHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandHeaderBar({
    super.key,
    this.showBalance = true,
    this.actions,
    this.compact = false,
  });

  /// Whether the Pi balance chip renders (hidden on narrow headers).
  final bool showBalance;

  /// Extra actions after the standard theme/notification actions.
  final List<Widget>? actions;

  /// Compact variant for very narrow widths.
  final bool compact;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: RadarTheme.ink.withValues(alpha: 0.96),
      titleSpacing: 12,
      // The title only gets whatever the actions leave behind. On a narrow
      // phone that can be less than the mark itself, so the brand scales down
      // instead of overflowing into the yellow/black hazard bars.
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadarMark(size: compact ? 24 : 30),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                AppBrand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: RadarTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 14 : 16,
                  letterSpacing: 2.4,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (showBalance) const PiBalanceChip(),
        const _ThemeHeaderToggle(),
        ...?actions,
      ],
    );
  }
}

/// Gold 𝛑 balance chip displayed in the header — mockup spec "50.00𝛑".
/// Shared with the Reels overlay header, which floats it over the media.
class PiBalanceChip extends StatelessWidget {
  const PiBalanceChip({super.key, this.amount = '50.00'});

  /// Displayed balance, without the 𝛑 prefix.
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: RadarTheme.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RadarTheme.gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '𝛑 $amount',
              style: TextStyle(
                color: RadarTheme.gold,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Light/dark toggle icon used inside headers.
class _ThemeHeaderToggle extends ConsumerWidget {
  const _ThemeHeaderToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == RadarBrightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 21,
        color: RadarTheme.textDim,
      ),
      onPressed: () async {
        final next = ref.read(themeModeProvider.notifier).toggle();
        RadarTheme.current = next == RadarBrightness.dark
            ? RadarPalette.dark
            : RadarPalette.light;
        await persistThemePreference(next);
      },
    );
  }
}
