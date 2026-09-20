import 'dart:math' as math;

/// One tracking sample from the AI Tracking Engine: where the locked-on
/// player was on the pitch at time [tSec], plus frame-derived event flags.
class TrackSample {
  const TrackSample({
    required this.tSec,
    required this.x,
    required this.y,
    this.onBall = false,
    this.shot = false,
    this.tackle = false,
    this.takeOn = false,
    this.recovery = false,
    this.pass = false,
    this.passCompleted = true,
  });

  /// Seconds since kickoff.
  final double tSec;

  /// Pitch coordinates in metres, origin at the viewer's goal centre:
  /// x = distance up the pitch (0..105), y = across (0..68).
  final double x;
  final double y;

  /// Frame-derived flags (jersey-lock confidence above threshold).
  final bool onBall;
  final bool shot;
  final bool tackle;
  final bool takeOn;
  final bool recovery;

  /// The player played a pass in this sample window.
  final bool pass;

  /// Whether that pass reached a teammate (completion rate).
  final bool passCompleted;
}

/// A point in the pitch heatmap grid.
class HeatCell {
  const HeatCell({required this.x, required this.y, required this.weight});
  final int x;
  final int y;
  final int weight;
}

/// One auto-sliced highlight clip.
class HighlightClip {
  const HighlightClip({
    required this.label,
    required this.startSec,
    required this.endSec,
    required this.kind,
  });

  final String label;
  final double startSec;
  final double endSec;

  /// shot | takeOn | tackle | recovery | touch | goal
  final String kind;

  String get kindLabel => switch (kind) {
        'shot' => 'Shot',
        'takeOn' => 'Take-on',
        'tackle' => 'Tackle',
        'recovery' => 'Recovery',
        'touch' => 'Touch',
        'goal' => 'GOAL',
        _ => kind,
      };

  String get windowLabel =>
      '${_clock(startSec)} – ${_clock(endSec)}';

  static String _clock(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).round().toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

/// Peak sprint / burst windows.
class SpeedBurst {
  const SpeedBurst({
    required this.startSec,
    required this.endSec,
    required this.peakKmh,
    required this.distanceM,
  });
  final double startSec;
  final double endSec;
  final double peakKmh;
  final double distanceM;
}

/// Full post-match breakdown computed from telemetry samples.
class MatchReport {
  const MatchReport({
    required this.totalDistanceM,
    required this.avgSpeedKmh,
    required this.peakSpeedKmh,
    required this.bursts,
    required this.heatmap,
    required this.passAttempts,
    required this.passCompletions,
    required this.takeOnsWon,
    required this.takeOnsLost,
    required this.tackles,
    required this.recoveries,
    required this.avgRecoverySec,
    required this.touches,
    required this.shots,
    required this.clips,
    required this.topSpeedZones,
  });

  // Physical.
  final double totalDistanceM;
  final double avgSpeedKmh;
  final double peakSpeedKmh;
  final List<SpeedBurst> bursts;
  final List<HeatCell> heatmap;
  final int topSpeedZones; // minutes in >24 km/h zone

  // Technical.
  final int passAttempts;
  final int passCompletions;
  final int takeOnsWon;
  final int takeOnsLost;
  final int tackles;
  final int recoveries;
  final double avgRecoverySec;
  final int touches;
  final int shots;

  final List<HighlightClip> clips;

  double get passRate =>
      passAttempts == 0 ? 0 : passCompletions / passAttempts * 100;
  double get takeOnRate =>
      (takeOnsWon + takeOnsLost) == 0
          ? 0
          : takeOnsWon / (takeOnsWon + takeOnsLost) * 100;
  double get distanceKm => totalDistanceM / 1000;

  /// 0..100 overall grade — distance vs positional norm, physical peaks and
  /// technical efficiency blended. Deterministic so scouts can compare.
  double get overallScore {
    final distScore = (distanceKm / 10.5).clamp(0.0, 1.2) * 30;
    final speedScore = (peakSpeedKmh / 31).clamp(0.0, 1.2) * 25;
    final passScore = (passRate / 100) * 20;
    final duelScore = (takeOnRate / 100) * 12;
    final workScore = (tackles + recoveries).clamp(0, 12) / 12 * 13;
    return (distScore + speedScore + passScore + duelScore + workScore)
        .clamp(0, 100);
  }
}

/// Result of streaming samples through the engine.
class TrackingEngine {
  /// Minimum delta speed (km/h) considered an "acceleration burst".
  static const double burstThresholdKmh = 4.0;

  /// Sprint zone threshold.
  static const double sprintZoneKmh = 24.0;

  /// Minimum burst length.
  static const double burstMinSec = 1.5;

  static MatchReport analyze(List<TrackSample> samples,
      {double pitchLengthM = 105, double pitchWidthM = 68}) {
    final sorted = List<TrackSample>.of(samples)
      ..sort((a, b) => a.tSec.compareTo(b.tSec));

    // ---- physical: distance, speeds, bursts -------------------------------
    var distance = 0.0;
    var peakKmh = 0.0;
    var sprintZoneSec = 0.0;
    final speeds = <double>[]; // kmh per interval
    final heat = List.generate(12, (_) => List.filled(8, 0));

    SpeedBurst? currentBurst;
    double burstPeak = 0;
    double burstDist = 0;
    double burstStart = 0;
    final bursts = <SpeedBurst>[];

    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final gx = (s.x / pitchLengthM * 12).floor().clamp(0, 11);
      final gy = (s.y / pitchWidthM * 8).floor().clamp(0, 7);
      heat[gx][gy]++;

      if (i == 0) continue;
      final prev = sorted[i - 1];
      final dt = s.tSec - prev.tSec;
      if (dt <= 0) continue;

      final d = math.sqrt(
          math.pow(s.x - prev.x, 2) + math.pow(s.y - prev.y, 2));
      distance += d;
      final kmh = d / dt * 3.6;
      speeds.add(kmh);
      if (kmh > peakKmh) peakKmh = kmh;
      if (kmh >= sprintZoneKmh) sprintZoneSec += dt;

      // Burst detection: sustained speed over the threshold.
      if (kmh > burstThresholdKmh && currentBurst == null) {
        currentBurst = SpeedBurst(startSec: 0, endSec: 0, peakKmh: 0, distanceM: 0);
        burstPeak = kmh;
        burstDist = d;
        burstStart = prev.tSec;
      } else if (currentBurst != null) {
        burstDist += d;
        if (kmh > burstPeak) burstPeak = kmh;
        if (kmh <= burstThresholdKmh || i == sorted.length - 1) {
          final len = s.tSec - burstStart;
          if (len >= burstMinSec && burstPeak >= sprintZoneKmh) {
            bursts.add(SpeedBurst(
              startSec: burstStart,
              endSec: s.tSec,
              peakKmh: burstPeak,
              distanceM: burstDist,
            ));
          }
          currentBurst = null;
          burstPeak = 0;
          burstDist = 0;
        }
      }
    }

    final durationSec =
        sorted.isEmpty ? 1 : math.max(1.0, sorted.last.tSec - sorted.first.tSec);
    final avgKmh = distance / durationSec * 3.6;

    // ---- technical counters ------------------------------------------------
    var passAttempts = 0, passCompletions = 0;
    var takeOnsWon = 0, tackles = 0, recoveries = 0;
    var touches = 0, shots = 0;
    var recoverySecSum = 0.0;

    // Recovery timing: seconds between losing possession region (tackle
    // against / interception by opponent) and our next recovery flag.
    double? lastLossSec;
    for (final s in sorted) {
      if (s.pass) {
        passAttempts++;
        if (s.passCompleted) passCompletions++;
      }
      if (s.takeOn) {
        takeOnsWon++;
      }
      if (s.tackle) tackles++;
      if (s.recovery) {
        recoveries++;
        if (lastLossSec != null) {
          recoverySecSum += (s.tSec - lastLossSec).clamp(0, 120);
          lastLossSec = null;
        }
      }
      if (s.onBall) touches++;
      if (s.shot) shots++;
    }

    // ---- clips: auto-slice every event into a reel --------------------------
    final clips = <HighlightClip>[];
    for (final s in sorted) {
      if (s.shot) {
        clips.add(HighlightClip(
          label: s.onBall ? 'Shot after carry' : 'Shot',
          startSec: (s.tSec - 6).clamp(0, double.infinity),
          endSec: s.tSec + 4,
          kind: 'shot',
        ));
      }
      if (s.tackle) {
        clips.add(HighlightClip(
          label: 'Defensive tackle',
          startSec: (s.tSec - 4).clamp(0, double.infinity),
          endSec: s.tSec + 3,
          kind: 'tackle',
        ));
      }
      if (s.takeOn) {
        clips.add(HighlightClip(
          label: 'Successful take-on',
          startSec: (s.tSec - 5).clamp(0, double.infinity),
          endSec: s.tSec + 4,
          kind: 'takeOn',
        ));
      }
      if (s.recovery) {
        clips.add(HighlightClip(
          label: 'Possession recovery',
          startSec: (s.tSec - 5).clamp(0, double.infinity),
          endSec: s.tSec + 3,
          kind: 'recovery',
        ));
      }
    }
    // Cap the reel, keep chronological order.
    clips.sort((a, b) => a.startSec.compareTo(b.startSec));
    final reel = clips.length > 24 ? clips.sublist(0, 24) : clips;

    // ---- heatmap cells ------------------------------------------------------
    final cells = <HeatCell>[];
    for (var x = 0; x < 12; x++) {
      for (var y = 0; y < 8; y++) {
        if (heat[x][y] > 0) {
          cells.add(HeatCell(x: x, y: y, weight: heat[x][y]));
        }
      }
    }

    return MatchReport(
      totalDistanceM: distance,
      avgSpeedKmh: avgKmh,
      peakSpeedKmh: peakKmh,
      bursts: bursts,
      heatmap: cells,
      passAttempts: passAttempts,
      passCompletions: passCompletions,
      takeOnsWon: takeOnsWon,
      takeOnsLost: 0,
      tackles: tackles,
      recoveries: recoveries,
      avgRecoverySec:
          recoveries == 0 ? 0 : recoverySecSum / recoveries,
      touches: touches,
      shots: shots,
      clips: reel,
      topSpeedZones: (sprintZoneSec / 60).round(),
    );
  }
}
