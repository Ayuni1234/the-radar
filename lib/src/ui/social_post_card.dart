import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/feed_post.dart';
import '../models/radar_event.dart';
import '../state/radar_providers.dart';
import 'radar_theme.dart';

/// A social-feed post card in the "ops-room" visual language: role avatar +
/// handle header, a 16:9 pitch-tinted media hero (live badge / countdown),
/// a custom action bar (location · schedule · live stream), the caption, and
/// a street-map snippet card giving the area physical context.
///
/// Tapping the location action opens the map preview sheet; the schedule
/// action opens the upcoming-sessions sheet; the live button opens the
/// stream/chat overlay for the post's own live pin when one exists.
class SocialPostCard extends ConsumerWidget {
  const SocialPostCard({
    super.key,
    required this.post,
    this.onOpenAuthor,
    this.onDelete,
    this.onOpenMapDeepLink,
  });

  final FeedPost post;
  final VoidCallback? onOpenAuthor;

  /// Shown only to the post's author (owner manage-own-rows rule).
  final VoidCallback? onDelete;

  /// When provided, the Location Pin deep links straight to this spot on
  /// the live Radar map; when null, the in-card map preview sheet opens.
  final VoidCallback? onOpenMapDeepLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];

    // The poster's own nearest live/scheduled session (by author + area).
    RadarEvent? linked;
    RadarEvent? nextScheduled;
    for (final e in events) {
      if (e.hostProfileId == post.authorProfileId) {
        if (e.isLive) {
          linked ??= e;
        } else if (e.startsAt.isAfter(DateTime.now())) {
          if (nextScheduled == null ||
              e.startsAt.isBefore(nextScheduled.startsAt)) {
            nextScheduled = e;
          }
        }
      }
    }
    linked ??= nextScheduled;
    // Final local so the null-check promotes inside the closures below
    // (captured mutable locals lose promotion).
    final linkedEvent = linked;

    return Container(
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RadarTheme.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            post: post,
            onOpenAuthor: onOpenAuthor,
            onDelete: onDelete,
          ),
          _MediaHero(post: post, linkedEvent: linkedEvent),
          _ActionBar(
            post: post,
            linkedEvent: linkedEvent,
            onOpenMap: onOpenMapDeepLink ?? () => _openMapSheet(context),
            onOpenSchedule: () => _openScheduleSheet(context, ref),
            onOpenChat: () => linkedEvent == null
                ? _openScheduleSheet(context, ref)
                : _openLiveSheet(context, linkedEvent),
          ),
          _Caption(post: post, onOpenMap: onOpenMapDeepLink ?? () => _openMapSheet(context)),
        ],
      ),
    );
  }

  Future<void> _openMapSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MapPreviewSheet(
        title: post.areaName ?? 'Training area',
        latitude: post.latitude,
        longitude: post.longitude,
      ),
    );
  }

  Future<void> _openScheduleSheet(BuildContext context, WidgetRef ref) {
    final events = ref.read(radarEventsProvider).value ?? const <RadarEvent>[];
    final upcoming = events
        .where((e) => e.hostProfileId == post.authorProfileId)
        .where((e) => e.startsAt.isAfter(DateTime.now()) || e.isLive)
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleSheet(
        playerName: post.authorName,
        sessions: upcoming,
      ),
    );
  }

  Future<void> _openLiveSheet(BuildContext context, RadarEvent event) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LiveStreamSheet(event: event),
    );
  }
}

// ------------------------------------------------------------------ header

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.post,
    this.onOpenAuthor,
    this.onDelete,
  });

  final FeedPost post;
  final VoidCallback? onOpenAuthor;
  final VoidCallback? onDelete;

  static const _roleIcons = {
    'player': Icons.sports_soccer,
    'scout': Icons.travel_explore,
    'club': Icons.emoji_events,
    'academy': Icons.school,
    'agent': Icons.handshake,
    'parent': Icons.family_restroom,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onOpenAuthor,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    RadarTheme.radar.withValues(alpha: 0.55),
                    RadarTheme.pi.withValues(alpha: 0.55),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: RadarTheme.panel,
                ),
                child: Icon(
                  _roleIcons[post.authorRole] ?? Icons.person,
                  size: 19,
                  color: RadarTheme.radar,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onOpenAuthor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${post.authorName} · '
                              '${post.authorRole[0].toUpperCase()}${post.authorRole.substring(1)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (post.isMinorPoster) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message: 'Posted by a minor — location locked to a '
                              'coarse regional label by database triggers',
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.shield, size: 13, color: RadarTheme.gold),
                            SizedBox(width: 3),
                            Text('Protected',
                                style: TextStyle(
                                    fontSize: 10.5, color: RadarTheme.gold)),
                          ]),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${_ago(post.createdAt)} · ${post.kind.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: RadarTheme.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: post.isMinorPoster
                ? 'Visible inside the safe area only'
                : 'Visible worldwide on the feed',
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: RadarTheme.panelHigh,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: RadarTheme.stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(post.isMinorPoster ? Icons.shield : Icons.public,
                      size: 12,
                      color: post.isMinorPoster
                          ? RadarTheme.gold
                          : RadarTheme.textDim),
                  const SizedBox(width: 4),
                  Text(post.isMinorPoster ? 'Protected' : 'Global',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: post.isMinorPoster
                              ? RadarTheme.gold
                              : RadarTheme.textDim)),
                ],
              ),
            ),
          ),
          if (onDelete != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete post',
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: RadarTheme.textDim),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// -------------------------------------------------------------- media hero

class _MediaHero extends StatelessWidget {
  const _MediaHero({required this.post, this.linkedEvent});

  final FeedPost post;
  final RadarEvent? linkedEvent;

  @override
  Widget build(BuildContext context) {
    final isLive = linkedEvent?.isLive ?? false;
    final upcoming = !isLive &&
        linkedEvent != null &&
        linkedEvent!.startsAt.isAfter(DateTime.now());
    final countdown = upcoming
        ? _countdown(linkedEvent!.startsAt)
        : null;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _PitchCanvas(),
          if (post.hasMedia)
            Positioned(
              left: 12,
              bottom: 12,
              child: _HeroChip(
                icon: Icons.play_circle_fill,
                label: post.mediaPlatform ?? 'Highlight link',
              ),
            ),
          if (isLive)
            Positioned(
              right: 12,
              top: 12,
              child: _LiveBadge(),
            )
          else if (countdown != null)
            Positioned(
              right: 12,
              top: 12,
              child: _HeroChip(
                icon: Icons.schedule,
                label: 'starts in $countdown',
              ),
            ),
        ],
      ),
    );
  }

  String _countdown(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

/// Painted floodlit-pitch backdrop for the media area — pure CustomPainter,
/// no network imagery required (demo-safe, deterministic in tests).
class _PitchCanvas extends StatelessWidget {
  const _PitchCanvas();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _PitchPainter());
  }
}

class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Night grass under floodlight: deep radial falloff.
    final bg = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.55),
        radius: 1.35,
        colors: [
          const Color(0xFF123B2A),
          const Color(0xFF0C241A),
          const Color(0xFF0A0E1A),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Mown-stripe bands, alternating light.
    final stripe = Paint()..color = const Color(0xFF16412E).withValues(alpha: 0.5);
    final band = size.height / 5;
    for (var i = 0; i < 5; i++) {
      if (i.isOdd) {
        canvas.drawRect(
            Rect.fromLTWH(0, i * band, size.width, band), stripe);
      }
    }

    // Distant treeline behind the pitch fence.
    final tree = Paint()
      ..color = const Color(0xFF092018).withValues(alpha: 0.9);
    final treeTop = size.height * 0.16;
    final treePath = Path()..moveTo(0, treeTop);
    var x = 0.0;
    while (x < size.width) {
      final w = size.width * 0.05;
      final h = size.height * (0.05 + ((x * 7) % 3) * 0.012);
      treePath.quadraticBezierTo(
          x + w * 0.5, treeTop - h, x + w, treeTop);
      x += w;
    }
    treePath
      ..lineTo(size.width, treeTop + size.height * 0.05)
      ..lineTo(0, treeTop + size.height * 0.05)
      ..close();
    canvas.drawPath(treePath, tree);

    // Perimeter fence: two rails + mesh posts.
    final fence = Paint()
      ..strokeWidth = 1.2
      ..color = const Color(0xFF9FB3A8).withValues(alpha: 0.30);
    final fenceY = size.height * 0.30;
    canvas.drawLine(Offset(0, fenceY), Offset(size.width, fenceY), fence);
    canvas.drawLine(Offset(0, fenceY + 5), Offset(size.width, fenceY + 5),
        fence..strokeWidth = 0.8);
    final post = Paint()
      ..strokeWidth = 1.6
      ..color = const Color(0xFF9FB3A8).withValues(alpha: 0.38);
    for (var px = 6.0; px < size.width; px += size.width / 11) {
      canvas.drawLine(Offset(px, fenceY - 8), Offset(px, fenceY + 6), post);
    }

    // Floodlight vignette: corners fall into shadow, center stays hot.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(0.1, -0.1),
          radius: 1.25,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.42),
          ],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Center circle + halfway line, thin chalk.
    final chalk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFDDE7DF).withValues(alpha: 0.35);
    final center = Offset(size.width / 2, size.height * 1.35);
    canvas.drawCircle(center, size.height * 0.85, chalk);
    canvas.drawLine(
        Offset(0, size.height * 0.82), Offset(size.width, size.height * 0.82),
        chalk..strokeWidth = 1.1);

    // Sprinting player silhouette — motion-blurred, chalk white.
    _drawPlayer(canvas, size);
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final s = size.height / 9; // unit
    final cx = size.width * 0.34;
    final cy = size.height * 0.60;
    final body = Paint()
      ..color = const Color(0xFFE8F1EC).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s * 0.34;

    final lean = -0.35; // forward sprint lean (radians)

    Path limb(Offset a, Offset b, Offset c) =>
        Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(b.dx, b.dy, c.dx, c.dy);

    // Torso (leaning), head, driving arms, mid-stride legs.
    final shoulder = Offset(cx + math.sin(lean) * s * 0.4, cy - s * 1.55);
    final hip = Offset(cx, cy);
    canvas.drawPath(limb(shoulder, Offset(cx - s * 0.1, cy - s * 0.75), hip),
        body);
    canvas.drawCircle(Offset(cx + s * 0.55, cy - s * 1.95), s * 0.30, body);
    // Arms.
    canvas.drawPath(
        limb(shoulder, Offset(cx + s * 0.9, cy - s * 1.0),
            Offset(cx + s * 1.25, cy - s * 0.5)),
        body);
    canvas.drawPath(
        limb(shoulder, Offset(cx - s * 0.7, cy - s * 0.9),
            Offset(cx - s * 1.1, cy - s * 0.35)),
        body);
    // Legs: one driving forward-up, one extended back.
    canvas.drawPath(
        limb(hip, Offset(cx + s * 0.85, cy + s * 0.55),
            Offset(cx + s * 0.55, cy + s * 1.35)),
        body);
    canvas.drawPath(
        limb(hip, Offset(cx - s * 0.75, cy + s * 0.5),
            Offset(cx - s * 1.35, cy + s * 1.0)),
        body);
    // Ball just ahead of the stride.
    final ball = Paint()..color = const Color(0xFFF3F6FB).withValues(alpha: 0.95);
    canvas.drawCircle(Offset(cx + s * 1.8, cy + s * 1.25), s * 0.26, ball);

    // Motion streaks behind the runner.
    final streak = Paint()
      ..strokeWidth = 1.2
      ..color = const Color(0xFFE8F1EC).withValues(alpha: 0.22);
    for (final dy in [-0.2, 0.35, 0.9]) {
      canvas.drawLine(
        Offset(cx - s * 2.1, cy + s * dy),
        Offset(cx - s * 3.4, cy + s * dy),
        streak,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: RadarTheme.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: RadarTheme.radar),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: RadarTheme.radar,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: RadarTheme.radar.withValues(alpha: 0.4),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                color: RadarTheme.ink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          const Text('LIVE NOW',
              style: TextStyle(
                  color: RadarTheme.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- action bar

/// Three outlined two-line pills, per the reference design:
/// Location Pin · Calendar (next date) · Chat bubble (Live Match Chat).
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.post,
    required this.linkedEvent,
    required this.onOpenMap,
    required this.onOpenSchedule,
    required this.onOpenChat,
  });

  final FeedPost post;
  final RadarEvent? linkedEvent;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    // Local capture: only *private* fields get field promotion, so bind the
    // nullable event once and let flow analysis promote the local below.
    final event = linkedEvent;
    final isLive = event?.isLive ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _ActionPill(
              icon: Icons.location_on_outlined,
              title: 'Location Pin',
              subtitle: post.areaName == null || post.areaName!.isEmpty
                  ? 'Tap to view'
                  : _short(post.areaName!),
              tooltip: post.areaName ?? 'Training location',
              accent: RadarTheme.info,
              iconBadge: const _MapChip(),
              onTap: onOpenMap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionPill(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar',
              subtitle:
                  event == null ? 'No sessions yet' : _when(event),
              tooltip: 'Upcoming training dates & times',
              accent: RadarTheme.gold,
              onTap: onOpenSchedule,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionPill(
              icon: Icons.chat_bubble_outline,
              title: isLive ? 'Live · Chat' : 'Chat bubble',
              subtitle: isLive ? 'Live Match Chat' : 'Open match chat',
              tooltip: isLive
                  ? 'Jump into the live match chat & stream'
                  : 'Next session chat opens at kickoff',
              accent: isLive ? RadarTheme.radar : RadarTheme.textDim,
              live: isLive,
              onTap: onOpenChat,
            ),
          ),
        ],
      ),
    );
  }

  String _short(String area) {
    final spot = area.split(RegExp(r'[—·-]')).first.trim();
    return spot.length > 12 ? '${spot.substring(0, 12)}…' : spot;
  }

  String _when(RadarEvent e) {
    if (e.isLive) return 'Live right now';
    final d = e.startsAt;
    final now = DateTime.now();
    final day = d.day == now.day
        ? 'Today'
        : DateFormat('MMM d').format(d);
    return '$day, ${DateFormat('h:mm a').format(d)}';
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.accent,
    required this.onTap,
    this.iconBadge,
    this.live = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String tooltip;
  final Color accent;
  final Widget? iconBadge;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Tooltip(
      message: tooltip,
      child: Material(
        color: RadarTheme.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: live
                ? RadarTheme.radar.withValues(alpha: 0.6)
                : RadarTheme.stroke,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              children: [
                iconBadge ??
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: live ? RadarTheme.radar : RadarTheme.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return live
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              pill,
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: RadarTheme.radar,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: RadarTheme.radar.withValues(alpha: 0.45),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: RadarTheme.ink,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
              ),
            ],
          )
        : pill;
  }
}

/// Tiny painted map tile used as the Location Pin's badge icon.
class _MapChip extends StatelessWidget {
  const _MapChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: RadarTheme.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: const CustomPaint(painter: _MapChipPainter()),
    );
  }
}

class _MapChipPainter extends CustomPainter {
  const _MapChipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFFEAF0E4));
    // Streets.
    final road = Paint()
      ..strokeWidth = 2.4
      ..color = const Color(0xFFC9D4C0);
    canvas.drawLine(Offset(0, size.height * 0.55),
        Offset(size.width, size.height * 0.4), road);
    canvas.drawLine(Offset(size.width * 0.4, 0),
        Offset(size.width * 0.55, size.height), road);
    // Green pitch corner.
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.55, size.height * 0.55,
          size.width * 0.45, size.height * 0.45),
      Paint()..color = const Color(0xFFBFD8B8),
    );
    // Pin.
    canvas.drawCircle(Offset(size.width * 0.38, size.height * 0.36), 3.4,
        Paint()..color = RadarTheme.alert);
    canvas.drawCircle(
        Offset(size.width * 0.38, size.height * 0.36),
        1.4,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MapChipPainter oldDelegate) => false;
}

// ----------------------------------------------------------------- caption

class _Caption extends StatelessWidget {
  const _Caption({required this.post, required this.onOpenMap});

  final FeedPost post;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.body,
            style: const TextStyle(
                color: RadarTheme.textPrimary, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: GestureDetector(
                  onTap: onOpenMap,
                  child: const Text(
                    'View full location & schedule',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: RadarTheme.info,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: RadarTheme.info,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onTap: onOpenMap,
                  child: _MapLabelChip(label: post.areaName ?? 'Training area'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Light street-map snippet with the area label printed across it — the
/// physical-context card from the reference design.
class _MapLabelChip extends StatelessWidget {
  const _MapLabelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _MapChipPainter()),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF25441F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Street-map backdrop: light paper base, blocks, streets, a pitch block and
/// a pulsing location pin — deterministic, no tile server required.
class _StreetMapPainter extends CustomPainter {
  const _StreetMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Light paper base (matching the reference's light map snippet).
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEAF0E4));

    final block = Paint()..color = const Color(0xFFD8E0D2);
    final road = Paint()
      ..strokeWidth = 3
      ..color = Colors.white
      ..strokeCap = StrokeCap.butt;
    final roadThin = Paint()
      ..strokeWidth = 1.6
      ..color = const Color(0xFFF7FAF5);

    // City blocks.
    for (final r in [
      const Rect.fromLTWH(2, 2, 18, 14),
      const Rect.fromLTWH(24, 2, 16, 10),
      const Rect.fromLTWH(2, 22, 14, 18),
      const Rect.fromLTWH(42, 16, 18, 20),
      const Rect.fromLTWH(20, 30, 16, 30),
    ]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)), block);
    }

    // Streets.
    canvas.drawLine(const Offset(0, 18), Offset(size.width, 18), road);
    canvas.drawLine(const Offset(22, 0), const Offset(22, 64), road);
    canvas.drawLine(const Offset(40, 0), Offset(40, size.height), roadThin);
    canvas.drawLine(const Offset(0, 46), Offset(44, 46), roadThin);

    // Pitch block (the training spot).
    final pitch = RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 2, 16, 10), const Radius.circular(2));
    canvas.drawRRect(pitch, Paint()..color = const Color(0xFFBFD8B8));

    // Pin.
    final pin = Paint()..color = RadarTheme.alert;
    canvas.drawCircle(const Offset(30, 38), 5, pin);
    canvas.drawCircle(const Offset(30, 38), 2,
        Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(30, 38), 9,
        Paint()..color = RadarTheme.alert.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant _StreetMapPainter oldDelegate) => false;
}

// ------------------------------------------------------------ map sheet

class _MapPreviewSheet extends StatelessWidget {
  const _MapPreviewSheet({
    required this.title,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    final hasCoords = latitude != null && longitude != null;
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.location_on, color: RadarTheme.radar, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15.5)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 220,
              child: CustomPaint(painter: _StreetMapPainter()),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasCoords
                ? '${latitude!.toStringAsFixed(4)}°, ${longitude!.toStringAsFixed(4)}° — approximate street-level context'
                : 'Coarse area only — precise coordinates withheld (minor safety).',
            style: const TextStyle(color: RadarTheme.textDim, fontSize: 12),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: RadarTheme.panelHigh,
              foregroundColor: RadarTheme.textPrimary,
            ),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.radar, size: 18),
            label: const Text('Open on the Radar map'),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------- schedule sheet

class _ScheduleSheet extends StatelessWidget {
  const _ScheduleSheet({required this.playerName, required this.sessions});

  final String playerName;
  final List<RadarEvent> sessions;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM · HH:mm');
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.event_available,
                color: RadarTheme.radar, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Upcoming sessions — $playerName',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15.5)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          const SizedBox(height: 10),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No upcoming sessions published yet. Tap the schedule icon '
                'again after the player drops a new pin.',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12.5),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in sessions.take(6))
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RadarTheme.panelHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: e.isLive
                                ? RadarTheme.radar.withValues(alpha: 0.5)
                                : RadarTheme.stroke),
                      ),
                      child: Row(children: [
                        Icon(
                          e.isLive ? Icons.podcasts : Icons.schedule,
                          size: 17,
                          color:
                              e.isLive ? RadarTheme.radar : RadarTheme.textDim,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                '${df.format(e.startsAt)} · ${e.safeLocationLabel()}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: RadarTheme.textDim),
                              ),
                            ],
                          ),
                        ),
                        if (e.isLive)
                          const Text('LIVE',
                              style: TextStyle(
                                  color: RadarTheme.radar,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800)),
                      ]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ live sheet

class _LiveStreamSheet extends StatelessWidget {
  const _LiveStreamSheet({required this.event});

  final RadarEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.radar.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.podcasts, color: RadarTheme.radar, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.isLive
                    ? 'Live — ${event.title}'
                    : 'Match chat — ${event.title}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15.5),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${event.safeLocationLabel()} · '
            '${event.attendingCount}${event.capacity != null ? '/${event.capacity}' : ''} watching',
            style: const TextStyle(color: RadarTheme.textDim, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 170,
              child: const CustomPaint(painter: _PitchPainter()),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.chat_bubble_outline, size: 17),
                label: const Text('Match chat',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.videocam, size: 17),
                label: Text(event.isLive ? 'Enter stream' : 'Notify me',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
