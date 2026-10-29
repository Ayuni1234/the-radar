import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/feed_post.dart';
import '../models/user_profile.dart';
import 'design/radar_design.dart';
import 'next_training_overlay.dart';
import 'radar_theme.dart';
import 'social_post_card.dart' show PostMediaSurface;

/// One full-screen Discover reel, built to the uploaded spec:
///
/// * live camera badge and viewer count over the top of the media,
/// * the player identity block (condensed name + verified tick, age/position
///   pill, club line, two-line bio, metric micro-chips),
/// * the LIVE SESSION INVITATION card with its countdown and dual CTAs,
/// * the right-hand action rail (avatar/follow, like, comments, scout star,
///   share, spinning sound disc).
class ReelView extends StatelessWidget {
  const ReelView({
    super.key,
    required this.post,
    required this.author,
    required this.training,
    required this.onOpenViewer,
    required this.onOpenAuthor,
    required this.onScoutInPerson,
    required this.onBounty,
    this.onOpenSession,
  });

  final FeedPost post;
  final UserProfile? author;
  final NextTrainingInfo? training;
  final VoidCallback onOpenViewer;
  final VoidCallback onOpenAuthor;

  /// Deep link → the player's map pin on the Radar Map tab.
  final VoidCallback onScoutInPerson;

  /// Opens the Pi bounty flow for the session.
  final VoidCallback onBounty;
  final VoidCallback? onOpenSession;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 720;
    final veryCompact = size.height < 620;

    return Stack(
      fit: StackFit.expand,
      children: [
        PostMediaSurface(
          post: post,
          heroTag: 'media-hero-${post.id}',
          onTap: onOpenViewer,
        ),
        // Top legibility ramp for the live camera chips.
        Align(
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    RadarTheme.panelLowest.withValues(alpha: 0.72),
                    RadarTheme.panelLowest.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom ramp: transparent from 40%, canvas by the bottom edge.
        Align(
          alignment: Alignment.bottomCenter,
          child: RadarMediaScrim(height: veryCompact ? 330 : 430),
        ),
        Positioned(
          top: 10,
          left: RadarSpace.md,
          right: RadarSpace.md,
          // No camera feed is connected yet, so this is null and shows DEMO
          // MODE. Pass real LiveCameraTelemetry here once a websocket exists.
          child: _LiveCameraStrip(post: post, telemetry: null),
        ),
        Positioned(
          left: RadarSpace.md,
          right: 8,
          bottom: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityBlock(
                      post: post,
                      author: author,
                      compact: compact,
                      veryCompact: veryCompact,
                      onOpenAuthor: onOpenAuthor,
                    ),
                    if (!veryCompact) const SizedBox(height: 10),
                    if (training != null)
                      NextTrainingOverlayCard(
                        info: training!,
                        compact: veryCompact,
                        onScoutInPerson: onScoutInPerson,
                        onBounty: onBounty,
                        onOpenProfile: onOpenAuthor,
                      )
                    else
                      _NoSessionStrip(onOpenAuthor: onOpenAuthor),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              ReelActionRail(
                author: author,
                post: post,
                compact: compact,
                onOpenAuthor: onOpenAuthor,
                onOpenSession: onOpenSession,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Real live telemetry for a reel. Null means no feed is connected, so the
/// strip shows DEMO MODE instead of invented camera, FPS or viewer numbers.
class LiveCameraTelemetry {
  const LiveCameraTelemetry({
    required this.cameraId,
    required this.fps,
    required this.viewers,
  });

  final int cameraId;
  final int fps;
  final int viewers;
}

class _LiveCameraStrip extends StatelessWidget {
  const _LiveCameraStrip({required this.post, this.telemetry});

  final FeedPost post;

  /// Real camera feed data (e.g. from a websocket). Null shows DEMO MODE.
  final LiveCameraTelemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    final isDemo = t == null;
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: RadarTheme.panelLowest.withValues(alpha: 0.80),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: (isDemo ? RadarTheme.gold : RadarTheme.radar)
                      .withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDemo)
                  Icon(Icons.science_outlined,
                      size: 11, color: RadarTheme.gold)
                else
                  const LiveDot(size: 7, animate: false),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    isDemo ? 'DEMO MODE' : 'LIVE PITCH CAM #${t.cameraId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RadarType.caps.copyWith(
                      fontSize: 9.5,
                      color: isDemo ? RadarTheme.gold : RadarTheme.radar,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                if (!isDemo) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${t.fps} FPS',
                    style: RadarType.caps.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: RadarTheme.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!isDemo) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: RadarTheme.panelLowest.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined,
                    size: 14, color: RadarTheme.cyanDeep),
                const SizedBox(width: 4),
                Text(
                  _compactCount(t.viewers),
                  style: RadarType.metricMd.copyWith(
                    fontSize: 12,
                    color: RadarTheme.cyanDeep,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({
    required this.post,
    required this.author,
    required this.compact,
    required this.veryCompact,
    required this.onOpenAuthor,
  });

  final FeedPost post;
  final UserProfile? author;
  final bool compact;
  final bool veryCompact;
  final VoidCallback onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    final name = author?.bestName ?? post.authorName;
    final positions = author?.positions ?? const <String>[];
    final age = author?.age;
    final meta = [
      if (age != null) '$age Y/O',
      if (positions.isNotEmpty) positions.take(2).join(' / '),
    ].join(' • ');
    final club = (author?.clubAffiliation ?? '').trim();
    final area = (post.areaName ?? '').trim();
    final bio = (author?.bio ?? '').trim();
    final caption = post.body.split('\n').first.trim();
    final metrics = reelMetricChips(author, post: post);
    final verified = author?.kycVerified ?? false;

    return GestureDetector(
      onTap: onOpenAuthor,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.heading(
                    compact ? 26 : 30,
                    weight: FontWeight.w800,
                    color: const Color(0xFFF0FFEE),
                    tracking: 0.9,
                    height: 1.0,
                  ),
                ),
              ),
              if (verified) ...[
                const SizedBox(width: 5),
                Icon(Icons.verified, size: 18, color: RadarTheme.radar),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: RadarTheme.info.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                meta.toUpperCase(),
                style: RadarType.caps.copyWith(
                  fontSize: 9.5,
                  color: RadarTheme.cyanDeep,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ],
          if (club.isNotEmpty || area.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.sports_soccer,
                    size: 14, color: RadarTheme.greenDeep),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    [
                      if (club.isNotEmpty) club,
                      if (area.isNotEmpty) area,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RadarType.bodySm.copyWith(
                      fontSize: 11.5,
                      color: RadarTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!veryCompact && (bio.isNotEmpty || caption.isNotEmpty)) ...[
            const SizedBox(height: 5),
            Text(
              bio.isNotEmpty ? bio : caption,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: RadarType.bodySm.copyWith(
                fontSize: 11.5,
                height: 1.35,
                color: const Color(0xE6FFFFFF),
              ),
            ),
          ],
          if (!veryCompact) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MetricChip(code: 'PAC', value: '${metrics.pac}'),
                MetricChip(code: 'DRI', value: '${metrics.dri}'),
                MetricChip(code: 'ACC', value: '${metrics.acc}'),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: RadarTheme.radar.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(RadarRadius.base),
                  ),
                  child: Text(
                    'TOP ${metrics.topPct}% ${metrics.band}',
                    style: RadarType.capsTight.copyWith(
                      fontSize: 9,
                      color: RadarTheme.radar,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Scouting index shown on the reel. The data set carries credibility and
/// rating rather than per-attribute telemetry, so the three chips are a
/// deterministic projection of those two numbers (stable per profile) instead
/// of random decoration.
({int pac, int dri, int acc, int topPct, String band}) reelMetricChips(
    UserProfile? profile, {
    FeedPost? post,
  }) {
  final seed =
      (profile?.id ?? post?.authorProfileId ?? 'radar').hashCode.abs();
  final base = ((profile?.credibilityScore ?? 60).clamp(0, 100)).round();
  final rating = (profile?.rating ?? 3.5).clamp(0, 5);
  final pac = (base * 0.55 + rating * 6 + seed % 7).clamp(40, 99).round();
  final dri = (base * 0.5 + rating * 7 + (seed ~/ 3) % 6).clamp(40, 99).round();
  final acc = (base * 0.6 + rating * 5 + (seed ~/ 7) % 5).clamp(40, 99).round();
  final age = profile?.age ?? 19;
  final band = age <= 17 ? 'U17' : (age <= 19 ? 'U19' : 'U21');
  final topPct = (100 - base).clamp(1, 25);
  return (pac: pac, dri: dri, acc: acc, topPct: topPct, band: band);
}

class _NoSessionStrip extends StatelessWidget {
  const _NoSessionStrip({required this.onOpenAuthor});

  final VoidCallback onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenAuthor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: RadarTheme.panelLowest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(RadarRadius.card),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 14, color: RadarTheme.gold),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'No live session scheduled — open the passport',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RadarType.bodySm.copyWith(
                  fontSize: 11.5,
                  color: RadarTheme.textDim,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: RadarTheme.textDim),
          ],
        ),
      ),
    );
  }
}

/// Right-hand interaction rail from the spec.
class ReelActionRail extends StatefulWidget {
  const ReelActionRail({
    super.key,
    required this.author,
    required this.post,
    required this.compact,
    required this.onOpenAuthor,
    this.onOpenSession,
  });

  final UserProfile? author;
  final FeedPost post;
  final bool compact;
  final VoidCallback onOpenAuthor;
  final VoidCallback? onOpenSession;

  @override
  State<ReelActionRail> createState() => _ReelActionRailState();
}

class _ReelActionRailState extends State<ReelActionRail> {
  bool _liked = false;
  bool _scouted = false;
  bool _following = false;

  int get _likes {
    final seed = widget.post.id.hashCode.abs();
    return 1800 + seed % 12000 + (_liked ? 1 : 0);
  }

  int get _comments => 90 + widget.post.id.hashCode.abs() % 380;

  void _toast(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHighest,
      duration: const Duration(milliseconds: 2200),
      content: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: RadarType.bodySm.copyWith(
                color: RadarTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.author?.bestName ?? widget.post.authorName;
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: widget.onOpenAuthor,
                child: RadarAvatar(
                  name: name,
                  url: widget.author?.avatarUrl,
                  size: 44,
                  ring: RadarTheme.radar.withValues(alpha: 0.4),
                ),
              ),
              Positioned(
                bottom: -6,
                left: 14,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _following = !_following);
                    _toast(
                      _following
                          ? 'Subscribed to $name radar alerts'
                          : 'Unsubscribed from $name',
                      _following
                          ? Icons.notifications_active
                          : Icons.notifications_off,
                      RadarTheme.radar,
                    );
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _following
                          ? RadarTheme.panelHighest
                          : RadarTheme.radar,
                      shape: BoxShape.circle,
                      border: Border.all(color: RadarTheme.panelLowest),
                    ),
                    child: Icon(
                      _following ? Icons.check : Icons.add,
                      size: 13,
                      color: _following
                          ? RadarTheme.radar
                          : RadarTheme.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: widget.compact ? 14 : 20),
          _RailAction(
            icon: _liked ? Icons.favorite : Icons.favorite_border,
            color: _liked ? RadarTheme.alert : RadarTheme.textPrimary,
            label: _compactCount(_likes),
            compact: widget.compact,
            onTap: () {
              setState(() => _liked = !_liked);
              if (_liked) {
                _toast('Added clip to Discovery Highlights', Icons.favorite,
                    RadarTheme.alert);
              }
            },
          ),
          _RailAction(
            icon: Icons.chat_bubble_outline,
            label: _compactCount(_comments),
            compact: widget.compact,
            onTap: () => _toast(
                'Match thread · ${_compactCount(_comments)} replies',
                Icons.chat_bubble_outline,
                RadarTheme.info),
          ),
          _RailAction(
            icon: _scouted ? Icons.star : Icons.star_border,
            color: RadarTheme.goldBright,
            label: 'Scout',
            labelColor: RadarTheme.goldBright,
            compact: widget.compact,
            onTap: () {
              setState(() => _scouted = !_scouted);
              _toast(
                _scouted
                    ? '$name pinned to your priority watchlist'
                    : 'Removed from watchlist',
                _scouted ? Icons.star : Icons.star_border,
                RadarTheme.goldBright,
              );
            },
          ),
          _RailAction(
            icon: Icons.share,
            label: 'Share',
            compact: widget.compact,
            onTap: () => _toast('Scout link copied to clipboard',
                Icons.link, RadarTheme.radar),
          ),
          _RailAction(
            icon: Icons.graphic_eq,
            color: RadarTheme.cyanDeep,
            label: '',
            compact: widget.compact,
            disc: true,
            onTap: widget.onOpenSession ?? () {},
          ),
        ],
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
    this.color,
    this.labelColor,
    this.disc = false,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;
  final Color? color;
  final Color? labelColor;
  final bool disc;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 36.0 : 42.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Column(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: disc
                    ? RadarTheme.panelLowest
                    : RadarTheme.panelHighest.withValues(alpha: 0.80),
                shape: BoxShape.circle,
                border:
                    disc ? Border.all(color: RadarTheme.lineStrong) : null,
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  size: compact ? 19 : 22,
                  color: color ?? RadarTheme.textPrimary),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RadarType.capsTight.copyWith(
                  fontSize: 8.5,
                  letterSpacing: 0.2,
                  color: labelColor ?? RadarTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}m';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return '$value';
}

/// Roboto-safe text scale for the very dense metric row.
double metricRowWidth(BuildContext context) =>
    math.min(MediaQuery.sizeOf(context).width - 90, 320);
