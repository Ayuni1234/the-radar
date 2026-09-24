import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/tracking_session.dart';
import '../models/enums.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/radar_providers.dart';
import 'match_analytics_screen.dart';
import 'radar_theme.dart';

/// "Blind Scouting" test mode — removes identity bias from evaluation.
///
/// Scouts review anonymized performance cards: real engine telemetry and
/// AI-edited clips, but the player appears only as "Candidate A/B/C…" with
/// no name, school, club, market value or profile photo. After rating all
/// candidates, the identities are revealed side-by-side with the scout's
/// verdicts — making raw talent the primary metric and showing whether
/// the scout's rankings changed once identity became visible.
class BlindTestScreen extends ConsumerStatefulWidget {
  const BlindTestScreen({super.key});

  @override
  ConsumerState<BlindTestScreen> createState() => _BlindTestScreenState();
}

class _BlindTestScreenState extends ConsumerState<BlindTestScreen> {
  final Map<String, double> _ratings = {};
  final Map<String, String> _notes = {};
  bool _revealed = false;

  late final List<(String, TrackingSession)> _candidates;

  @override
  void initState() {
    super.initState();
    // Build an anonymized pool from real demo profiles (live: from the
    // directory), each with a deterministic synthetic tracking session.
    _candidates = _buildPool();
  }

  List<(String, TrackingSession)> _buildPool() {
    final profiles = ref.read(profilesProvider).value ?? const <UserProfile>[];
    final players = profiles
        .where((p) => p.role == UserRole.player && !p.isMinor)
        .take(3)
        .toList();
    if (players.length < 3) {
      // Pad the pool so the test is always meaningful.
      final synth = List.generate(3 - players.length, (i) => UserProfile(
            id: 'blind-synth-$i',
            piUid: 'blind-synth-$i',
            username: 'candidate-${String.fromCharCode(65 + i)}',
            displayName: 'Candidate ${String.fromCharCode(65 + i)}',
            role: UserRole.player,
            credibilityScore: 0,
            kycVerified: false,
            createdAt: DateTime(2026, 1, 1),
          ));
      players.addAll(synth);
    }
    final pool = <(String, TrackingSession)>[];
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      pool.add((
        'Candidate ${String.fromCharCode(65 + i)}',
        TrackingSession.synthetic(
          id: 'blind-${p.id}',
          bountyId: 'blind-${p.id}',
          playerLabel: 'Candidate ${String.fromCharCode(65 + i)} · '
              'outfield ${2020 + i * 3}',
          seed: 100 + i * 17,
          durationMin: 60,
        ),
      ));
    }
    // Shuffle deterministically so position ≠ identity each session.
    pool.shuffle(math.Random(42));
    return pool;
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];
    final allRated = _ratings.length == _candidates.length;
    final avg = _ratings.isEmpty
        ? 0.0
        : _ratings.values.reduce((a, b) => a + b) / _ratings.length;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: Row(children: [
           Icon(Icons.visibility_off, size: 19, color: RadarTheme.pi),
          const SizedBox(width: 8),
          const Text('Blind scouting test',
              style: TextStyle(fontSize: 16.5)),
        ]),
      ),
      body: !_revealed
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: RadarTheme.pi.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: RadarTheme.pi.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(
                        'Bias-free evaluation protocol',
                        style: TextStyle(
                            color: RadarTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You are seeing anonymized AI-tracked performance cards. '
                        'Names, schools, clubs and market values are hidden — '
                        'rate the raw talent. Identities are revealed only after '
                        'you have scored every candidate.\n\n'
                        'Average so far: ${avg.toStringAsFixed(1)}/10 · '
                        '${_ratings.length}/${_candidates.length} rated',
                        style:  TextStyle(
                            color: RadarTheme.textDim,
                            fontSize: 12.5,
                            height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final (label, session) in _candidates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _BlindCandidateCard(
                      label: label,
                      session: session,
                      rating: _ratings[label],
                      onRate: (v) => setState(() => _ratings[label] = v),
                      onOpenReport: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MatchAnalyticsScreen(
                            bounty: _fakeBounty(session),
                            session: session,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: allRated ? RadarTheme.pi : null,
                  ),
                  onPressed: allRated ? () => setState(() => _revealed = true) : null,
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                  label: Text(allRated
                      ? 'Reveal identities & compare'
                      : 'Rate all ${_candidates.length} candidates to reveal'),
                ),
                const SizedBox(height: 30),
              ],
            )
          : _RevealView(
              candidates: _candidates,
              ratings: _ratings,
              notes: _notes,
              profiles: profiles,
              onRestart: () => setState(() {
                _ratings.clear();
                _notes.clear();
                _revealed = false;
              }),
            ),
    );
  }

  StreamBounty _fakeBounty(TrackingSession session) {
    // The analytics screen reads a bounty's title for context only.
    return StreamBounty(
      id: session.bountyId,
      posterProfileId: 'blind-test',
      posterName: 'Blind test',
      title: 'Blind-test evaluation: ${session.playerLabel}',
      brief: 'Anonymized evaluation session.',
      areaName: 'Blind pool',
      amountPi: 0,
      durationMinutes: session.durationMin,
      status: 'completed',
      createdAt: DateTime.now(),
    );
  }
}

// ------------------------------------------------------------- candidate card

class _BlindCandidateCard extends StatelessWidget {
  const _BlindCandidateCard({
    required this.label,
    required this.session,
    required this.rating,
    required this.onRate,
    required this.onOpenReport,
  });

  final String label;
  final TrackingSession session;
  final double? rating;
  final ValueChanged<double> onRate;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final report = session.analyze()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: rating != null
                ? RadarTheme.pi.withValues(alpha: 0.5)
                : RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: RadarTheme.pi.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(label.split(' ').last,
                  style:  TextStyle(
                      color: RadarTheme.pi,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$label · ${session.durationMin} min tracked',
                style:  TextStyle(
                    color: RadarTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5),
              ),
            ),
            TextButton.icon(
              onPressed: onOpenReport,
              icon: const Icon(Icons.query_stats, size: 15),
              label: const Text('Full card', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat(Icons.directions_run,
                  '${report.distanceKm.toStringAsFixed(1)} km', 'distance'),
              _stat(Icons.speed,
                  '${report.peakSpeedKmh.toStringAsFixed(1)} km/h', 'peak'),
              _stat(Icons.swap_horiz,
                  '${report.passRate.toStringAsFixed(0)}%', 'pass rate'),
              _stat(Icons.bolt,
                  '${report.bursts.length}', 'bursts'),
              _stat(Icons.sports_baseball, '${report.shots}', 'shots'),
              _stat(Icons.shield_outlined, '${report.tackles}', 'tackles'),
            ],
          ),
          const SizedBox(height: 10),
          // The "AI-edited skill clip" strip: the engine's auto-sliced reel
          // preview, anonymized by construction (no faces/names — telemetry
          // windows only).
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final clip in report.clips.take(6))
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: RadarTheme.panelHigh,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: RadarTheme.stroke),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                       Icon(Icons.movie_filter,
                          size: 13, color: RadarTheme.radar),
                      const SizedBox(width: 5),
                      Text('${clip.kindLabel} ${clip.windowLabel.split('–').first.trim()}',
                          style:  TextStyle(
                              color: RadarTheme.textDim, fontSize: 11)),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Slider(
                value: rating ?? 5,
                min: 1,
                max: 10,
                divisions: 9,
                label: (rating ?? 5).toStringAsFixed(0),
                activeColor: RadarTheme.pi,
                onChanged: onRate,
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                rating == null ? '—/10' : '${rating!.toStringAsFixed(0)}/10',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: rating == null ? RadarTheme.textDim : RadarTheme.pi,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: RadarTheme.panelHigh,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: RadarTheme.radar),
          const SizedBox(width: 5),
          Text('$value $label',
              style:  TextStyle(
                  color: RadarTheme.textPrimary, fontSize: 11.5)),
        ]),
      );
}

// ------------------------------------------------------------------- reveal

class _RevealView extends StatelessWidget {
  const _RevealView({
    required this.candidates,
    required this.ratings,
    required this.notes,
    required this.profiles,
    required this.onRestart,
  });

  final List<(String, TrackingSession)> candidates;
  final Map<String, double> ratings;
  final Map<String, String> notes;
  final List<UserProfile> profiles;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    // Rank by the scout's blind rating.
    final ranked = candidates.toList()
      ..sort((a, b) => (ratings[b.$1] ?? 0).compareTo(ratings[a.$1] ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RadarTheme.radar.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RadarTheme.radar.withValues(alpha: 0.4)),
          ),
          child:  Text(
            'Identities revealed. Compare your blind verdicts against who the '
            'candidates actually are — if your ranking surprises you, the bias '
            'check did its job.',
            style: TextStyle(color: RadarTheme.textPrimary, fontSize: 13,
                height: 1.45),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < ranked.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RevealCard(
              rank: i + 1,
              label: ranked[i].$1,
              session: ranked[i].$2,
              rating: ratings[ranked[i].$1] ?? 0,
              profile: _resolveProfile(ranked[i].$2),
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Run another blind test'),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  UserProfile? _resolveProfile(TrackingSession session) {
    final id = session.bountyId.replaceFirst('blind-', '');
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class _RevealCard extends StatelessWidget {
  const _RevealCard({
    required this.rank,
    required this.label,
    required this.session,
    required this.rating,
    required this.profile,
  });

  final int rank;
  final String label;
  final TrackingSession session;
  final double rating;
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final report = session.analyze()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rank == 1
            ? RadarTheme.radar.withValues(alpha: 0.07)
            : RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: rank == 1
                ? RadarTheme.radar.withValues(alpha: 0.5)
                : RadarTheme.stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 1
                  ? RadarTheme.radar.withValues(alpha: 0.16)
                  : RadarTheme.panelHigh,
              shape: BoxShape.circle,
            ),
            child: Text('#$rank',
                style: TextStyle(
                    color: rank == 1 ? RadarTheme.radar : RadarTheme.textDim,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile != null
                      ? '${profile!.displayName} · ${profile!.clubAffiliation ?? 'unaffiliated'}'
                      : '$label (synthetic candidate)',
                  style:  TextStyle(
                      color: RadarTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  'Your blind verdict: ${rating.toStringAsFixed(0)}/10 · '
                  '${report.distanceKm.toStringAsFixed(1)} km · '
                  '${report.peakSpeedKmh.toStringAsFixed(0)} km/h peak · '
                  '${report.passRate.toStringAsFixed(0)}% passing',
                  style:  TextStyle(
                      color: RadarTheme.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          if (profile != null && profile!.kycVerified)
             Icon(Icons.verified, size: 16, color: RadarTheme.radar),
        ],
      ),
    );
  }
}
