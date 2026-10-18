import 'dart:async';

import 'package:flutter/material.dart';

import 'radar_theme.dart';

/// Formats a [Duration] hackathon-style: "00:03:22:4h" —
/// `HH:MM:SS` with a single decimal hour digit (0–9 tenths of the
/// remaining hour), bold numeric countdown display.
String formatHackathonCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  // Tenths of the current hour for the trailing "h" digit.
  final tenth = (d.inSeconds.remainder(3600) * 10 ~/ 3600);
  final hh = h.toString().padLeft(2, '0');
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return '$hh:$mm:$ss:${tenth < 9 ? tenth : 9}h';
}

/// The clock format drawn on the live invitation card: `01h 42m 18s`.
String formatClockCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${h}h ${m}m ${s}s';
}

/// Live ticking countdown — rebuilds once per second. Hot stage 0.
class LiveCountdownText extends StatefulWidget {
  const LiveCountdownText({
    super.key,
    required this.target,
    this.style,
    this.onExpired,
    this.expiredLabel = 'LIVE NOW',
    this.formatter,
  });

  /// Overrides the default `HH:MM:SS:Xh` format (the reel card uses
  /// `formatClockCountdown` for its `01h 42m 18s` readout).
  final String Function(Duration)? formatter;

  /// The moment the countdown runs toward.
  final DateTime target;

  /// Override the default bold numeric style.
  final TextStyle? style;

  /// Called once when the timer crosses zero.
  final VoidCallback? onExpired;

  /// Text shown after expiry (single frame, until the parent rebuilds).
  final String expiredLabel;

  @override
  State<LiveCountdownText> createState() => _LiveCountdownTextState();
}

class _LiveCountdownTextState extends State<LiveCountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(covariant LiveCountdownText old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _tick();
  }

  void _tick() {
    _timer?.cancel();
    final remaining = widget.target.difference(DateTime.now());
    if (remaining.isNegative) {
      widget.onExpired?.call();
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = widget.target.difference(DateTime.now());
      if (left.isNegative) {
        _timer?.cancel();
        setState(() {});
        widget.onExpired?.call();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.target.difference(DateTime.now());
    if (remaining.isNegative) {
      return Text(
        widget.expiredLabel,
        style: (widget.style ?? const TextStyle()).copyWith(
          color: RadarTheme.radar,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return Text(
      (widget.formatter ?? formatHackathonCountdown)(remaining),
      style: widget.style ??
          TextStyle(
            color: RadarTheme.gold,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}
