import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/enums.dart';
import '../models/feed_post.dart' show distanceKm;
import '../models/radar_event.dart';
import '../state/auth_controller.dart';
import 'design/radar_design.dart';
import 'live_countdown.dart';
import 'radar_theme.dart';

/// Data for the LIVE SESSION INVITATION card on the Discover reel — the
/// uploaded design's hero overlay (`LIVE SESSION INVITATION`, countdown,
/// pitch + distance + scout attendance, dual CTAs).
class NextTrainingInfo {
  const NextTrainingInfo({
    required this.event,
    this.playerName,
    this.pitchLabel,
  });

  final RadarEvent event;

  /// Display name of the hosting player (falls back to [RadarEvent.hostName]).
  final String? playerName;

  /// Pitch label override (falls back to the event's safe location label).
  final String? pitchLabel;

  String get name => (playerName?.isNotEmpty ?? false)
      ? playerName!
      : (event.hostName.isNotEmpty ? event.hostName : 'Player');

  String get pitch => pitchLabel ??
      (event.venueName != null && event.venueName!.isNotEmpty
          ? event.venueName!
          : event.safeLocationLabel());

  String get startTimeLabel => DateFormat('h:mm a').format(event.startsAt);
}

/// Resolve the viewer's next upcoming (or currently live) training session
/// from the shared radar event provider — used by the Discover overlay.
NextTrainingInfo? resolveNextTraining(List<RadarEvent> events) {
  RadarEvent? next;
  for (final e in events) {
    if (e.type != RadarEventType.trainingSession &&
        e.type != RadarEventType.match &&
        e.type != RadarEventType.trial) {
      continue;
    }
    if (e.isLive || e.isUpcoming) {
      if (next == null || e.startsAt.isBefore(next.startsAt)) next = e;
    }
  }
  return next == null ? null : NextTrainingInfo(event: next);
}

/// The uploaded design's live invitation card.
///
/// The whole card is a deep link: tapping it, or "SCOUT IN PERSON", closes the
/// reel and selects the host's pitch pin on the Radar Map tab. "BOUNTY 25 π"
/// opens the bounty composer for the same session.
class NextTrainingOverlayCard extends StatelessWidget {
  const NextTrainingOverlayCard({
    super.key,
    required this.info,
    required this.onScoutInPerson,
    this.onBounty,
    this.onOpenProfile,
    this.overMedia = true,
    this.compact = false,
  });

  final NextTrainingInfo info;

  /// Deep link → the player's pin on the Radar Map tab.
  final VoidCallback onScoutInPerson;

  /// Opens the Pi bounty flow for this session.
  final VoidCallback? onBounty;

  /// Optional profile route (avatar / name tap).
  final VoidCallback? onOpenProfile;

  /// Renders on the spec's near-opaque well when it sits over photography.
  final bool overMedia;

  /// Drops the secondary lines on very short viewports.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final event = info.event;
    final live = event.isLive;
    final amount = event.bountyPi ?? 25;
    final scouts = event.attendingCount;
    final distance = _distanceLabel(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('live-invitation-card'),
        onTap: onScoutInPerson,
        borderRadius: BorderRadius.circular(RadarRadius.card),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RadarRadius.card),
          child: Container(
            decoration: BoxDecoration(
              color: (overMedia ? RadarTheme.panelLowest : RadarTheme.panel)
                  .withValues(alpha: 0.95),
              border: Border.all(color: RadarTheme.stroke),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xA6000000),
                  blurRadius: 32,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LaserEdge(height: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(context, live),
                      const SizedBox(height: 8),
                      _matchLine(event),
                      if (!compact) ...[
                        const SizedBox(height: 5),
                        _distanceLine(distance),
                        if (scouts > 0) ...[
                          const SizedBox(height: 6),
                          _scoutsPill(scouts, event),
                        ],
                      ],
                      const SizedBox(height: 12),
                      _ctas(amount),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool live) {
    return Row(
      children: [
        const LiveDot(size: 9, animate: false),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            live ? 'LIVE SESSION — IN PROGRESS' : 'LIVE SESSION INVITATION',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RadarType.heading(
              19,
              weight: FontWeight.w700,
              color: const Color(0xFFF0FFEE),
              tracking: 0.9,
              height: 1.05,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: RadarTheme.panelHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined,
                  size: 13, color: RadarTheme.radar),
              const SizedBox(width: 4),
              live
                  ? Text(
                      'LIVE NOW',
                      style: RadarType.caps.copyWith(
                        fontSize: 10.5,
                        color: RadarTheme.radar,
                      ),
                    )
                  : LiveCountdownText(
                      target: info.event.startsAt,
                      formatter: formatClockCountdown,
                      style: RadarType.metricMd.copyWith(
                        fontSize: 12,
                        height: 1.0,
                        color: RadarTheme.radar,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _matchLine(RadarEvent event) {
    final title = event.title.trim().isEmpty ? 'Open training session' : event.title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.stadium_outlined, size: 17, color: RadarTheme.info),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RadarType.bodyMd.copyWith(
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: RadarTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _distanceLine(String? distance) {
    return Row(
      children: [
        Icon(Icons.location_on_outlined,
            size: 15, color: RadarTheme.alert),
        const SizedBox(width: 5),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                if (distance != null)
                  TextSpan(
                    text: distance,
                    style: RadarType.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: RadarTheme.textPrimary,
                    ),
                  ),
                TextSpan(
                  text: distance == null
                      ? '${info.event.safeLocationLabel()} · from your sideline GPS'
                      : ' away from your current sideline GPS',
                  style: RadarType.bodySm.copyWith(
                    fontSize: 11.5,
                    color: RadarTheme.textDim,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _scoutsPill(int scouts, RadarEvent event) {
    final tag = event.hostName.trim().isEmpty ? 'Radar scouting network' : event.hostName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: RadarTheme.panelHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(RadarRadius.base),
      ),
      // A Wrap, not a Row: the attendance line and the host tag degrade onto a
      // second line on a narrow phone instead of painting an overflow band.
      child: Wrap(
        spacing: 5,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 15, color: RadarTheme.info),
          Text(
            '$scouts Verified ${scouts == 1 ? 'Scout' : 'Scouts'}',
            style: RadarType.bodySm.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: RadarTheme.info,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              '($tag)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RadarType.bodySm.copyWith(
                fontSize: 11,
                color: RadarTheme.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctas(double amount) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: RadarPrimaryButton(
            label: 'Scout in Person',
            icon: Icons.explore_outlined,
            height: 42,
            compactLabel: true,
            onPressed: onScoutInPerson,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: onBounty,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: RadarTheme.panelHighest,
                borderRadius: BorderRadius.circular(RadarRadius.base),
                boxShadow: [
                  BoxShadow(
                    color: RadarTheme.gold.withValues(alpha: 0.20),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: RadarTheme.goldBright,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      'π',
                      style: RadarType.capsTight.copyWith(
                        fontSize: 10,
                        color: const Color(0xFF442B00),
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'BOUNTY ${fmtPi(amount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        14,
                        weight: FontWeight.w700,
                        color: RadarTheme.goldBright,
                        tracking: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Distance from the signed-in viewer's regional base to the session, when
  /// both coordinates are known. Deliberately derived from the profile's
  /// regional base (not device GPS) so no permission prompt is needed.
  String? _distanceLabel(BuildContext context) {
    final session = _sessionOf(context);
    final lat = session?.viewerLatitude;
    final lon = session?.viewerLongitude;
    if (lat == null || lon == null) return null;
    final d = distanceKm(
      lat1: lat,
      lon1: lon,
      lat2: info.event.latitude,
      lon2: info.event.longitude,
    );
    if (d <= 0 || d.isNaN || d.isInfinite) return null;
    return '${d.toStringAsFixed(1)} km';
  }

  RadarSession? _sessionOf(BuildContext context) {
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(sessionProvider);
    } catch (_) {
      return null;
    }
  }
}
