import 'package:flutter/material.dart';

import 'radar_theme.dart';

/// Rounded info/status pill.
class InfoPill extends StatelessWidget {
  const InfoPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = color ?? RadarColors.stroke;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Section title with optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Expanded + ellipsis: long titles shrink instead of overflowing
          // the row when a trailing action joins it on narrow screens.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Shared color aliases for widgets that import this file only — routed
/// through the active RadarTheme palette so they follow dark/light mode.
abstract final class RadarColors {
  static Color get ink => RadarTheme.ink;
  static Color get stroke => RadarTheme.stroke;
}

/// Reusable radar logo mark.
class RadarMark extends StatelessWidget {
  const RadarMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RadarMarkPainter(),
    );
  }
}

class _RadarMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..color = RadarColors.stroke;
    for (final factor in const [0.35, 0.65, 0.95]) {
      canvas.drawCircle(c, r * factor, ring);
    }
    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          RadarTheme.radar.withValues(alpha: 0.05),
          RadarTheme.radar.withValues(alpha: 0.7),
        ],
        transform: const GradientRotation(-0.9),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.9), -1.2, 1.6, true, sweep);
    final dot = Paint()..color = RadarTheme.radar;
    canvas.drawCircle(c, r * 0.09, dot);
  }

  @override
  bool shouldRepaint(covariant _RadarMarkPainter oldDelegate) => false;
}
