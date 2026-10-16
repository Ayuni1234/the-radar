import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import '../models/radar_event.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../state/radar_providers.dart';
import '../models/feed_post.dart' show distanceKm;
import 'live_countdown.dart';
import 'player_cv_screen.dart';
import 'radar_theme.dart';
import 'shell.dart' show InfoPill;

/// Player Profile & Session Broadcast — the hackathon mockup's profile hub:
/// avatar, name, age, position, bio and a segmented control
/// [Bio] [Highlights] [LIVE Session Info] with:
///  * countdown to the next session (00:03:22:4h),
///  * Live GPS Broadcast mini-map snippet,
///  * "Go Watch Player Live" (turn-by-turn navigation deep link),
///  * "Set Bounty for this Match".
///
/// Wraps [PlayerCvScreen]'s rich bio/highlights content as the first two
/// tabs and adds the live-broadcast tab built on the real map widget.
class PlayerLiveSessionScreen extends ConsumerWidget {
  const PlayerLiveSessionScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];
    final own = events
        .where((e) => e.hostProfileId == profile.id)
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final next = own.firstWhere(
      (e) => e.isLive || e.isUpcoming,
      orElse: () => RadarEvent(
        id: '',
        type: RadarEventType.trainingSession,
        title: '',
        hostProfileId: '',
        hostName: '',
        latitude: 0,
        longitude: 0,
        startsAt: DateTime.now(),
        endsAt: DateTime.now(),
        precision: GeoPrecision.approximate,
      ),
    );
    final hasNext = next.id.isNotEmpty;
    final nextIsLive = hasNext && next.isLive;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: RadarTheme.ink,
        appBar: AppBar(
          title: Text(profile.bestName,
              style: const TextStyle(fontSize: 15)),
        ),
        body: NestedScrollView(
          headerSliverBuilder: (_, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 118,
              automaticallyImplyLeading: false,
              backgroundColor: RadarTheme.ink,
              flexibleSpace: FlexibleSpaceBar(
                background: _PlayerHero(profile: profile),
              ),
            ),
            PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: Container(
                color: RadarTheme.ink,
                child: TabBar(
                  labelColor: RadarTheme.gold,
                  unselectedLabelColor: RadarTheme.textDim,
                  indicatorColor: RadarTheme.gold,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Bio'),
                    Tab(text: 'Highlights'),
                    Tab(text: 'LIVE Session Info'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _BioTab(profile: profile),
              _HighlightsTab(profile: profile),
              _LiveSessionTab(
                profile: profile,
                nextHasSession: hasNext,
                nextSession: hasNext ? next : null,
                nextIsLive: nextIsLive,
                ownSessions: own,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- hero

class _PlayerHero extends StatelessWidget {
  const _PlayerHero({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final role = p.role;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: BoxDecoration(
        color: RadarTheme.panel.withValues(alpha: 0.5),
        border: Border(
            bottom: BorderSide(color: RadarTheme.stroke, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [RadarTheme.gold, RadarTheme.pi],
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RadarTheme.ink,
              ),
              alignment: Alignment.center,
              child: Text(
                p.bestName.isNotEmpty ? p.bestName[0].toUpperCase() : '?',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: RadarTheme.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.bestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: RadarTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  '${p.age != null ? "Age ${p.age}" : "Age —"}'
                  ' · ${role.label}',
                  style: TextStyle(
                      color: RadarTheme.textDim, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ bio tab

class _BioTab extends StatelessWidget {
  const _BioTab({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Bio',
            style: TextStyle(
                color: RadarTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          profile.bio?.trim().isNotEmpty == true
              ? profile.bio!
              : 'No bio yet — the player can add one from their Football CV.',
          style: TextStyle(
              color: RadarTheme.textDim, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            InfoPill(
                icon: Icons.speed,
                label:
                    'Credibility ${profile.credibilityScore.toStringAsFixed(0)}/100',
                color: profile.credibilityScore >= 75
                    ? RadarTheme.radar
                    : RadarTheme.gold),
            if (profile.kycVerified)
              InfoPill(
                  icon: Icons.verified,
                  label: 'KYC verified',
                  color: RadarTheme.radar),
            if (profile.positions.isNotEmpty)
              InfoPill(
                  icon: Icons.sports_soccer_outlined,
                  label: profile.positions.join(' · '),
                  color: RadarTheme.info),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- highlights tab

class _HighlightsTab extends StatelessWidget {
  const _HighlightsTab({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final links = profile.videoShowcaseUrls;
    return links.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.movie_creation_outlined,
                    size: 40, color: RadarTheme.textDim),
                const SizedBox(height: 10),
                Text('No highlight videos yet',
                    style: TextStyle(color: RadarTheme.textDim)),
              ],
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(18),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: links.length,
            itemBuilder: (context, i) => Container(
              decoration: BoxDecoration(
                color: RadarTheme.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: RadarTheme.stroke),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: RadarTheme.panelHigh),
                    Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 40,
                          color: RadarTheme.gold.withValues(alpha: 0.7)),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
                        'Highlight ${i + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
  }
}

// ------------------------------------------------------ live session tab

class _LiveSessionTab extends ConsumerWidget {
  const _LiveSessionTab({
    required this.profile,
    required this.nextHasSession,
    required this.nextSession,
    required this.nextIsLive,
    required this.ownSessions,
  });

  final UserProfile profile;
  final bool nextHasSession;
  final RadarEvent? nextSession;
  final bool nextIsLive;
  final List<RadarEvent> ownSessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!nextHasSession || nextSession == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined,
                size: 40, color: RadarTheme.textDim),
            const SizedBox(height: 10),
            Text('No scheduled sessions yet',
                style: TextStyle(color: RadarTheme.textDim)),
          ],
        ),
      );
    }

    final e = nextSession!;
    final df = DateFormat('EEE d MMM · h:mm a');
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text("There's next session in",
            style: TextStyle(color: RadarTheme.textDim, fontSize: 12.5)),
        const SizedBox(height: 4),
        if (nextIsLive)
          Row(children: [
            Icon(Icons.podcasts, color: RadarTheme.radar, size: 20),
            const SizedBox(width: 8),
            Text('LIVE NOW — broadcasting',
                style: TextStyle(
                    color: RadarTheme.radar,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ])
        else
          LiveCountdownText(
            target: e.startsAt,
            style: TextStyle(
              color: RadarTheme.gold,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        const SizedBox(height: 12),
        InfoPill(
          icon: Icons.schedule,
          label: df.format(e.startsAt),
          color: RadarTheme.info,
        ),
        const SizedBox(height: 16),
        Text('Live GPS Broadcast',
            style: TextStyle(
                color: RadarTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _LiveGpsMiniMap(event: e),
        const SizedBox(height: 16),
        // "Go Watch Player Live" — turn-by-turn navigation deep link for
        // local scouts.
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: RadarTheme.pi,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () async => _openNavigation(context, e),
          icon: const Icon(Icons.directions, size: 18),
          label: const Text('Go Watch Player Live',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        // "Set Bounty for this Match" — remote scouts commission a local
        // camera pioneer; flows into the posted-bounty sheet pre-filled.
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: RadarTheme.gold,
            side: BorderSide(color: RadarTheme.gold.withValues(alpha: 0.6)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          onPressed: () => _openSetBountySheet(context, ref, e),
          icon: const Icon(Icons.workspace_premium, size: 18),
          label: const Text('Set Bounty for this Match',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _openNavigation(BuildContext context, RadarEvent e) async {
    final lat = e.latitude;
    final lon = e.longitude;
    final hasFix = !(lat == 0 && lon == 0);
    if (!hasFix) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHigh,
        content: const Text(
            'Approximate location only — the exact pitch opens in the map.'),
      ));
      return;
    }
    // Navigation deep link: geo: works on Android, maps.apple.com on iOS;
    // desktop/web falls back to Google Maps directions.
    final label = Uri.encodeComponent(e.safeLocationLabel());
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=walking&q=$label');
    // ignore: avoid_print
    debugPrint('[WatchLive] navigate → $url');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHigh,
      content: Text('Opening directions to ${e.safeLocationLabel()}…'),
    ));
  }

  Future<void> _openSetBountySheet(
      BuildContext context, WidgetRef ref, RadarEvent e) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHigh,
      content: Text(
          'Bounty composer opening for "${e.title}" — Pi escrow flow starts '
          'once you post.'),
    ));
  }
}

// ----------------------------------------------------------- gps mini-map

class _LiveGpsMiniMap extends StatelessWidget {
  const _LiveGpsMiniMap({required this.event});

  final RadarEvent event;

  @override
  Widget build(BuildContext context) {
    final isLive = event.isLive;
    final lat = event.latitude;
    final lon = event.longitude;
    final hasFix = !(lat == 0 && lon == 0);
    // Minor-protected events are approximate already (safeLocationLabel).
    return Container(
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isLive
                ? RadarTheme.radar.withValues(alpha: 0.5)
                : RadarTheme.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasFix
              ? FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.theradar.app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(lat, lon),
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: (isLive
                                    ? RadarTheme.radar
                                    : RadarTheme.gold)
                                .withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.place,
                              color: isLive
                                  ? RadarTheme.radar
                                  : RadarTheme.gold,
                              size: 22),
                        ),
                      ),
                    ]),
                  ],
                )
              : Container(
                  color: RadarTheme.panelHigh,
                  alignment: Alignment.center,
                  child: Text('Location not broadcast yet',
                      style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
                ),
          if (isLive)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: RadarTheme.radar),
                  const SizedBox(width: 5),
                  const Text('LIVE GPS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Distance helper re-exported for test convenience.
double distanceFromViewer({
  required double viewerLat,
  required double viewerLon,
  required RadarEvent event,
}) =>
    distanceKm(lat1: viewerLat, lon1: viewerLon, lat2: event.latitude, lon2: event.longitude);
