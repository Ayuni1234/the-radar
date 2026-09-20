import 'package:flutter_test/flutter_test.dart';
import 'package:the_radar/src/analytics/tracking_engine.dart';

void main() {
  group('TrackingEngine.analyze', () {
    test('computes distance along a straight line and average speed', () {
      // 100 m in 100 s along the touchline → 1 m/s = 3.6 km/h.
      final samples = List.generate(101, (i) => TrackSample(
            tSec: i.toDouble(),
            x: i.toDouble(),
            y: 10,
          ));
      final report = TrackingEngine.analyze(samples);
      expect(report.totalDistanceM, closeTo(100, 0.5));
      expect(report.avgSpeedKmh, closeTo(3.6, 0.1));
    });

    test('detects a sprint burst with its peak speed', () {
      final samples = <TrackSample>[];
      for (var i = 0; i <= 30; i++) {
        samples.add(TrackSample(tSec: i.toDouble(), x: i * 1.0, y: 10));
      }
      // Sprint 10 m/s between t=10 and t=20.
      for (var i = 31; i <= 40; i++) {
        samples.add(TrackSample(tSec: i.toDouble(), x: 30 + (i - 30) * 10.0, y: 10));
      }
      for (var i = 41; i <= 60; i++) {
        samples.add(TrackSample(tSec: i.toDouble(), x: 130 + (i - 40) * 1.0, y: 10));
      }
      final report = TrackingEngine.analyze(samples);
      expect(report.bursts, isNotEmpty);
      expect(report.bursts.first.peakKmh, greaterThan(30));
      expect(report.peakSpeedKmh, greaterThan(30));
    });

    test('pass completion rate counts attempts and completions', () {
      final samples = [
        for (var i = 0; i < 8; i++)
          TrackSample(
            tSec: i * 10.0,
            x: 20 + i * 5.0,
            y: 30,
            pass: true,
            passCompleted: i < 6, // 6 of 8 completed = 75%
          ),
      ];
      final report = TrackingEngine.analyze(samples);
      expect(report.passAttempts, 8);
      expect(report.passCompletions, 6);
      expect(report.passRate, closeTo(75, 0.01));
    });

    test('auto-slices clips for every shot, tackle and take-on', () {
      final samples = [
        TrackSample(tSec: 100, x: 60, y: 34, shot: true),
        TrackSample(tSec: 250, x: 40, y: 20, tackle: true),
        TrackSample(tSec: 400, x: 70, y: 50, takeOn: true),
      ];
      final report = TrackingEngine.analyze(samples);
      expect(report.clips.length, 3);
      expect(report.clips.map((c) => c.kind),
          containsAll(['shot', 'tackle', 'takeOn']));
      // Clips are chronological.
      expect(report.clips.first.startSec, lessThan(report.clips.last.startSec));
      // Shot window is padded ±(6s/4s) and clamped at 0 for early events.
      final early = TrackingEngine.analyze(
          [TrackSample(tSec: 2, x: 60, y: 34, shot: true)]);
      expect(early.clips.first.startSec, 0);
    });

    test('heatmap aggregates samples into the 12×8 grid', () {
      final samples = [
        TrackSample(tSec: 1, x: 52, y: 34),
        TrackSample(tSec: 2, x: 53, y: 35),
      ];
      final report = TrackingEngine.analyze(samples);
      expect(report.heatmap, isNotEmpty);
      final total = report.heatmap.fold<int>(0, (s, c) => s + c.weight);
      expect(total, 2);
    });

    test('empty telemetry yields a zeroed report without crashing', () {
      final report = TrackingEngine.analyze(const []);
      expect(report.totalDistanceM, 0);
      expect(report.clips, isEmpty);
      expect(report.passRate, 0);
      expect(report.overallScore, 0);
    });
  });
}
