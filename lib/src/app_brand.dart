import 'package:flutter/material.dart';

import 'ui/shell.dart' show RadarMark;

/// Official app branding — the single source of truth for every header,
/// title bar, splash, PWA label and document title in the app.
///
/// IMPORTANT: no "Pi Scout" branding anywhere. Every user-visible app name
/// MUST come from [AppBrand] so a future rename lands in exactly one place.
/// Web `manifest.json` and `web/index.html` mirror these values manually.
abstract final class AppBrand {
  /// Marketing name shown in headers, the login hero and the splash.
  static const String name = 'THE RADAR';

  /// Title-cased variant for sentences and document titles.
  static const String nameTitleCase = 'The Radar';

  /// Unique short name for the PWA / OS launcher.
  static const String shortName = 'The Radar';

  /// Full MaterialApp.title / PWA manifest name.
  static const String tagline = 'Global Football Scouting Platform';

  /// Composed app bar title, e.g. "The Radar — Global Football Scouting Platform".
  static String get fullTitle => '$nameTitleCase — $tagline';

  /// Brand header widget: the radar mark next to the configured app name.
  /// Used by every top-level header so branding stays dynamic.
  static Widget header({double size = 34, double fontSize = 15}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadarMark(size: size),
          const SizedBox(width: 10),
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              letterSpacing: 3,
            ),
          ),
        ],
      );
}
