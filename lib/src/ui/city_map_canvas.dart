import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import 'radar_theme.dart';

/// A painted, photoreal-styled city map canvas: a vector rendition of
/// central London — the Thames sweep, street grid, parks, POI dots and
/// place-name labels — used as the Radar tab's base layer.
///
/// Deterministic (no tiles, no network): the same widget tree renders
/// identically offline, in demo mode and in widget tests.
class CityMapCanvas extends StatelessWidget {
  const CityMapCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _CityMapPainter());
  }
}

class _CityMapPainter extends CustomPainter {
  const _CityMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _paintBase(canvas, size);
    _paintParks(canvas, size);
    _paintThames(canvas, size);
    _paintBlocks(canvas, size);
    _paintStreets(canvas, size);
    _paintLabels(canvas, size);
    _paintVignette(canvas, size);
  }

  // Deep aerial base: dark earth tones in dark mode, a clean paper-map
  // wash in light mode — driven by the active RadarTheme palette.
  void _paintBase(Canvas canvas, Size size) {
    final light = !RadarTheme.current.isDark;
    final base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 1.6,
        colors: light
            ? const [
                Color(0xFFE7EDE4),
                Color(0xFFDEE6DB),
                Color(0xFFD4DED1),
              ]
            : const [
                Color(0xFF232B22),
                Color(0xFF1A211A),
                Color(0xFF141A14),
              ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);
  }

  // Parks: Hyde Park (NW), Green Park, St James's (W), embed gardens.
  void _paintParks(Canvas canvas, Size size) {
    final light = !RadarTheme.current.isDark;
    final park = Paint()
      ..color = light ? const Color(0xFFC4D8BC) : const Color(0xFF2E4428);
    final parkLight = Paint()
      ..color = light ? const Color(0xFFCFE2C6) : const Color(0xFF35502C);

    Path rounded(Rect r, double rad) => Path()
      ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(rad)));

    canvas.drawPath(
        rounded(
            Rect.fromLTWH(size.width * 0.02, size.height * 0.10,
                size.width * 0.30, size.height * 0.16),
            10),
        park); // Hyde Park
    canvas.drawPath(
        rounded(
            Rect.fromLTWH(size.width * 0.10, size.height * 0.28,
                size.width * 0.12, size.height * 0.09),
            8),
        parkLight); // Green Park
    canvas.drawPath(
        rounded(
            Rect.fromLTWH(size.width * 0.06, size.height * 0.40,
                size.width * 0.10, size.height * 0.10),
            8),
        park); // St James's
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width * 0.46, size.height * 0.52),
            width: size.width * 0.10,
            height: size.height * 0.06),
        parkLight); // gardens
  }

  // The Thames: a broad sweeping band across the SE with tributary curve.
  void _paintThames(Canvas canvas, Size size) {
    final river = Path()
      ..moveTo(size.width * 1.02, size.height * 0.42)
      ..cubicTo(
          size.width * 0.86, size.height * 0.40,
          size.width * 0.80, size.height * 0.52,
          size.width * 0.68, size.height * 0.55)
      ..cubicTo(
          size.width * 0.55, size.height * 0.58,
          size.width * 0.55, size.height * 0.72,
          size.width * 0.45, size.height * 0.80)
      ..cubicTo(
          size.width * 0.38, size.height * 0.86,
          size.width * 0.24, size.height * 0.88,
          size.width * 0.10, size.height * 0.86);

    final light = !RadarTheme.current.isDark;
    final water = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.055
      ..strokeCap = StrokeCap.round
      ..color = light ? const Color(0xFFA9C6E0) : const Color(0xFF1E3446);
    canvas.drawPath(river, water);

    final sheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.055 * 0.45
      ..strokeCap = StrokeCap.round
      ..color = (light ? const Color(0xFFBBD5EA) : const Color(0xFF29465E))
          .withValues(alpha: 0.65);
    canvas.drawPath(river, sheen);
  }

  // City blocks: irregular building masses on both banks.
  void _paintBlocks(Canvas canvas, Size size) {
    final light = !RadarTheme.current.isDark;
    final blockPaint = Paint()
      ..color = light ? const Color(0xFFCFCFC6) : const Color(0xFF333A33);
    final blockLight = Paint()
      ..color = light ? const Color(0xFFDADAD1) : const Color(0xFF3C4440);
    final rnd = math.Random(7);

    for (var i = 0; i < 240; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      // Avoid the river band: keep blocks off the water sweep.
      final t = x / size.width;
      final riverY = _riverYAt(t, size) ?? double.infinity;
      if ((y - riverY).abs() < size.height * 0.06) continue;

      final w = 6 + rnd.nextDouble() * 26;
      final h = 5 + rnd.nextDouble() * 18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h), const Radius.circular(1.6)),
        rnd.nextDouble() > 0.7 ? blockLight : blockPaint,
      );
    }
  }

  double? _riverYAt(double t, Size size) {
    // Approximate the painted river path for block exclusion.
    if (t > 0.95) return size.height * 0.42;
    if (t > 0.75) return size.height * 0.48;
    if (t > 0.55) return size.height * 0.58;
    if (t > 0.45) return size.height * 0.74;
    if (t > 0.25) return size.height * 0.86;
    return null;
  }

  // Street network: arterials + minor grid, clipped off the water.
  void _paintStreets(Canvas canvas, Size size) {
    final light = !RadarTheme.current.isDark;
    final major = Paint()
      ..strokeWidth = 2.6
      ..color = (light ? const Color(0xFF9AA0A6) : const Color(0xFF59615C))
          .withValues(alpha: 0.85);
    final minor = Paint()
      ..strokeWidth = 1.1
      ..color = (light ? const Color(0xA6A8AEB4) : const Color(0xFF4A524D))
          .withValues(alpha: 0.7);
    final rnd = math.Random(11);

    // Arterial diagonals & sweep.
    final arterials = <List<Offset>>[
      [Offset(0, size.height * 0.34), Offset(size.width * 0.5, size.height * 0.30), Offset(size.width, size.height * 0.36)],
      [Offset(0, size.height * 0.62), Offset(size.width * 0.45, size.height * 0.56), Offset(size.width * 0.85, size.height * 0.66)],
      [Offset(size.width * 0.30, 0), Offset(size.width * 0.34, size.height * 0.5), Offset(size.width * 0.30, size.height)],
      [Offset(size.width * 0.58, 0), Offset(size.width * 0.55, size.height * 0.45), Offset(size.width * 0.62, size.height)],
    ];
    for (final path in arterials) {
      final p = Path()..moveTo(path.first.dx, path.first.dy);
      var prev = path.first;
      for (final o in path.skip(1)) {
        p.quadraticBezierTo((prev.dx + o.dx) / 2, o.dy, o.dx, o.dy);
        prev = o;
      }
      canvas.drawPath(p, major);
    }

    // Minor streets: jittered grid.
    for (var i = 0; i < 34; i++) {
      final y = rnd.nextDouble() * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
    for (var i = 0; i < 26; i++) {
      final x = rnd.nextDouble() * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
  }

  // Place-name labels — the street-level context the mock shows.
  void _paintLabels(Canvas canvas, Size size) {
    final labelColor = !RadarTheme.current.isDark
        ? const Color(0xFF3E4A40)
        : const Color(0xFFB8C2BA);
    void label(String text, Offset at,
        {double fontSize = 10, Color? color, double angle = 0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color ?? labelColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            shadows: [
              Shadow(
                  color: RadarTheme.current.isDark
                      ? const Color(0xAA000000)
                      : const Color(0x66FFFFFF),
                  blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (angle != 0) {
        canvas.translate(at.dx, at.dy);
        canvas.rotate(angle);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.rotate(-angle);
        canvas.translate(-at.dx, -at.dy);
      } else {
        tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      }
    }

    label('London', Offset(size.width * 0.055, size.height * 0.62),
        fontSize: 13,
        color: !RadarTheme.current.isDark
            ? const Color(0xFF33403A)
            : const Color(0xFFD3DCD4));
    label('Covent Garden', Offset(size.width * 0.45, size.height * 0.475),
        fontSize: 11);
    label('Tothill St',
        Offset(size.width * 0.20, size.height * 0.455),
        fontSize: 8.5, angle: -0.10);
    label('Emilie Fed', Offset(size.width * 0.82, size.height * 0.30),
        fontSize: 8.5, angle: -0.24);
    label('Columbuts and',
        Offset(size.width * 0.15, size.height * 0.665),
        fontSize: 8.5);
    label('The Mall', Offset(size.width * 0.12, size.height * 0.565),
        fontSize: 8, angle: 0.06);
  }

  void _paintVignette(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.15,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.38),
          ],
          stops: const [0.62, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _CityMapPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Map markers (widgets, so they can animate & carry tooltips)
// ---------------------------------------------------------------------------

/// Semantic geographic anchors used to place markers on the painted map.
/// Positions are fractions of the canvas, matching _CityMapPainter's layout.
abstract final class MapSpots {
  static const Offset coventGarden = Offset(0.45, 0.475);
  static const Offset scheduledEast = Offset(0.56, 0.462);
  static const Offset southBankPitches = Offset(0.52, 0.655);
  static const Offset westminsterSchool = Offset(0.22, 0.435);
}

/// The green pulsing "live now" marker: teardrop pin with concentric aura.
class LiveNowMarker extends StatefulWidget {
  const LiveNowMarker({super.key, this.size = 64});

  final double size;

  @override
  State<LiveNowMarker> createState() => _LiveNowMarkerState();
}

class _LiveNowMarkerState extends State<LiveNowMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => CustomPaint(
          painter: _LivePinPainter(phase: _pulse.value),
        ),
      ),
    );
  }
}

class _LivePinPainter extends CustomPainter {
  const _LivePinPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final auraR = size.width * (0.28 + 0.30 * phase);
    canvas.drawCircle(
        c, auraR, Paint()..color = RadarTheme.radar.withValues(alpha: 0.20 * (1 - phase)));
    canvas.drawCircle(
        c,
        size.width * 0.22,
        Paint()..color = RadarTheme.radar.withValues(alpha: 0.28));

    // Teardrop pin.
    final pin = Path()
      ..moveTo(c.dx, c.dy + size.height * 0.24)
      ..quadraticBezierTo(
          c.dx - size.width * 0.16, c.dy - size.height * 0.02,
          c.dx, c.dy - size.height * 0.20)
      ..quadraticBezierTo(
          c.dx + size.width * 0.16, c.dy - size.height * 0.02,
          c.dx, c.dy + size.height * 0.24)
      ..close();
    canvas.drawPath(pin, Paint()..color = RadarTheme.radar);
    canvas.drawCircle(
        Offset(c.dx, c.dy - size.height * 0.02),
        size.width * 0.055,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LivePinPainter old) => old.phase != phase;
}

/// The yellow "scheduled" marker.
class ScheduledMarker extends StatelessWidget {
  const ScheduledMarker({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ScheduledPinPainter()),
    );
  }
}

class _ScheduledPinPainter extends CustomPainter {
  const _ScheduledPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final pin = Path()
      ..moveTo(c.dx, c.dy + size.height * 0.26)
      ..quadraticBezierTo(
          c.dx - size.width * 0.18, c.dy - size.height * 0.02,
          c.dx, c.dy - size.height * 0.22)
      ..quadraticBezierTo(
          c.dx + size.width * 0.18, c.dy - size.height * 0.02,
          c.dx, c.dy + size.height * 0.26)
      ..close();
    canvas.drawPath(pin, Paint()..color = RadarTheme.gold);
    canvas.drawCircle(
        Offset(c.dx, c.dy - size.height * 0.02),
        size.width * 0.06,
        Paint()..color = const Color(0xFF231B04));
  }

  @override
  bool shouldRepaint(covariant _ScheduledPinPainter oldDelegate) => false;
}

/// The red pulsing sonar "bounty active" marker.
class BountySonarMarker extends StatefulWidget {
  const BountySonarMarker({super.key, this.size = 56});

  final double size;

  @override
  State<BountySonarMarker> createState() => _BountySonarMarkerState();
}

class _BountySonarMarkerState extends State<BountySonarMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ping = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ping,
        builder: (context, _) => CustomPaint(
          painter: _SonarPainter(phase: _ping.value),
        ),
      ),
    );
  }
}

class _SonarPainter extends CustomPainter {
  const _SonarPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // Two expanding sonar rings, offset by half a phase each.
    for (final p in [phase, (phase + 0.5) % 1]) {
      canvas.drawCircle(
          c,
          size.width * (0.14 + 0.34 * p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4 * (1 - p)
            ..color = RadarTheme.alert.withValues(alpha: 0.65 * (1 - p)));
    }
    canvas.drawCircle(
        c, size.width * 0.10, Paint()..color = RadarTheme.alert);
  }

  @override
  bool shouldRepaint(covariant _SonarPainter old) => old.phase != phase;
}

/// The blue-and-white shield for minor-protected sites.
class MinorShieldMarker extends StatelessWidget {
  const MinorShieldMarker({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShieldPainter()),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final shield = Path()
      ..moveTo(c.dx, c.dy - size.height * 0.38)
      ..lineTo(c.dx + size.width * 0.26, c.dy - size.height * 0.26)
      ..quadraticBezierTo(c.dx + size.width * 0.26, c.dy + size.height * 0.16,
          c.dx, c.dy + size.height * 0.36)
      ..quadraticBezierTo(c.dx - size.width * 0.26, c.dy + size.height * 0.16,
          c.dx - size.width * 0.26, c.dy - size.height * 0.26)
      ..close();
    canvas.drawPath(shield, Paint()..color = RadarTheme.info);
    canvas.drawPath(
        shield,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white);
    // White tick inside the shield.
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawLine(
        Offset(c.dx - size.width * 0.09, c.dy),
        Offset(c.dx - size.width * 0.02, c.dy + size.height * 0.09), tick);
    canvas.drawLine(
        Offset(c.dx - size.width * 0.02, c.dy + size.height * 0.09),
        Offset(c.dx + size.width * 0.12, c.dy - size.height * 0.10), tick);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Placement helpers
// ---------------------------------------------------------------------------

/// Lays out [markers] over the city canvas. Each entry pairs a semantic
/// model object with its anchor spot (fractions of the canvas).
class CityMapMarkerLayout extends StatelessWidget {
  const CityMapMarkerLayout({
    super.key,
    required this.liveEvents,
    required this.scheduledEvents,
    required this.bounties,
    required this.protectedEvents,
    this.onSelectEvent,
    this.onSelectBounty,
  });

  final List<RadarEvent> liveEvents;
  final List<RadarEvent> scheduledEvents;
  final List<StreamBounty> bounties;
  final List<RadarEvent> protectedEvents;
  final ValueChanged<RadarEvent>? onSelectEvent;
  final ValueChanged<StreamBounty>? onSelectBounty;

  @override
  Widget build(BuildContext context) {
    final anchors = _spread(MapSpots.coventGarden, liveEvents.length, 0.055);
    final schedAnchors =
        _spread(MapSpots.scheduledEast, scheduledEvents.length, 0.05);
    final bountyAnchors =
        _spread(MapSpots.southBankPitches, bounties.length, 0.06);
    final shieldAnchors =
        _spread(MapSpots.westminsterSchool, protectedEvents.length, 0.05);

    return LayoutBuilder(builder: (context, constraints) {
      Offset at(Offset frac) => Offset(
            frac.dx * constraints.maxWidth,
            frac.dy * constraints.maxHeight,
          );

      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < liveEvents.length; i++)
            Positioned(
              left: at(anchors[i]).dx - 32,
              top: at(anchors[i]).dy - 32,
              child: GestureDetector(
                onTap: () => onSelectEvent?.call(liveEvents[i]),
                child: const LiveNowMarker(size: 64),
              ),
            ),
          for (var i = 0; i < scheduledEvents.length; i++)
            Positioned(
              left: at(schedAnchors[i]).dx - 20,
              top: at(schedAnchors[i]).dy - 20,
              child: GestureDetector(
                onTap: () => onSelectEvent?.call(scheduledEvents[i]),
                child: const ScheduledMarker(size: 40),
              ),
            ),
          for (var i = 0; i < bounties.length; i++)
            Positioned(
              left: at(bountyAnchors[i]).dx - 28,
              top: at(bountyAnchors[i]).dy - 28,
              child: GestureDetector(
                onTap: () => onSelectBounty?.call(bounties[i]),
                child: const BountySonarMarker(size: 56),
              ),
            ),
          for (var i = 0; i < protectedEvents.length; i++)
            Positioned(
              left: at(shieldAnchors[i]).dx - 17,
              top: at(shieldAnchors[i]).dy - 17,
              child: Tooltip(
                message:
                    'Minor-protected — approximate location only',
                child: const MinorShieldMarker(size: 34),
              ),
            ),
        ],
      );
    });
  }

  /// Spreads [n] anchors around [origin] in a widening ring so overlapping
  /// sessions remain individually tappable.
  List<Offset> _spread(Offset origin, int n, double step) {
    if (n == 0) return const [];
    if (n == 1) return [origin];
    return [
      for (var i = 0; i < n; i++)
        Offset(
          origin.dx + step * math.cos(i * 2.399),
          origin.dy + step * math.sin(i * 2.399),
        ),
    ];
  }
}
