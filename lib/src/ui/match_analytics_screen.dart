import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/tracking_engine.dart';
import '../analytics/tracking_session.dart';
import '../data/radar_repository.dart';
import '../models/stream_bounty.dart';
import 'radar_theme.dart';

/// AI-Powered Player Tracking & Match Analytics — the automated post-match
/// scouting report card generated from the tracking engine's telemetry:
/// heatmap + distance, sprint peaks and bursts, technical rates, and an
/// auto-sliced highlight reel of every touch, tackle and shot.
class MatchAnalyticsScreen extends ConsumerStatefulWidget {
  const MatchAnalyticsScreen({
    super.key,
    required this.bounty,
    this.session,
  });

  final StreamBounty bounty;

  /// Pre-loaded session (demo); when null it is fetched by bounty id.
  final TrackingSession? session;

  @override
  ConsumerState<MatchAnalyticsScreen> createState() =>
      _MatchAnalyticsScreenState();
}

class _MatchAnalyticsScreenState extends ConsumerState<MatchAnalyticsScreen> {
  TrackingSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.session != null) {
      setState(() {
        _session = widget.session;
        _loading = false;
      });
      return;
    }
    final s = await RadarRepository.instance
        .fetchTrackingSession(widget.bounty.id);
    if (!mounted) return;
    setState(() {
      _session = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bounty;
    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: const Text('Match analytics',
            style: TextStyle(fontSize: 17)),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: RadarTheme.radar),
                  SizedBox(height: 12),
                  Text('Crunching tracking telemetry…',
                      style: TextStyle(color: RadarTheme.textDim)),
                ],
              ),
            )
          : (_session == null)
              ? _NoTelemetry(bounty: b)
              : _ReportView(session: _session!, bounty: b),
    );
  }
}

class _NoTelemetry extends StatelessWidget {
  const _NoTelemetry({required this.bounty});

  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.radar, size: 46, color: RadarTheme.textDim),
            const SizedBox(height: 14),
            Text(
              bounty.isLive
                  ? 'Tracking engine warming up'
                  : 'No tracking telemetry yet',
              style: const TextStyle(
                  color: RadarTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              bounty.isLive
                  ? 'The CV engine is locking onto the target player. '
                      'The report card publishes once frames accumulate.'
                  : 'Telemetry publishes when the streamer\'s tracker has '
                      'processed the broadcast.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: RadarTheme.textDim, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.session, required this.bounty});

  final TrackingSession session;
  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    final report = session.analyze()!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(session: session, report: report, bounty: bounty),
        const SizedBox(height: 14),
        _HeatmapCard(report: report),
        const SizedBox(height: 14),
        _PhysicalCard(report: report),
        const SizedBox(height: 14),
        _TechnicalCard(report: report),
        const SizedBox(height: 14),
        _HighlightReelCard(report: report),
        const SizedBox(height: 30),
      ],
    );
  }
}

// ------------------------------------------------------------------- header

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.session,
    required this.report,
    required this.bounty,
  });

  final TrackingSession session;
  final MatchReport report;
  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    final score = report.overallScore;
    final gradeColor =
        score >= 75 ? RadarTheme.radar : (score >= 50 ? RadarTheme.gold : RadarTheme.alert);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.playerLabel,
                        style: const TextStyle(
                            color: RadarTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'AI tracking · ${(session.lockConfidence * 100).toStringAsFixed(0)}% lock confidence'
                      ' · ${session.durationMin} min',
                      style: const TextStyle(
                          color: RadarTheme.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 74,
                height: 74,
                child: Stack(children: [
                  SizedBox(
                    width: 74,
                    height: 74,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 6,
                      color: gradeColor,
                      backgroundColor: RadarTheme.panelHigh,
                    ),
                  ),
                  Center(
                    child: Text(score.toStringAsFixed(0),
                        style: TextStyle(
                            color: gradeColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Bounty: ${bounty.title}',
              style: const TextStyle(
                  color: RadarTheme.textDim, fontSize: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ heatmap

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    final maxW =
        report.heatmap.fold<int>(1, (m, c) => math.max(m, c.weight));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Positional heatmap',
                style: TextStyle(
                    color: RadarTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const Spacer(),
            Text('${report.distanceKm.toStringAsFixed(1)} km covered',
                style: const TextStyle(
                    color: RadarTheme.radar,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: CustomPaint(
              size: Size.infinite,
              painter: _HeatmapPainter(
                cells: report.heatmap,
                maxWeight: maxW,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Attack direction →    (viewer goal on the left; intensity = '
            'time on pitch)',
            style: TextStyle(color: RadarTheme.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.cells, required this.maxWeight});

  final List<HeatCell> cells;
  final int maxWeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Pitch outline.
    final pitch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = RadarTheme.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(8)),
      pitch,
    );
    // Halfway line + boxes.
    canvas.drawLine(Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height), pitch);
    canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.25, size.width * 0.14,
            size.height * 0.5),
        pitch);
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.86, size.height * 0.25,
            size.width * 0.14, size.height * 0.5),
        pitch);

    // Heat cells — normalized (cell x/12, y/8).
    const cols = 12.0;
    const rows = 8.0;
    final cw = size.width / cols;
    final ch = size.height / rows;
    final fill = Paint();
    for (final c in cells) {
      final t = c.weight / maxWeight;
      fill.color = Color.lerp(
          RadarTheme.radar.withValues(alpha: 0.06),
          RadarTheme.radar.withValues(alpha: 0.72),
          t)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(c.x * cw + 1, c.y * ch + 1, cw - 2, ch - 2),
          const Radius.circular(3),
        ),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.cells != cells || old.maxWeight != maxWeight;
}

// ----------------------------------------------------------------- physical

class _PhysicalCard extends StatelessWidget {
  const _PhysicalCard({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Physical output',
              style: TextStyle(
                  color: RadarTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('Peak speed', report.peakSpeedKmh.toStringAsFixed(1),
                  'km/h', RadarTheme.radar),
              const SizedBox(width: 10),
              _metric('Avg speed', report.avgSpeedKmh.toStringAsFixed(1),
                  'km/h', RadarTheme.info),
              const SizedBox(width: 10),
              _metric('Distance', report.distanceKm.toStringAsFixed(1), 'km',
                  RadarTheme.gold),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${report.bursts.length} acceleration bursts · '
            '${report.topSpeedZones} min in the sprint zone (24+ km/h)',
            style: const TextStyle(color: RadarTheme.textDim, fontSize: 12.5),
          ),
          if (report.bursts.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final b in report.bursts.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.bolt, color: RadarTheme.gold, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    '${_clock(b.startSec)} — ${_clock(b.endSec)}: peak '
                    '${b.peakKmh.toStringAsFixed(1)} km/h over '
                    '${b.distanceM.toStringAsFixed(0)} m',
                    style: const TextStyle(
                        color: RadarTheme.textPrimary, fontSize: 12.5),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  static String _clock(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).round().toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _metric(String label, String value, String unit, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: RadarTheme.panelHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                      text: value,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                          color: RadarTheme.textDim, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style:
                    const TextStyle(color: RadarTheme.textDim, fontSize: 11)),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- technical

class _TechnicalCard extends StatelessWidget {
  const _TechnicalCard({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Technical breakdown',
              style: TextStyle(
                  color: RadarTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 12),
          _bar('Pass completion', report.passRate,
              '${report.passCompletions}/${report.passAttempts}'),
          const SizedBox(height: 10),
          _bar('Take-on success', report.takeOnRate,
              '${report.takeOnsWon} won'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.gps_fixed, '${report.touches} touches',
                  RadarTheme.radar),
              _chip(Icons.sports_baseball, '${report.shots} shots',
                  RadarTheme.gold),
              _chip(Icons.shield_outlined, '${report.tackles} tackles',
                  RadarTheme.info),
              _chip(Icons.replay, '${report.recoveries} recoveries',
                  RadarTheme.radar),
              if (report.recoveries > 0)
                _chip(
                    Icons.timer,
                    '${report.avgRecoverySec.toStringAsFixed(0)}s avg recovery',
                    RadarTheme.textDim),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(String label, double pct, String detail) {
    final color =
        pct >= 70 ? RadarTheme.radar : (pct >= 45 ? RadarTheme.gold : RadarTheme.alert);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: const TextStyle(
                  color: RadarTheme.textPrimary, fontSize: 13)),
          const Spacer(),
          Text('${pct.toStringAsFixed(0)}%  $detail',
              style: TextStyle(
                  color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 7,
            color: color,
            backgroundColor: RadarTheme.panelHigh,
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

// ------------------------------------------------------------ highlight reel

class _HighlightReelCard extends StatelessWidget {
  const _HighlightReelCard({required this.report});

  final MatchReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Auto-generated highlight reel',
                style: TextStyle(
                    color: RadarTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const Spacer(),
            Text('${report.clips.length} clips',
                style: const TextStyle(
                    color: RadarTheme.textDim, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          const Text(
            'The tracking engine auto-slices every touch, tackle, take-on '
            'and shot into scout-ready clips.',
            style: TextStyle(color: RadarTheme.textDim, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          if (report.clips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No highlight events detected in this session.',
                  style: TextStyle(color: RadarTheme.textDim, fontSize: 12.5)),
            )
          else
            ...[
              for (final clip in report.clips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: RadarTheme.panelHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: RadarTheme.stroke),
                    ),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _clipColor(clip.kind).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(_clipIcon(clip.kind),
                            size: 17, color: _clipColor(clip.kind)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(clip.label,
                                style: const TextStyle(
                                    color: RadarTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(clip.windowLabel,
                                style: const TextStyle(
                                    color: RadarTheme.textDim, fontSize: 11)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _clipColor(clip.kind).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(clip.kindLabel,
                            style: TextStyle(
                                color: _clipColor(clip.kind),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
            ],
        ],
      ),
    );
  }

  Color _clipColor(String kind) => switch (kind) {
        'shot' || 'goal' => RadarTheme.gold,
        'tackle' => RadarTheme.info,
        'takeOn' => RadarTheme.radar,
        'recovery' => RadarTheme.pi,
        _ => RadarTheme.textDim,
      };

  IconData _clipIcon(String kind) => switch (kind) {
        'shot' || 'goal' => Icons.sports_baseball,
        'tackle' => Icons.shield,
        'takeOn' => Icons.bolt,
        'recovery' => Icons.replay,
        _ => Icons.videocam,
      };
}
