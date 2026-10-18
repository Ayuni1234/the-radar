import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'design/radar_design.dart';
import 'profile_hub_screen.dart';
import 'radar_theme.dart';
import 'radar_top_bar.dart';

/// Review — the uploaded "Scout Review Room" design.
///
/// The scout side of the escrow: raw footage HUD, proof checklist, footage
/// rating, Pi release and shortlist. It is the final gate of the four-step
/// operator flow (check-in → record → upload → request payment).
class ReviewRoomScreen extends ConsumerWidget {
  const ReviewRoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bounties =
        ref.watch(streamBountiesProvider).value ?? const <StreamBounty>[];
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];
    final session = ref.watch(sessionProvider);

    StreamBounty? target;
    for (final b in bounties) {
      if (b.status == 'live' || b.status == 'accepted') {
        target = b;
        break;
      }
    }
    target ??= bounties.where((b) => b.isFunded).isEmpty
        ? null
        : bounties.where((b) => b.isFunded).first;

    UserProfile? poster;
    for (final p in profiles) {
      if (p.id == session?.profileId) {
        poster = p;
        break;
      }
    }

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: Column(
        children: [
          RadarTopBar(
            onAvatarTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileHubScreen()),
            ),
          ),
          Expanded(
            child: target == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'No footage is waiting for review.\nClaim a bounty and '
                        'upload the tape to open a review room.',
                        textAlign: TextAlign.center,
                        style: RadarType.bodyMd
                            .copyWith(color: RadarTheme.textDim, height: 1.6),
                      ),
                    ),
                  )
                : _ReviewBody(
                    bounty: target,
                    viewerName: poster?.bestName ??
                        session?.displayName ??
                        session?.username ??
                        'Scout',
                    viewerClub: poster?.clubAffiliation,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBody extends ConsumerStatefulWidget {
  const _ReviewBody({
    required this.bounty,
    required this.viewerName,
    this.viewerClub,
  });

  final StreamBounty bounty;
  final String viewerName;
  final String? viewerClub;

  @override
  ConsumerState<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends ConsumerState<_ReviewBody> {
  bool _playing = false;
  bool _released = false;
  bool _shortlisted = false;
  int _rating = 5;
  double _scrub = 0.762;
  int _moment = 2;
  bool _busy = false;
  late final TextEditingController _notes = TextEditingController(
    text: '"Mobile winger with elite acceleration. High-level hip rotation '
        'in 1v1 duels; the operator tracked every touch cleanly. Cleared for '
        'a tier-1 academy trial invitation."',
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  StreamBounty get b => widget.bounty;

  @override
  Widget build(BuildContext context) {
    final progress = _released ? 1.0 : (_scrub.clamp(0.0, 1.0));
    final minutes = (b.durationMinutes * progress).floor();
    final stamp =
        '${minutes.toString().padLeft(2, '0')}:${((progress * 60) % 60).floor().toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
      children: [
        _MissionHeader(bounty: b),
        const SizedBox(height: 12),
        _PlayerViewport(
          bounty: b,
          playing: _playing,
          progress: progress,
          stamp: stamp,
          onPlay: () => setState(() => _playing = !_playing),
        ),
        const SizedBox(height: 12),
        _Scrubber(
          progress: progress,
          totalMinutes: b.durationMinutes,
          moment: _moment,
          onMoment: (i) => setState(() {
            _moment = i;
            _scrub = (0.30 + i * 0.16).clamp(0.0, 0.96);
          }),
          onScrub: (v) => setState(() => _scrub = v),
        ),
        const SizedBox(height: 12),
        _ProofChecklist(bounty: b),
        const SizedBox(height: 12),
        _EscrowRelease(
          bounty: b,
          released: _released,
          busy: _busy,
          rating: _rating,
          onRating: (v) => setState(() => _rating = v),
          onRelease: _release,
          shortlisted: _shortlisted,
          onShortlist: () => setState(() => _shortlisted = !_shortlisted),
        ),
        const SizedBox(height: 12),
        _NotesCard(
          controller: _notes,
          reviewer: widget.viewerName,
          club: widget.viewerClub,
        ),
      ],
    );
  }

  Future<void> _release() async {
    if (_released || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RadarTheme.panel,
        title: Text('Release ${fmtPi(b.amountPi)} π?',
            style: RadarType.heading(20,
                weight: FontWeight.w700, color: RadarTheme.textPrimary)),
        content: Text(
          'This releases the escrow to ${b.streamerName ?? 'the camera operator'} '
          'and closes the bounty.',
          style: RadarType.bodySm.copyWith(color: RadarTheme.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: RadarTheme.gold,
              foregroundColor: const Color(0xFF442B00),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Release & pay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final (ok, message) =
        await ref.read(streamBountiesProvider.notifier).releaseEscrow(b.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _released = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHighest : RadarTheme.alert,
      content: Text(message,
          style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary)),
    ));
  }
}

class _MissionHeader extends StatelessWidget {
  const _MissionHeader({required this.bounty});

  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    return RadarPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: RadarCaps(
                    'BOUNTY #${bounty.id.replaceAll('demo-bounty-', 'B-').toUpperCase()}',
                    size: 8,
                    color: RadarTheme.cyanDeep,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const LiveDot(size: 6, animate: false),
              const SizedBox(width: 4),
              RadarCaps('TELEMETRY SYNCED',
                  size: 8, color: RadarTheme.radar),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: RadarTheme.panelHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: RadarCaps('ESCROW LOCKED',
                    size: 7.5, color: RadarTheme.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bounty.title.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RadarType.heading(
              23,
              weight: FontWeight.w700,
              color: RadarTheme.textPrimary,
              tracking: 0.5,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${bounty.areaName}${bounty.venueName != null ? ' • ${bounty.venueName}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RadarType.bodySm.copyWith(
              fontSize: 10.5,
              color: RadarTheme.textDim,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: RadarTheme.panelHigh,
              borderRadius: BorderRadius.circular(RadarRadius.card),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.videocam_outlined,
                      size: 17, color: RadarTheme.cyanDeep),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '@${(bounty.streamerName ?? bounty.posterName).replaceAll(' ', '_').toLowerCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RadarType.bodySm.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFF0FFEE),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: RadarTheme.gold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: RadarCaps('PIONEER PRO',
                                size: 6.5, color: RadarTheme.goldBright),
                          ),
                        ],
                      ),
                      Text(
                        '⭐ 4.98 Rating • ${bounty.durationMinutes} min verified',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.bodySm.copyWith(
                          fontSize: 9.5,
                          color: RadarTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      RadarCaps('CAMERA HARDWARE', size: 7),
                      Text(
                        'Pi Cam / 60fps',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.metricMd.copyWith(
                          fontSize: 11,
                          color: RadarTheme.textPrimary,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerViewport extends StatelessWidget {
  const _PlayerViewport({
    required this.bounty,
    required this.playing,
    required this.progress,
    required this.stamp,
    required this.onPlay,
  });

  final StreamBounty bounty;
  final bool playing;
  final double progress;
  final String stamp;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(RadarRadius.sheet),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: RadarTheme.panelLowest,
              child: CustomPaint(painter: TacticalGridPainter(spacing: 26)),
            ),
            // Floodlit pitch suggestion.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.1, -0.2),
                  radius: 1.05,
                  colors: [
                    RadarTheme.radar.withValues(alpha: 0.18),
                    RadarTheme.panelLowest,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      RadarTheme.panelLowest.withValues(alpha: 0),
                      RadarTheme.panelLowest.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Row(
                children: [
                  _HudPill(
                    text: 'RAW UNCUT 1080p 60fps',
                    color: RadarTheme.radar,
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF93000A),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB4AB),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text('REC $stamp',
                            style: RadarType.capsTight.copyWith(
                                fontSize: 7,
                                color: const Color(0xFFFFDAD6))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _HudPill(
                text:
                    'LAT ${bounty.latitude?.toStringAsFixed(4) ?? '51.5458'} • LON ${bounty.longitude?.toStringAsFixed(4) ?? '-0.0271'}',
                color: RadarTheme.cyanDeep,
              ),
            ),
            // Target reticle.
            Align(
              alignment: const Alignment(-0.22, -0.18),
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            color: RadarTheme.info.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: RadarTheme.info.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: RadarTheme.info.withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Text('#10',
                              style: RadarType.heading(16,
                                  weight: FontWeight.w600,
                                  color: RadarTheme.cyanDeep)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: RadarTheme.panelLowest.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadarCaps('TARGET', size: 7, color: RadarTheme.cyanDeep),
                          const SizedBox(width: 3),
                          Text('31.8 km/h',
                              style: RadarType.metricMd.copyWith(
                                  fontSize: 10,
                                  height: 1,
                                  color: RadarTheme.radar)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: onPlay,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHighest.withValues(alpha: 0.82),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: RadarTheme.radar.withValues(alpha: 0.3),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: RadarTheme.radar,
                    size: 26,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 7,
              child: Row(
                children: [
                  Icon(Icons.replay_10,
                      size: 17, color: RadarTheme.textPrimary),
                  const SizedBox(width: 6),
                  Text(stamp,
                      style: RadarType.metricMd.copyWith(
                          fontSize: 11, color: RadarTheme.radar)),
                  Text(' / ${bounty.durationMinutes}:00',
                      style: RadarType.bodySm.copyWith(
                          fontSize: 9, color: RadarTheme.textDim)),
                  const Spacer(),
                  Icon(Icons.grid_view, size: 16, color: RadarTheme.textDim),
                  const SizedBox(width: 8),
                  Icon(Icons.fullscreen, size: 17, color: RadarTheme.textDim),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudPill extends StatelessWidget {
  const _HudPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: RadarTheme.panelLowest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: RadarType.capsTight.copyWith(fontSize: 7, color: color),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.progress,
    required this.totalMinutes,
    required this.moment,
    required this.onMoment,
    required this.onScrub,
  });

  final double progress;
  final int totalMinutes;
  final int moment;
  final ValueChanged<int> onMoment;
  final ValueChanged<double> onScrub;

  @override
  Widget build(BuildContext context) {
    const moments = [
      ("14'", 'Goal (solo dribble)'),
      ("22'", 'Explosive transition'),
      ("31'", 'Key assist (cross)'),
      ("41'", 'Foul drawn (D-box)'),
    ];
    return RadarPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RadarCaps('Key Moment Milestones',
                    size: 8, color: RadarTheme.textDim, tracking: 0.6),
              ),
              RadarCaps('TAP TO JUMP', size: 7, color: RadarTheme.cyanDeep),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(builder: (context, constraints) {
            return GestureDetector(
              onTapDown: (d) => onScrub(
                  (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0)),
              onHorizontalDragUpdate: (d) => onScrub(
                  (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0)),
              child: Container(
                height: 9,
                decoration: BoxDecoration(
                  color: RadarTheme.panelHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: FractionallySizedBox(
                  widthFactor: progress.clamp(0.02, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        RadarTheme.info,
                        RadarTheme.radar,
                      ]),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (var i = 0; i < moments.length; i++)
                GestureDetector(
                  onTap: () => onMoment(i),
                  child: Container(
                    width: 154,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: i == moment
                          ? RadarTheme.panelHighest
                          : RadarTheme.panelHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Text(
                          moments[i].$1,
                          style: RadarType.heading(
                            14,
                            weight: FontWeight.w600,
                            color: i == moment
                                ? RadarTheme.radar
                                : RadarTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            moments[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RadarType.bodySm.copyWith(
                              fontSize: 9,
                              color: RadarTheme.textDim,
                            ),
                          ),
                        ),
                        Icon(
                          i == moment
                              ? Icons.play_circle_outline
                              : Icons.check_circle_outline,
                          size: 13,
                          color: i == moment
                              ? RadarTheme.radar
                              : RadarTheme.textFaint,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProofChecklist extends StatelessWidget {
  const _ProofChecklist({required this.bounty});

  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, String)>[
      (
        'GPS timestamp & location match',
        '${bounty.venueName ?? bounty.areaName} • GPS verified',
        'MATCHED',
      ),
      (
        'Unedited raw footage verified',
        'Continuous file stream, 0 split cuts or speed edits',
        'CLEAN',
      ),
      (
        'Target player visible in 92% of clips',
        'AI bounding-box model identifies the tracked player',
        '92.4%',
      ),
      (
        'Audio & pitch atmosphere recorded',
        'Dual-mic field audio with referee whistles',
        'SYNCED',
      ),
    ];
    return RadarPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 19, color: RadarTheme.radar),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'PROOF & TELEMETRY VERIFICATION',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.heading(
                    16,
                    weight: FontWeight.w600,
                    color: RadarTheme.textPrimary,
                    tracking: 0.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: RadarTheme.panelHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: RadarCaps('4/4 PASS',
                    size: 7.5, color: RadarTheme.greenDeep),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (title, sub, tag) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: RadarTheme.panel,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: RadarTheme.radar.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check,
                          size: 11, color: RadarTheme.radar),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RadarType.bodySm.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: RadarTheme.textPrimary,
                            ),
                          ),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RadarType.bodySm.copyWith(
                              fontSize: 9,
                              color: RadarTheme.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    RadarCaps(tag, size: 7, color: RadarTheme.greenDeep),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EscrowRelease extends StatelessWidget {
  const _EscrowRelease({
    required this.bounty,
    required this.released,
    required this.busy,
    required this.rating,
    required this.onRating,
    required this.onRelease,
    required this.shortlisted,
    required this.onShortlist,
  });

  final StreamBounty bounty;
  final bool released;
  final bool busy;
  final int rating;
  final ValueChanged<int> onRating;
  final VoidCallback onRelease;
  final bool shortlisted;
  final VoidCallback onShortlist;

  static const _ratingLabels = [
    '1.0 • Poor Angles',
    '2.0 • Usable but Shaky',
    '3.0 • Solid Community Footage',
    '4.0 • High Standard Scout Quality',
    '5.0 • Broadcast Ready',
  ];

  @override
  Widget build(BuildContext context) {
    return RadarPanel(
      padding: const EdgeInsets.all(14),
      glow: RadarTheme.gold,
      borderColor: RadarTheme.gold.withValues(alpha: 0.25),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadarCaps(
                      'Smart Contract Escrow',
                      size: 8.5,
                      color: RadarTheme.goldBright,
                      tracking: 0.9,
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            fmtPi(bounty.amountPi),
                            style: RadarType.heading(
                              34,
                              weight: FontWeight.w700,
                              color: RadarTheme.goldBright,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('π',
                              style: RadarType.heading(20,
                                  weight: FontWeight.w700,
                                  color: RadarTheme.goldBright)),
                          const SizedBox(width: 6),
                          Text(
                            '~${(bounty.amountPi * 32).toStringAsFixed(0)} USD',
                            style: RadarType.bodySm.copyWith(
                                fontSize: 10, color: RadarTheme.textDim),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: RadarTheme.panelHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(
                      released ? Icons.verified : Icons.lock_outline,
                      size: 14,
                      color: released
                          ? RadarTheme.radar
                          : RadarTheme.goldBright,
                    ),
                    const SizedBox(width: 4),
                    RadarCaps(
                      released ? 'PAID ON PI' : 'LOCKED',
                      size: 7.5,
                      color: released
                          ? RadarTheme.radar
                          : RadarTheme.goldBright,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: RadarTheme.panel,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Rate Footage Quality',
                          style: RadarType.bodySm.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: RadarTheme.textPrimary,
                          )),
                    ),
                    RadarCaps(_ratingLabels[rating - 1],
                        size: 7.5, color: RadarTheme.goldBright),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      GestureDetector(
                        onTap: () => onRating(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 3),
                          child: Icon(
                            i <= rating ? Icons.star : Icons.star_border,
                            size: 25,
                            color: i <= rating
                                ? RadarTheme.goldBright
                                : RadarTheme.textFaint,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: busy ? null : onRelease,
            child: Container(
              height: 50,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: released
                    ? [RadarTheme.radar, RadarTheme.greenDeep]
                    : [RadarTheme.goldBright, RadarTheme.gold]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: (released ? RadarTheme.radar : RadarTheme.gold)
                        .withValues(alpha: 0.35),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(released ? Icons.check_circle : Icons.lock_open,
                      size: 19,
                      color: released
                          ? RadarTheme.onAccent
                          : const Color(0xFF442B00)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      busy
                          ? 'RELEASING…'
                          : released
                              ? '${fmtPi(bounty.amountPi)} π RELEASED SUCCESSFULLY'
                              : 'RELEASE ${fmtPi(bounty.amountPi)} π TO CAMERA OPERATOR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        14,
                        weight: FontWeight.w700,
                        color: released
                            ? RadarTheme.onAccent
                            : const Color(0xFF2B1A00),
                        tracking: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          GestureDetector(
            onTap: onShortlist,
            child: Container(
              height: 44,
              width: double.infinity,
              decoration: BoxDecoration(
                color: RadarTheme.panelHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    shortlisted ? Icons.bookmark_added : Icons.playlist_add,
                    size: 17,
                    color: RadarTheme.radar,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      shortlisted
                          ? 'SAVED TO CLUB SHORTLIST (TIER-A PROSPECT)'
                          : 'SAVE PLAYER TO CLUB SCOUTING SHORTLIST',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        13,
                        weight: FontWeight.w600,
                        color: RadarTheme.radar,
                        tracking: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({
    required this.controller,
    required this.reviewer,
    this.club,
  });

  final TextEditingController controller;
  final String reviewer;
  final String? club;

  @override
  Widget build(BuildContext context) {
    return RadarPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DIRECT SCOUT NOTES',
                  style: RadarType.heading(
                    16,
                    weight: FontWeight.w600,
                    color: RadarTheme.textPrimary,
                    tracking: 0.5,
                  ),
                ),
              ),
              RadarCaps('SAVED TO CLOUD', size: 7.5),
            ],
          ),
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: RadarTheme.panel,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 5,
                  minLines: 3,
                  style: RadarType.bodySm.copyWith(
                    fontSize: 11.5,
                    height: 1.5,
                    color: RadarTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Verified by $reviewer${club != null ? ' ($club)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.bodySm.copyWith(
                          fontSize: 8.5,
                          color: RadarTheme.textDim,
                        ),
                      ),
                    ),
                    RadarCaps('PRO SIGNED', size: 7.5, color: RadarTheme.radar),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
