import 'dart:math' as math;

import 'tracking_engine.dart';

/// One AI-tracking session attached to a bounty broadcast: the engine locks
/// onto the target player (jersey-number + gait CV lock) and accumulates
/// telemetry for the post-match breakdown.
class TrackingSession {
  TrackingSession({
    required this.id,
    required this.bountyId,
    required this.playerLabel,
    required this.startedAt,
    required this.durationMin,
    List<TrackSample>? samples,
    this.lockConfidence = 0.93,
    this.report,
  }) : samples = samples ?? const [];

  final String id;
  final String bountyId;

  /// What the CV engine locked onto, e.g. "Player #7 (RW) — Golden Coast".
  final String playerLabel;
  final DateTime startedAt;

  /// Planned tracking duration in minutes (mirrors the bounty length).
  final int durationMin;

  /// Mean tracker confidence (jersey lock + gait match), 0..1.
  final double lockConfidence;

  final List<TrackSample> samples;

  /// Cached breakdown — computed once the telemetry stream completes.
  final MatchReport? report;

  MatchReport? analyze() => report ?? TrackingEngine.analyze(samples);

  /// Deterministic synthetic telemetry for a full match: a believable
  /// blend of positional play, sprints toward the box, passes, take-ons,
  /// defensive recoveries and shots. Used in demo mode and to preview the
  /// report while a real broadcast is still streaming.
  static TrackingSession synthetic({
    required String id,
    required String bountyId,
    String playerLabel = 'Player #7 (RW)',
    int durationMin = 90,
    int seed = 7,
  }) {
    final rng = math.Random(seed);
    final samples = <TrackSample>[];
    const dt = 1.0; // one frame per second (30 Hz decimated for transport)
    final totalSec = durationMin * 60;

    var x = 70.0 + rng.nextDouble() * 20; // wide right third
    var y = 8.0 + rng.nextDouble() * 10;

    for (var t = 0.0; t < totalSec; t += dt) {
      // Slow drift with periodic sprints down the flank and cutbacks inside.
      final phase = (t / 45) % (2 * math.pi);
      final sprinting = (t % 120) > 95 && (t % 120) < 118; // ~23 s effort
      final speed = sprinting ? 8.5 + rng.nextDouble() * 2 : 1.2 + rng.nextDouble() * 1.6;
      final direction = math.sin(phase) * 0.35 + (sprinting ? 0.15 : 0.0);
      x += math.cos(direction) * speed * dt * (sprinting ? 1 : 0.5);
      y += math.sin(direction) * speed * dt * (sprinting ? 1 : 0.5);
      // Keep in bounds, drift back when out.
      if (x > 103) x = 103 - rng.nextDouble() * 8;
      if (x < 5) x = 5 + rng.nextDouble() * 10;
      if (y > 64) y = 64 - rng.nextDouble() * 6;
      if (y < 4) y = 4 + rng.nextDouble() * 6;

      var onBall = false, shot = false, tackle = false;
      var takeOn = false, recovery = false, pass = false, passOk = true;

      // Possession windows every ~35 s: touch + pass/take-on/shot choice.
      if ((t % 35) < dt) {
        onBall = true;
        final roll = rng.nextDouble();
        if (roll < 0.55) {
          pass = true;
          passOk = rng.nextDouble() < 0.82; // 82% completion
        } else if (roll < 0.8) {
          takeOn = true;
        } else if (roll < 0.88) {
          shot = true;
        } else {
          recovery = true;
        }
      }
      // Defensive tracking back: recovery chase after opponent switches play.
      if ((t % 97) > 90 && (t % 97) < 92) {
        recovery = true;
      }
      // Ground duel won as a tackle every ~150 s.
      if ((t % 150) < dt) tackle = true;

      samples.add(TrackSample(
        tSec: t,
        x: x,
        y: y,
        onBall: onBall,
        shot: shot,
        tackle: tackle,
        takeOn: takeOn,
        recovery: recovery,
        pass: pass,
        passCompleted: passOk,
      ));
    }

    return TrackingSession(
      id: id,
      bountyId: bountyId,
      playerLabel: playerLabel,
      startedAt: DateTime.now().subtract(Duration(minutes: durationMin)),
      durationMin: durationMin,
      lockConfidence: 0.90 + rng.nextDouble() * 0.08,
      samples: samples,
      report: TrackingEngine.analyze(samples),
    );
  }
}

/// JSON adapter for persisted tracking frames.
class TrackSampleJson {
  const TrackSampleJson._();

  static TrackSample fromJson(Map<String, Object?> json) => TrackSample(
        tSec: (json['t'] as num?)?.toDouble() ?? 0,
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        onBall: json['b'] as bool? ?? false,
        shot: json['s'] as bool? ?? false,
        tackle: json['t'] as bool? ?? false,
        takeOn: json['d'] as bool? ?? false,
        recovery: json['r'] as bool? ?? false,
        pass: json['p'] as bool? ?? false,
        passCompleted: json['pc'] as bool? ?? true,
      );
}
