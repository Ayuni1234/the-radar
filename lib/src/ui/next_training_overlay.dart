import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/radar_event.dart';
import '../models/enums.dart';
import '../state/radar_providers.dart';
import 'live_countdown.dart';
import 'radar_theme.dart';

/// Data for the floating "Next Live Training" overlay card on the Reels
/// feed — the hackathon mockup's hero overlay ("Main Pitch · 3:20 PM",
/// "00:03:22:4h", "GO TO PROFILE / WATCH LIVE").
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

  String get pitch =>
      pitchLabel ?? event.venueName ?? event.safeLocationLabel();

  String get startTimeLabel => DateFormat('h:mm a').format(event.startsAt);
}

/// Resolve the viewer's next upcoming (or currently live) training session
/// from the shared radar event provider — used by the Reels overlay.
NextTrainingInfo? resolveNextTraining(List<RadarEvent> events) {
  RadarEvent? next;
  for (final e in events) {
    if (e.type != RadarEventType.trainingSession &&
        e.type != RadarEventType.match) {
      continue;
    }
    if (e.isLive || e.isUpcoming) {
      if (next == null || e.startsAt.isBefore(next.startsAt)) next = e;
    }
  }
  return next == null ? null : NextTrainingInfo(event: next);
}

/// Floating overlay card: "Next Live Training Info" + pitch + countdown +
/// GO TO PROFILE / WATCH LIVE CTA. Semi-transparent dark surface in both
/// themes (it sits on top of feed media), per the mockup.
class NextTrainingOverlayCard extends ConsumerStatefulWidget {
  const NextTrainingOverlayCard({
    super.key,
    required this.info,
    required this.onGoToProfile,
    this.onWatchLive,
    this.flat = false,
  });

  final NextTrainingInfo info;

  /// Deep link to the player's profile (CV + live session info tab).
  final VoidCallback onGoToProfile;

  /// Optional separate "watch live" action (defaults to [onGoToProfile]).
  final VoidCallback? onWatchLive;

  /// Drops the card's own surface (fill, border, padding) so it reads as part
  /// of a parent panel — the Reels overlay card, which already provides the
  /// translucent violet surface behind the media.
  final bool flat;

  @override
  ConsumerState<NextTrainingOverlayCard> createState() =>
      _NextTrainingOverlayCardState();
}

class _NextTrainingOverlayCardState
    extends ConsumerState<NextTrainingOverlayCard> {
  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isLive = info.event.isLive;

    return Container(
      padding: widget.flat
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: widget.flat
          ? null
          : BoxDecoration(
              // Semi-transparent deep-violet overlay — readable over any
              // media.
              color: const Color(0xFF1A1230).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLive
                    ? RadarTheme.radar.withValues(alpha: 0.6)
                    : RadarTheme.gold.withValues(alpha: 0.35),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLive ? 'Live Training In Progress' : 'Next Live Training Info',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          // Pitch · kick-off on the left, the live countdown on the right —
          // the mockup's "Main Pitch · 2.30pm   00:03:22:4h" row.
          Row(
            children: [
              Expanded(
                child: Text(
                  '${info.pitch} · ${info.startTimeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (!isLive)
                LiveCountdownText(
                  target: info.event.startsAt,
                  style: const TextStyle(
                    color: Color(0xFFF5C043),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                )
              else
                Row(
                  children: [
                    Icon(Icons.podcasts, size: 16, color: RadarTheme.radar),
                    const SizedBox(width: 6),
                    const Text(
                      'Broadcasting now',
                      style: TextStyle(
                        color: Color(0xFF3DFFA2),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          // GO TO PROFILE / WATCH LIVE — deep-links to the player's profile
          // and GPS location broadcast. Violet, per the mockup's CTA pill.
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: RadarTheme.pi,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            ),
            onPressed: isLive
                ? (widget.onWatchLive ?? widget.onGoToProfile)
                : widget.onGoToProfile,
            icon: Icon(isLive ? Icons.play_arrow : Icons.person, size: 15),
            label: Text(
              isLive ? 'WATCH LIVE' : 'GO TO PROFILE',
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience provider-backed wrapper: picks the next session from the
/// radar events and wires the deep link through [onOpenProfile].
class NextTrainingOverlay extends ConsumerWidget {
  const NextTrainingOverlay({
    super.key,
    required this.onOpenProfile,
    this.onWatchLive,
  });

  /// Called with the host profile id of the next session.
  final void Function(String hostProfileId) onOpenProfile;

  final void Function(String hostProfileId)? onWatchLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];
    final info = resolveNextTraining(events);
    if (info == null) return const SizedBox.shrink();
    return NextTrainingOverlayCard(
      info: info,
      onGoToProfile: () => onOpenProfile(info.event.hostProfileId),
      onWatchLive: onWatchLive == null
          ? null
          : () => onWatchLive!(info.event.hostProfileId),
    );
  }
}
