import 'package:flutter/material.dart';

import 'radar_theme.dart';

/// Shared chrome for every modal bottom sheet in the app.
///
/// Guarantees that a sheet can never clip its content or hide it behind the
/// keyboard:
///
/// * the body always scrolls (`SingleChildScrollView`) — long forms stretch
///   instead of overflowing,
/// * the optional [footer] (primary action) is pinned *below* the scrollable
///   body, so the submit button stays visible without scrolling,
/// * the bottom padding grows by `MediaQuery.viewInsetsOf(context).bottom`,
///   so keyboard-occluded sheets lift their focused field and footer above
///   the keyboard.
///
/// Migration note: call sites should use `isScrollControlled: true` and
/// `backgroundColor: Colors.transparent` — the scaffold paints its own
/// background (`floating: true` renders the inset bordered-card variant).
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = RadarTheme.radar,
    this.children = const <Widget>[],
    this.footer,
    this.showClose = true,
    this.floating = false,
    this.backgroundColor,
  });

  /// Sheet title, rendered in the pinned header row.
  final String title;

  /// One-line explanation rendered under the title.
  final String? subtitle;

  /// Optional leading icon in the header row.
  final IconData? icon;

  /// Color of the leading header icon.
  final Color iconColor;

  /// Scrollable content between the header and the footer.
  final List<Widget> children;

  /// Pinned primary action below the scroll view (e.g. the submit button).
  /// Always visible — never pushed off-screen by long content or keyboard.
  final Widget? footer;

  /// Whether to render the trailing close (×) button in the header.
  final bool showClose;

  /// Inset bordered-card variant (rounded on all sides, 14px margin) used by
  /// sheets that previously floated over a transparent background.
  final bool floating;

  /// Background color; defaults to [RadarTheme.panel].
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // Raise the content above the keyboard; when no keyboard is up, keep the
    // content clear of the home indicator via the safe-area inset instead.
    final bottomPad =
        keyboard > 0 ? keyboard : MediaQuery.paddingOf(context).bottom;

    final background = backgroundColor ?? RadarTheme.panel;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (showClose)
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close, size: 18),
              ),
          ]),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: RadarTheme.textDim),
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            // The body always scrolls: long forms can never overflow, and
            // with a keyboard up the focused field is reachable by scroll.
            padding: EdgeInsets.fromLTRB(16, 12, 16, footer == null
                ? 16 + bottomPad
                : 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
            child: footer!,
          ),
      ],
    );

    if (floating) {
      content = Padding(
        padding: const EdgeInsets.all(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RadarTheme.stroke),
          ),
          child: content,
        ),
      );
    } else {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: content,
      );
    }
    return content;
  }
}
