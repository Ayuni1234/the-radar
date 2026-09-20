import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import 'radar_theme.dart';

/// One interactive pin on the live scouting map — either a radar event or
/// an active stream bounty, color-coded by the scouting-map convention:
/// 🟢 live happening now · 🟡 scheduled upcoming · 🔴 active bounty.
enum PinKind { liveNow, scheduled, bounty }

class MapPin {
  const MapPin._({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.isMinorProtected,
    required this.isBoosted,
    this.event,
    this.bounty,
  });

  final String id;
  final String title;
  final String subtitle;
  final Color color;
  final PinKind kind;
  final double latitude;
  final double longitude;
  final bool isMinorProtected;
  final bool isBoosted;
  final RadarEvent? event;
  final StreamBounty? bounty;

  factory MapPin.fromEvent(RadarEvent e) {
    final PinKind kind;
    if (e.isLive) {
      kind = PinKind.liveNow;
    } else {
      kind = PinKind.scheduled;
    }
    final color = switch (kind) {
      PinKind.liveNow => RadarTheme.radar, // 🟢 active training now
      PinKind.scheduled => RadarTheme.gold, // 🟡 scheduled sessions
      PinKind.bounty => RadarTheme.alert,
    };
    return MapPin._(
      id: 'event:${e.id}',
      title: e.title,
      subtitle: e.isLive
          ? 'Live now · ${e.safeLocationLabel()}'
          : 'Scheduled · ${e.safeLocationLabel()}',
      color: color,
      kind: kind,
      latitude: e.latitude,
      longitude: e.longitude,
      isMinorProtected: e.isMinorProtected,
      isBoosted: e.isBoosted,
      event: e,
    );
  }

  factory MapPin.fromBounty(StreamBounty b) {
    return MapPin._(
      id: 'bounty:${b.id}',
      title: b.title,
      subtitle:
          '${_fmtPi(b.amountPi)} π bounty · ${b.areaName}',
      color: RadarTheme.alert, // 🔴 bounty active
      kind: PinKind.bounty,
      latitude: b.latitude ?? 5.6037,
      longitude: b.longitude ?? -0.1870,
      isMinorProtected: false,
      isBoosted: false,
      bounty: b,
    );
  }

  static String _fmtPi(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

/// Deterministic pseudo-geo layout shared with the radar painter: places a
/// pin by bearing & distance from its longitude/latitude so positions are
/// stable across rebuilds.
List<(MapPin, Offset)> layoutPins(
    List<MapPin> pins, Offset center, double radius) {
  final result = <(MapPin, Offset)>[];
  for (final pin in pins) {
    final bearing = (pin.longitude.abs() * 40) % 360;
    final distance =
        0.35 + ((pin.latitude.abs() * 13) % 55) / 100;
    final angle = bearing * math.pi / 180 - math.pi / 2;
    final r = radius * distance * (pin.isBoosted ? 0.82 : 1.0);
    result.add((
      pin,
      Offset(center.dx + math.cos(angle) * r,
          center.dy + math.sin(angle) * r),
    ));
  }
  return result;
}
