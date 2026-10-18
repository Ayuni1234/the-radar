import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../radar_theme.dart';

/// Design tokens translated 1:1 from the uploaded Stitch spec
/// (`nocturnal_athletic_pitchside_radar/DESIGN.md`).
///
/// Every size, weight, tracking and radius here is taken from the spec's
/// typography + shape tables — screens compose these instead of inventing
/// local values, so a future spec refresh lands in one place.
abstract final class RadarType {
  // ---------------------------------------------------------------- display
  static const TextStyle displayHero = TextStyle(
    fontFamily: RadarFonts.heading,
    fontSize: 56,
    height: 56 / 56,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.12,
  );

  static const TextStyle displayHeroMobile = TextStyle(
    fontFamily: RadarFonts.heading,
    fontSize: 40,
    height: 42 / 40,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
  );

  // --------------------------------------------------------------- headline
  static const TextStyle headlineLg = TextStyle(
    fontFamily: RadarFonts.heading,
    fontSize: 36,
    height: 40 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.08,
  );

  static const TextStyle headlineLgMobile = TextStyle(
    fontFamily: RadarFonts.heading,
    fontSize: 28,
    height: 32 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.56,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: RadarFonts.heading,
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.48,
  );

  static const TextStyle headlineSm = TextStyle(
    fontFamily: RadarFonts.heading,
    fontSize: 20,
    height: 24 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  // ------------------------------------------------------------------- body
  static const TextStyle bodyLg = TextStyle(
    fontFamily: RadarFonts.body,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: RadarFonts.body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: RadarFonts.body,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  // ---------------------------------------------------------------- metrics
  static const TextStyle metricLg = TextStyle(
    fontFamily: RadarFonts.label,
    fontSize: 28,
    height: 32 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.56,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle metricMd = TextStyle(
    fontFamily: RadarFonts.label,
    fontSize: 18,
    height: 22 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.18,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ----------------------------------------------------------------- labels
  static const TextStyle caps = TextStyle(
    fontFamily: RadarFonts.label,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.88,
  );

  static const TextStyle capsTight = TextStyle(
    fontFamily: RadarFonts.label,
    fontSize: 10,
    height: 13 / 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  static const TextStyle interactive = TextStyle(
    fontFamily: RadarFonts.body,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w600,
  );

  /// Convenience: a heading style recoloured, optionally resized.
  static TextStyle heading(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? tracking,
    double? height,
  }) =>
      TextStyle(
        fontFamily: RadarFonts.heading,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: tracking,
        color: color,
      );
}

/// Spacing scale from the spec (4 / 8 / 16 / 24 / 40).
abstract final class RadarSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;

  /// Page margin (mobile base / tablet / desktop per the responsive rules).
  static double page(double width) =>
      width >= 1024 ? 48 : (width >= 640 ? 32 : 16);
}

/// Radius scale: 4px base, 8px cards, 12px sheets, pills.
abstract final class RadarRadius {
  static const double sm = 2;
  static const double base = 4;
  static const double card = 8;
  static const double sheet = 12;
  static const Radius r4 = Radius.circular(4);
  static const Radius r8 = Radius.circular(8);
  static const BorderRadius all4 = BorderRadius.all(r4);
  static const BorderRadius all8 = BorderRadius.all(r8);
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(sheet));
}

// ---------------------------------------------------------------------------
// Surfaces & HUD primitives
// ---------------------------------------------------------------------------

/// Uppercase telemetry label (Space Grotesk, tracked).
class RadarCaps extends StatelessWidget {
  const RadarCaps(
    this.text, {
    super.key,
    this.color,
    this.size = 11,
    this.weight = FontWeight.w700,
    this.tracking = 0.88,
    this.maxLines = 1,
    this.align,
  });

  final String text;
  final Color? color;
  final double size;
  final FontWeight weight;
  final double tracking;
  final int maxLines;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        fontFamily: RadarFonts.label,
        fontSize: size,
        height: 14 / size,
        fontWeight: weight,
        letterSpacing: tracking,
        color: color ?? RadarTheme.textDim,
      ),
    );
  }
}

/// The spec's Surface-1/2 plate: translucent fill, hairline border, 8px
/// radius, optional accent rim light.
class RadarPanel extends StatelessWidget {
  const RadarPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(RadarSpace.md),
    this.color,
    this.borderColor,
    this.glow,
    this.radius = RadarRadius.card,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Color? glow;
  final double radius;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? RadarTheme.panel) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? RadarTheme.stroke),
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow!.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: -2,
                ),
              ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// Pill chip, matching the spec's tag/live-badge geometry.
class RadarPill extends StatelessWidget {
  const RadarPill({
    super.key,
    required this.label,
    this.color,
    this.fill,
    this.border,
    this.icon,
    this.dot = false,
    this.selected = false,
    this.height = 28,
    this.onTap,
    this.trailing,
  });

  final String label;
  final Color? color;
  final Color? fill;
  final Color? border;
  final IconData? icon;
  final bool dot;
  final bool selected;
  final double height;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? RadarTheme.textDim;
    final bg = fill ??
        (selected ? RadarTheme.radar : RadarTheme.panelHighest);
    final fg = selected ? RadarTheme.onAccent : accent;
    final content = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: trailing == null ? 10 : 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : (border ?? RadarTheme.stroke),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: selected ? RadarTheme.onAccent : accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: RadarType.caps.copyWith(color: fg, fontSize: 10.5),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// The radiating beacon dot used by every live badge.
class LiveDot extends StatefulWidget {
  const LiveDot({
    super.key,
    this.size = 8,
    this.color,
    this.animate = true,
  });

  final double size;
  final Color? color;
  final bool animate;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? RadarTheme.radar;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8),
        ],
      ),
    );
    if (_controller == null) return dot;
    return SizedBox(
      width: widget.size * 2.4,
      height: widget.size * 2.4,
      child: AnimatedBuilder(
        animation: _controller!,
        builder: (context, child) {
          final t = _controller!.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.65,
                child: Container(
                  width: widget.size * (1 + t * 1.4),
                  height: widget.size * (1 + t * 1.4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: dot,
      ),
    );
  }
}

/// Two-pixel tri-colour laser edge used on the live invitation card.
class LaserEdge extends StatelessWidget {
  const LaserEdge({super.key, this.height = 2, this.radius = RadarRadius.card});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            RadarTheme.radar,
            RadarTheme.info,
            RadarTheme.gold,
          ]),
        ),
      ),
    );
  }
}

/// Primary neon CTA — solid pitch green with the spec's lumen spread.
class RadarPrimaryButton extends StatelessWidget {
  const RadarPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 44,
    this.expand = true,
    this.compactLabel = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool expand;
  final bool compactLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: RadarTheme.radar,
          borderRadius: BorderRadius.circular(RadarRadius.base),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: RadarTheme.radar.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: RadarTheme.onAccent),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: RadarType.heading(
                  compactLabel ? 14 : 16,
                  weight: FontWeight.w700,
                  color: RadarTheme.onAccent,
                  tracking: 0.6,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: button,
    );
  }
}

/// Ghost telemetry button (cyan outline) or Pi-gold tint button.
enum RadarGhostTone { cyan, gold, neutral }

class RadarGhostButton extends StatelessWidget {
  const RadarGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = RadarGhostTone.neutral,
    this.height = 44,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final RadarGhostTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, line) = switch (tone) {
      RadarGhostTone.cyan => (
          RadarTheme.info,
          RadarTheme.info.withValues(alpha: 0.10),
          RadarTheme.info.withValues(alpha: 0.55),
        ),
      RadarGhostTone.gold => (
          RadarTheme.goldBright,
          RadarTheme.gold.withValues(alpha: 0.12),
          RadarTheme.gold.withValues(alpha: 0.40),
        ),
      RadarGhostTone.neutral => (
          RadarTheme.textPrimary,
          RadarTheme.panelHighest,
          RadarTheme.stroke,
        ),
    };
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(RadarRadius.base),
          border: Border.all(color: line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RadarType.heading(
                  15,
                  weight: FontWeight.w700,
                  color: fg,
                  tracking: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Attribute chip: `PAC 96` — caps code in dim, value in bright metric type.
class MetricChip extends StatelessWidget {
  const MetricChip({
    super.key,
    required this.code,
    required this.value,
    this.accent,
    this.fill,
    this.trailing,
  });

  final String code;
  final String value;
  final Color? accent;
  final Color? fill;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill ?? RadarTheme.panelHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(RadarRadius.base),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(code.toUpperCase(),
              style: RadarType.capsTight.copyWith(color: RadarTheme.textDim)),
          const SizedBox(width: 5),
          Text(
            value,
            style: RadarType.capsTight.copyWith(
              color: accent ?? RadarTheme.radar,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Full-width section rule with an accent tick, as used above every block in
/// the bounty hub and passport.
class RadarSectionTitle extends StatelessWidget {
  const RadarSectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.accent,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final Widget? trailing;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? RadarTheme.radar;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RadarType.heading(
                16,
                weight: FontWeight.w700,
                color: RadarTheme.textPrimary,
                tracking: 1.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The scrollable horizontal pill rail used above the reel and the map.
class RadarPillRail extends StatelessWidget {
  const RadarPillRail({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }
}

/// The spec's bottom-of-media gradient: transparent at 40%, canvas at 95%.
class RadarMediaScrim extends StatelessWidget {
  const RadarMediaScrim({super.key, this.height = 320, this.opacity = 1});

  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              RadarTheme.ink.withValues(alpha: 0),
              RadarTheme.ink.withValues(alpha: 0.55 * opacity),
              RadarTheme.ink.withValues(alpha: 0.95 * opacity),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Tiny tactical grid painter — the map canvas and empty states.
class TacticalGridPainter extends CustomPainter {
  TacticalGridPainter({this.spacing = 24, this.color, this.dot = false});

  final double spacing;
  final Color? color;
  final bool dot;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (color ?? Colors.white).withValues(alpha: 0.035)
      ..strokeWidth = 1;
    if (dot) {
      final dotPaint = Paint()
        ..color = (color ?? Colors.white).withValues(alpha: 0.06);
      for (double x = spacing / 2; x < size.width; x += spacing) {
        for (double y = spacing / 2; y < size.height; y += spacing) {
          canvas.drawCircle(Offset(x, y), 1, dotPaint);
        }
      }
      return;
    }
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant TacticalGridPainter oldDelegate) =>
      oldDelegate.spacing != spacing || oldDelegate.color != color;
}

/// Deterministic monogram avatar used where the design shows photography that
/// is not part of the data set.
class RadarAvatar extends StatelessWidget {
  const RadarAvatar({
    super.key,
    this.name = '',
    this.url,
    this.size = 40,
    this.ring,
    this.ringWidth = 2,
  });

  final String name;
  final String? url;
  final double size;
  final Color? ring;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.trim().isNotEmpty;
    final initials = _initials(name);
    final hue = (name.hashCode % 40) - 20;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring == null ? 0 : ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring!, width: ringWidth),
      ),
      child: ClipOval(
        child: hasUrl
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => _monogram(initials, hue),
              )
            : _monogram(initials, hue),
      ),
    );
  }

  Widget _monogram(String initials, int hue) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(RadarTheme.panelHighest, RadarTheme.radar, 0.16 + hue / 400)!,
            RadarTheme.panelLowest,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: RadarType.heading(
          size * 0.38,
          weight: FontWeight.w700,
          color: RadarTheme.textPrimary,
          tracking: 0.5,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'π';
    if (parts.length == 1) {
      return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// Soft radial glow behind live pins and hero numbers.
class RadialGlow extends StatelessWidget {
  const RadialGlow({
    super.key,
    required this.child,
    this.color,
    this.radius = 90,
    this.strength = 0.28,
  });

  final Widget child;
  final Color? color;
  final double radius;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final c = (color ?? RadarTheme.radar).withValues(alpha: strength);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [c, c.withValues(alpha: 0)],
          radius: 0.7,
        ),
      ),
      child: child,
    );
  }
}

/// Formats Pi amounts the way the spec does: whole numbers bare, fractions
/// with two decimals, always followed by the π glyph by the caller.
String fmtPi(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
