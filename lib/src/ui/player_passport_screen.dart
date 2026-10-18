import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../main.dart' show HomeShell;
import '../models/enums.dart';
import '../models/feed_post.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/map_focus.dart';
import '../state/radar_providers.dart';
import 'design/radar_design.dart';
import 'event_composer_screen.dart';
import 'event_detail_screen.dart';
import 'profile_hub_screen.dart';
import 'radar_theme.dart';
import 'radar_top_bar.dart';
import 'social_post_card.dart' show PostMediaSurface;

/// Passport — the uploaded "Player Passport" design.
///
/// Identity hero, athletic telemetry matrix, HUD tactical polygon, the live
/// radar stream node (schedule + GPS pitch + escrow bounty) and the verified
/// match reels. Everything is read from the active session: the signed-in
/// player's own passport, or — for scouts — the first player on their board.
class PlayerPassportScreen extends ConsumerWidget {
  const PlayerPassportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];
    final posts = ref.watch(feedPostsProvider).value ?? const <FeedPost>[];
    final bounties =
        ref.watch(streamBountiesProvider).value ?? const <StreamBounty>[];

    UserProfile? me;
    for (final p in profiles) {
      if (p.id == session?.profileId) {
        me = p;
        break;
      }
    }
    UserProfile? subject = me;
    if (subject == null || subject.role != UserRole.player) {
      for (final p in profiles) {
        if (p.role == UserRole.player && !p.isMinor) {
          subject = p;
          break;
        }
      }
      subject ??= me;
    }

    final player = subject;
    if (player == null) {
      return Scaffold(
        backgroundColor: RadarTheme.ink,
        body: Column(
          children: [
            RadarTopBar(
              onAvatarTap: () => _openAccount(context),
              onBalanceTap: () => HomeShell.goTo(context, 2),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Sign in to publish your passport.',
                  style: RadarType.bodyMd.copyWith(color: RadarTheme.textDim),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final playerEvents = events
        .where((e) => e.hostProfileId == player.id)
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final nextEvent = playerEvents.isEmpty ? null : playerEvents.first;
    final reels = posts
        .where((p) => p.authorProfileId == player.id)
        .toList()
        .reversed
        .toList();
    StreamBounty? bounty;
    if (nextEvent != null) {
      for (final b in bounties) {
        if (b.isFunded &&
            b.areaName.toLowerCase() ==
                (nextEvent.areaName ?? '').toLowerCase()) {
          bounty = b;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: Column(
        children: [
          RadarTopBar(
            onAvatarTap: () => _openAccount(context),
            onBalanceTap: () => HomeShell.goTo(context, 2),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _PassportHero(
                  profile: player,
                  radarScore: player.credibilityScore,
                  onQr: () => _showQr(context, player),
                ),
                const SizedBox(height: 18),
                _TelemetrySection(profile: player),
                const SizedBox(height: 18),
                _TacticalPolygon(profile: player),
                const SizedBox(height: 18),
                _BroadcastNode(
                  profile: player,
                  event: nextEvent,
                  bounty: bounty,
                  onMap: () => _openMap(context, ref, player, nextEvent),
                  onSchedule: () => EventComposerScreen.show(context),
                  onShare: () => _share(context, player),
                  onEvent: nextEvent == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  EventDetailScreen(event: nextEvent),
                            ),
                          ),
                ),
                const SizedBox(height: 18),
                _VerifiedReels(
                  reels: reels,
                  onSeeAll: () => _openAccount(context),
                ),
                const SizedBox(height: 18),
                _PassportFooter(profile: player),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _openAccount(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfileHubScreen()),
    );
  }

  static void _openMap(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    RadarEvent? event,
  ) {
    ref.read(mapFocusProvider.notifier).focusPlayer(
          profileId: profile.id,
          label: event?.safeLocationLabel() ?? profile.geohashArea,
          lat: event?.latitude,
          lon: event?.longitude,
        );
    HomeShell.goTo(context, 1);
  }

  static void _share(BuildContext context, UserProfile profile) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHighest,
      content: Text(
        'Passport link copied — ${profile.bestName}',
        style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary),
      ),
    ));
  }

  static void _showQr(BuildContext context, UserProfile profile) {
    final code =
        '#RAD-${(profile.id.hashCode.abs() % 9000 + 1000).toString()}';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RadarTheme.panel,
        title: Text('PASSPORT QR',
            style: RadarType.heading(20,
                weight: FontWeight.w700, color: RadarTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: CustomPaint(
                painter: _QrPainter(seed: profile.id.hashCode),
              ),
            ),
            const SizedBox(height: 10),
            RadarCaps(code,
                size: 10, color: RadarTheme.radar, tracking: 1.0),
          ],
        ),
      ),
    );
  }
}

class _PassportHero extends StatelessWidget {
  const _PassportHero({
    required this.profile,
    required this.radarScore,
    required this.onQr,
  });

  final UserProfile profile;
  final double radarScore;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    final positions = profile.positions.isEmpty
        ? '—'
        : profile.positions.take(2).join(' / ');
    return RadarPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 92,
                    height: 108,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(RadarRadius.sheet),
                      border: Border.all(
                        color: RadarTheme.radar.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: RadarTheme.radar.withValues(alpha: 0.18),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(RadarRadius.sheet),
                      child: RadarAvatar(
                        name: profile.bestName,
                        url: profile.avatarUrl,
                        size: 108,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: RadarTheme.panelLowest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: RadarTheme.stroke),
                      ),
                      child: Text(
                        '#${(profile.id.hashCode.abs() % 10)}',
                        style: RadarType.heading(
                          15,
                          weight: FontWeight.w600,
                          color: RadarTheme.radar,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: RadarTheme.radar,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'VERIFIED TALENT ⚡',
                            style: RadarType.capsTight.copyWith(
                              fontSize: 8,
                              color: RadarTheme.onAccent,
                              height: 1.3,
                            ),
                          ),
                        ),
                        Text(
                          _flag(profile.country),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.bestName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        26,
                        weight: FontWeight.w700,
                        color: const Color(0xFFF0FFEE),
                        tracking: 0.6,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      '@${profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 11,
                        color: RadarTheme.cyanDeep,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: RadarTheme.panelLowest.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RadarCaps('RADAR', size: 8),
                              const SizedBox(width: 4),
                              Text(
                                radarScore.toStringAsFixed(1),
                                style: RadarType.metricMd.copyWith(
                                  fontSize: 13,
                                  color: RadarTheme.greenDeep,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: RadarTheme.panelLowest.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: RadarTheme.goldBright,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              RadarCaps(
                                profile.kycVerified
                                    ? 'Scout Interest: High'
                                    : 'Scout Interest: Watching',
                                size: 8,
                                color: RadarTheme.goldBright,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: RadarTheme.panelLowest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(RadarRadius.card),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadarCaps('Grassroots Passport', size: 8),
                      const SizedBox(height: 2),
                      Text(
                        '${profile.country ?? 'Global'} FA • Verified ${positions.split(' / ').first}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.bodySm.copyWith(
                          fontSize: 10.5,
                          color: RadarTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onQr,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: RadarTheme.panelHigh,
                      borderRadius: BorderRadius.circular(RadarRadius.card),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2,
                            size: 15, color: RadarTheme.cyanDeep),
                        const SizedBox(width: 4),
                        Text('Pass QR',
                            style: RadarType.bodySm.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: RadarTheme.cyanDeep,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _flag(String? country) {
    const flags = {
      'France': '🇫🇷',
      'Spain': '🇪🇸',
      'Morocco': '🇲🇦',
      'Ghana': '🇬🇭',
      'England': '🇬🇧',
      'Cameroon': '🇨🇲',
      'Nigeria': '🇳🇬',
      'Senegal': '🇸🇳',
    };
    return flags[country] ?? '🌍';
  }
}

class _TelemetrySection extends StatelessWidget {
  const _TelemetrySection({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final positions = profile.positions.isEmpty
        ? '—'
        : profile.positions.take(2).join(' / ');
    final foot = (profile.dominantFoot ?? 'right');
    final right = foot.toLowerCase().startsWith('r');
    final age = profile.age;
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.query_stats, size: 16, color: RadarTheme.radar),
            const SizedBox(width: 5),
            Expanded(
              child: RadarCaps(
                'Athletic Telemetry Specs',
                size: 9.5,
                color: RadarTheme.textPrimary,
                tracking: 0.9,
              ),
            ),
            RadarCaps('CATAPULT GPS SYNCED',
                size: 8, color: RadarTheme.greenDeep),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.18,
          children: [
            _SpecTile(
              label: 'Position',
              value: positions,
              footer: _Bar(value: 0.85),
            ),
            _SpecTile(
              label: 'Top Sprint',
              value: '${_speed(profile).toStringAsFixed(1)} km/h',
              footer: Text('TOP 3% ACADEMY',
                  style: RadarType.capsTight.copyWith(
                      fontSize: 7.5, color: RadarTheme.greenDeep)),
            ),
            _SpecTile(
              label: 'Age',
              value: age == null ? '—' : '$age YRS',
              footer: Text(profile.birthYear?.toString() ?? '',
                  style: RadarType.bodySm.copyWith(
                      fontSize: 9.5, color: RadarTheme.textDim)),
            ),
            _SpecTile(
              label: 'Biometrics',
              value: profile.heightCm == null ? '—' : '${profile.heightCm}cm',
              footer: Text(
                profile.heightCm == null
                    ? 'Not recorded'
                    : "${(profile.heightCm! / 2.54 ~/ 12)}'${(profile.heightCm! / 2.54).round() % 12}\"",
                style: RadarType.bodySm.copyWith(
                    fontSize: 9.5, color: RadarTheme.textDim),
              ),
            ),
            _SpecTile(
              label: 'Pref. Foot',
              value: right ? 'RIGHT' : 'LEFT',
              footer: _FootDots(right: right),
            ),
            _SpecTile(
              label: 'Work Rate',
              value: 'H / H',
              footer: Text('Box-to-Box',
                  style: RadarType.bodySm.copyWith(
                      fontSize: 9.5, color: RadarTheme.textDim)),
            ),
          ],
        ),
      ],
    );
  }

  static double _speed(UserProfile p) {
    final seed = p.id.hashCode.abs();
    return 31.5 + (seed % 28) / 10;
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({
    required this.label,
    required this.value,
    required this.footer,
  });

  final String label;
  final String value;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(RadarRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadarCaps(label, size: 8, tracking: 0.6),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: RadarType.heading(
                17,
                weight: FontWeight.w600,
                color: const Color(0xFFF0FFEE),
                height: 1.0,
              ),
            ),
          ),
          const Spacer(),
          footer,
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3,
        backgroundColor: RadarTheme.panelHighest,
        valueColor: AlwaysStoppedAnimation(RadarTheme.radar),
      ),
    );
  }
}

class _FootDots extends StatelessWidget {
  const _FootDots({required this.right});
  final bool right;

  @override
  Widget build(BuildContext context) {
    final filled = right ? 4 : 2;
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: i < filled
                    ? RadarTheme.radar
                    : RadarTheme.panelHighest,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// Attribute set shown on the polygon and the pills. Projected from the
/// profile's credibility + rating (the data set has no per-attribute feed),
/// stable per profile so the passport never reshuffles between builds.
class _Attributes {
  const _Attributes(this.pac, this.dri, this.sho, this.pas, this.stm, this.agi);

  final int pac, dri, sho, pas, stm, agi;

  factory _Attributes.of(UserProfile p) {
    final seed = p.id.hashCode.abs();
    final base = p.credibilityScore.clamp(0, 100);
    final rating = p.rating.clamp(0, 5);
    int v(double weight, int spread, int salt) => (base * weight +
            rating * 4 +
            (seed ~/ salt) % spread)
        .clamp(45, 99)
        .round();
    return _Attributes(
      v(0.62, 7, 1),
      v(0.58, 8, 3),
      v(0.50, 9, 5),
      v(0.52, 8, 7),
      v(0.56, 7, 11),
      v(0.54, 9, 13),
    );
  }

  List<int> get values => [pac, dri, sho, pas, stm, agi];
}

class _TacticalPolygon extends StatelessWidget {
  const _TacticalPolygon({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final a = _Attributes.of(profile);
    const labels = ['PAC', 'DRI', 'SHO', 'PAS', 'STM', 'AGI'];
    return RadarPanel(
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.radar, size: 18, color: RadarTheme.cyanDeep),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'HUD TACTICAL POLYGON',
                  style: RadarType.heading(
                    17,
                    weight: FontWeight.w600,
                    color: const Color(0xFFF0FFEE),
                    tracking: 0.6,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: RadarTheme.panelHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: RadarCaps('PRO LEVEL MATCHED',
                    size: 7.5, color: RadarTheme.cyanDeep),
              ),
            ],
          ),
          SizedBox(
            height: 220,
            child: CustomPaint(
              size: const Size(double.infinity, 220),
              painter: _PolygonPainter(values: a.values, labels: labels),
            ),
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: 2.8,
            children: [
              for (var i = 0; i < labels.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: RadarCaps(labels[i], size: 8)),
                      Text(
                        '${a.values[i]}',
                        style: RadarType.metricMd.copyWith(
                          fontSize: 13,
                          height: 1,
                          color: i == 0 || i == 5
                              ? RadarTheme.greenDeep
                              : RadarTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PolygonPainter extends CustomPainter {
  _PolygonPainter({required this.values, required this.labels});

  final List<int> values;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 4);
    final radius = math.min(size.width, size.height) * 0.36;

    Offset point(int i, double scale) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      return center + Offset(math.cos(angle), math.sin(angle)) * radius * scale;
    }

    List<Offset> ring(double scale) =>
        [for (var i = 0; i < 6; i++) point(i, scale)];

    void drawPolygon(List<Offset> pts, Paint paint) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = RadarTheme.textFaint.withValues(alpha: 0.28);
    drawPolygon(ring(1), grid);
    drawPolygon(ring(0.72), grid..color = RadarTheme.textFaint.withValues(alpha: 0.20));
    drawPolygon(ring(0.44), grid..color = RadarTheme.textFaint.withValues(alpha: 0.14));

    final spoke = Paint()
      ..strokeWidth = 1
      ..color = RadarTheme.textFaint.withValues(alpha: 0.22);
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(center, point(i, 1), spoke);
    }

    final scaled = <Offset>[
      for (var i = 0; i < 6; i++) point(i, values[i] / 100),
    ];
    drawPolygon(
      scaled,
      Paint()..color = RadarTheme.radar.withValues(alpha: 0.16),
    );
    drawPolygon(
      scaled,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = RadarTheme.radar,
    );
    final knot = Paint()..color = RadarTheme.radar;
    for (final p in scaled) {
      canvas.drawCircle(p, 3, knot);
    }

    for (var i = 0; i < 6; i++) {
      final labelPos = point(i, 1.22);
      final tp = TextPainter(
        text: TextSpan(
          text: '${labels[i]} ${values[i]}',
          style: TextStyle(
            fontFamily: RadarFonts.label,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: i == 0 || i == 5
                ? RadarTheme.greenDeep
                : RadarTheme.textPrimary,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        labelPos - Offset(tp.width / 2, tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonPainter old) =>
      old.values != values || old.labels != labels;
}

class _BroadcastNode extends StatelessWidget {
  const _BroadcastNode({
    required this.profile,
    required this.event,
    required this.bounty,
    required this.onMap,
    required this.onSchedule,
    required this.onShare,
    this.onEvent,
  });

  final UserProfile profile;
  final RadarEvent? event;
  final StreamBounty? bounty;
  final VoidCallback onMap;
  final VoidCallback onSchedule;
  final VoidCallback onShare;
  final VoidCallback? onEvent;

  @override
  Widget build(BuildContext context) {
    final live = event?.isLive ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (live) const LiveDot(size: 7, animate: false),
            if (live) const SizedBox(width: 5),
            RadarCaps(
              'Live Radar Stream Node',
              size: 9.5,
              color: RadarTheme.textPrimary,
              tracking: 0.9,
            ),
            const Spacer(),
            RadarCaps(
              live ? 'SCOUT TRANSMISSION ON' : 'TRANSMISSION STANDBY',
              size: 8,
              color: RadarTheme.goldBright,
            ),
          ],
        ),
        const SizedBox(height: 8),
        RadarPanel(
          padding: const EdgeInsets.all(14),
          color: RadarTheme.panelHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: RadarTheme.radar.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: RadarTheme.radar.withValues(alpha: 0.25),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LiveDot(size: 5, animate: false),
                        const SizedBox(width: 4),
                        Text(
                          live
                              ? 'BROADCAST ACTIVE • ${event!.attendingCount} SCOUTS'
                              : 'NEXT MATCH • ${event?.attendingCount ?? 0} SCOUTS',
                          style: RadarType.capsTight.copyWith(
                            fontSize: 8,
                            color: RadarTheme.radar,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.sensors, size: 14, color: RadarTheme.radar),
                  const SizedBox(width: 3),
                  RadarCaps(
                    'CH-04 ${(profile.city ?? 'PITCH').toUpperCase()}',
                    size: 7.5,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (event?.title ?? 'No match scheduled yet').toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RadarType.heading(
                  21,
                  weight: FontWeight.w700,
                  color: const Color(0xFFF0FFEE),
                  tracking: 0.5,
                  height: 1.05,
                ),
              ),
              if (event != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${event!.hostName} • ${event!.areaName ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.bodySm.copyWith(
                    fontSize: 11,
                    color: RadarTheme.cyanDeep,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Kickoff Schedule',
                value: event == null
                    ? 'Not scheduled'
                    : '${DateFormat('EEE, MMM d').format(event!.startsAt)} • ${DateFormat('HH:mm').format(event!.startsAt)}',
                accent: RadarTheme.cyanDeep,
                onTap: onEvent,
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.pin_drop_outlined,
                label: 'Pitch Coordinate',
                value: event == null
                    ? 'Drop a GPS pin to publish a pitch'
                    : '${event!.safeLocationLabel()} (GPS ${event!.precision == GeoPrecision.exact ? 'Verified' : 'Approximate'})',
                accent: RadarTheme.radar,
                onTap: onMap,
              ),
              if (bounty != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: RadarTheme.panelLowest.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(RadarRadius.card),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: RadarTheme.gold.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Text('π',
                            style: RadarType.caps.copyWith(
                                fontSize: 12,
                                color: RadarTheme.goldBright)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RadarCaps(
                              'Active Pi Bounty • ${bounty!.posterName}',
                              size: 8,
                              color: RadarTheme.goldBright,
                            ),
                            Text(
                              bounty!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RadarType.bodySm.copyWith(
                                fontSize: 10,
                                color: RadarTheme.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('+${fmtPi(bounty!.amountPi)} π',
                              style: RadarType.metricMd.copyWith(
                                fontSize: 13,
                                height: 1,
                                color: RadarTheme.goldBright,
                              )),
                          RadarCaps('ESCROW HELD',
                              size: 7, color: RadarTheme.textFaint),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              RadarPrimaryButton(
                label: 'Schedule & broadcast next match',
                icon: Icons.cell_tower,
                height: 48,
                onPressed: onSchedule,
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: _SubAction(
                      icon: Icons.edit_location_alt_outlined,
                      label: 'Drop GPS Pin',
                      onTap: onMap,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _SubAction(
                      icon: Icons.share,
                      label: 'Share Reel Link',
                      onTap: onShare,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: RadarTheme.panelLowest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(RadarRadius.card),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadarCaps(label, size: 8),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RadarType.bodySm.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: RadarTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 15, color: RadarTheme.textFaint),
          ],
        ),
      ),
    );
  }
}

class _SubAction extends StatelessWidget {
  const _SubAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(RadarRadius.card),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: RadarTheme.cyanDeep),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RadarType.bodySm.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: RadarTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedReels extends StatelessWidget {
  const _VerifiedReels({required this.reels, required this.onSeeAll});

  final List<FeedPost> reels;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 16, color: RadarTheme.radar),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'VERIFIED MATCH REELS',
                style: RadarType.heading(
                  17,
                  weight: FontWeight.w600,
                  color: const Color(0xFFF0FFEE),
                  tracking: 0.6,
                ),
              ),
            ),
            GestureDetector(
              onTap: onSeeAll,
              child: RadarCaps('SEE ALL (${reels.length})',
                  size: 8, color: RadarTheme.cyanDeep),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (reels.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            width: double.infinity,
            decoration: BoxDecoration(
              color: RadarTheme.panel,
              borderRadius: BorderRadius.circular(RadarRadius.sheet),
            ),
            child: Text(
              'No reels published yet — post a highlight to appear here.',
              textAlign: TextAlign.center,
              style: RadarType.bodySm.copyWith(color: RadarTheme.textDim),
            ),
          )
        else
          SizedBox(
            height: 236,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _ReelCard(post: reels[i]),
            ),
          ),
      ],
    );
  }
}

class _ReelCard extends StatelessWidget {
  const _ReelCard({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final seed = post.id.hashCode.abs();
    return SizedBox(
      width: 232,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadarRadius.sheet),
        child: ColoredBox(
          color: RadarTheme.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PostMediaSurface(post: post),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: RadarTheme.panelLowest.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.play_arrow,
                                size: 11, color: RadarTheme.radar),
                            const SizedBox(width: 2),
                            Text(
                              '${(seed % 40) + 4}k views',
                              style: RadarType.capsTight.copyWith(
                                  fontSize: 7.5,
                                  color: RadarTheme.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: RadarTheme.radar,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          post.kind.label.toUpperCase(),
                          style: RadarType.capsTight.copyWith(
                              fontSize: 7, color: RadarTheme.onAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.body.split('\n').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: RadarTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      post.areaName ?? post.mediaPlatform ?? 'Match reel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                          fontSize: 10, color: RadarTheme.textDim),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: RadarTheme.panelHigh,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: RadarCaps('${(seed % 30) + 6} SCOUT SAVES',
                                size: 7, color: RadarTheme.greenDeep),
                          ),
                          RadarCaps(
                            post.mediaDurationSeconds == null
                                ? '0:${(15 + seed % 40).toString().padLeft(2, '0')}'
                                : '${post.mediaDurationSeconds! ~/ 60}:${(post.mediaDurationSeconds! % 60).toString().padLeft(2, '0')}',
                            size: 7,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassportFooter extends StatelessWidget {
  const _PassportFooter({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final code = '#RAD-${(profile.id.hashCode.abs() % 9000 + 1000)}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelLowest,
        borderRadius: BorderRadius.circular(RadarRadius.card),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: RadarTheme.panelHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.security, size: 18, color: RadarTheme.radar),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadarCaps(
                  'Cryptographic Grassroots Passport $code',
                  size: 8.5,
                  color: RadarTheme.radar,
                  tracking: 0.7,
                ),
                const SizedBox(height: 2),
                Text(
                  'GPS match telemetry certified on Pi Network Ledger.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.bodySm.copyWith(
                      fontSize: 10, color: RadarTheme.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 21;
    final cell = size.width / cells;
    final paint = Paint()..color = RadarTheme.textPrimary;
    final rng = math.Random(seed);
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        final finder = (x < 7 && y < 7) ||
            (x > cells - 8 && y < 7) ||
            (x < 7 && y > cells - 8);
        final on = finder ? _finderOn(x, y, cells) : rng.nextBool();
        if (on) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  bool _finderOn(int x, int y, int cells) {
    final lx = x > cells - 8 ? cells - 1 - x : x;
    final ly = y > cells - 8 ? cells - 1 - y : y;
    if (lx == 0 || lx == 6 || ly == 0 || ly == 6) return true;
    return lx >= 2 && lx <= 4 && ly >= 2 && ly <= 4;
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.seed != seed;
}
