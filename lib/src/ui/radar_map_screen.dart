import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/connection_request.dart';
import 'city_map_canvas.dart';
import '../models/enums.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/radar_providers.dart';
import 'bounty_board_screen.dart';
import 'event_composer_screen.dart';
import 'event_detail_screen.dart';
import 'map_pins.dart';
import 'profiles_screen.dart';
import 'search_screen.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Live interactive radar: events placed on a sweep radar by bearing &
/// distance from the viewer's region.
class RadarMapScreen extends ConsumerStatefulWidget {
  const RadarMapScreen({super.key});

  @override
  ConsumerState<RadarMapScreen> createState() => _RadarMapScreenState();
}

class _RadarMapScreenState extends ConsumerState<RadarMapScreen> {
  RadarEvent? _selected;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(filteredEventsProvider);
    final eventsAsync = ref.watch(radarEventsProvider);
    final bounties = ref.watch(streamBountiesProvider).value ?? const <StreamBounty>[];
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final wide = size != WindowSize.compact;

    // Interactive scouting map pins: events by live/scheduled state plus
    // active funded bounties, each color-coded (🟢 live · 🟡 scheduled ·
    // 🔴 bounty).
    final pins = <MapPin>[
      for (final e in events) MapPin.fromEvent(e),
      for (final b in bounties)
        if (b.status == 'funded' || b.status == 'accepted' || b.status == 'live')
          MapPin.fromBounty(b),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: RadarTheme.radar, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            const Text('LIVE RADAR'),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${events.length} active · ${bounties.where((b) => b.isFunded && b.status != 'completed').length} bounties',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, color: RadarTheme.textDim, fontWeight: FontWeight.w400),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Global search',
            icon: const Icon(Icons.travel_explore, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Publish event',
            icon: const Icon(Icons.add_location_alt_outlined, size: 20),
            onPressed: () => EventComposerScreen.show(context),
          ),
          IconButton(
            tooltip: 'Safety policy',
            icon: const Icon(Icons.shield_outlined, size: 20),
            onPressed: _showSafetyDialog,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: eventsAsync.isLoading && events.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        flex: 3,
                        child: _cityMap(pins, wide, events, bounties)),
                    SizedBox(
                      width: 360,
                      child: _EventSidePanel(
                        events: events,
                        selected: _selected,
                        onSelect: (e) => setState(() => _selected = e),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Filter chips row sits directly above the map (mock).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                      child: SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: const [
                            _FilterChips(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: _cityMap(pins, wide, events, bounties)),
                  ],
                ),
    );
  }

  /// The satellite-style city map with semantic marker overlays.
  Widget _cityMap(List<MapPin> pins, bool wide, List<RadarEvent> events,
      List<StreamBounty> bounties) {
    final live = events.where((e) => e.isLive).toList();
    final scheduled = events.where((e) => !e.isLive).toList();
    final protectedEvents = events.where((e) => e.isMinorProtected).toList();
    final activeBounties = bounties
        .where((b) => b.status == 'funded' || b.status == 'accepted' || b.status == 'live')
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: CityMapCanvas()),
          Positioned.fill(
            child: CityMapMarkerLayout(
              liveEvents: live,
              scheduledEvents: scheduled,
              bounties: activeBounties,
              protectedEvents: protectedEvents,
              onSelectEvent: (e) {
                if (wide) {
                  setState(() => _selected = e);
                } else {
                  _openEventSheet(context, e);
                }
              },
              onSelectBounty: (_) => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BountyBoardScreen()),
              ),
            ),
          ),
          const Positioned(top: 14, right: 14, child: _ScoutingLegend()),
        ],
      ),
    );
  }

  void _openEventSheet(BuildContext context, RadarEvent e) {
    setState(() => _selected = e);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RadarTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EventDetailsSheet(event: e),
    );
  }

  void _showSafetyDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location safety policy'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The Radar protects young players by default:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Bullet('Events involving minors (U18) show an approximate area '
                  'name only — never exact venues or coordinates.'),
              Bullet('Signed-in hosts always see their own events in full '
                  'detail.'),
              Bullet('Verified scouts & clubs can request exact access from '
                  'hosts; nothing is exposed automatically.'),
              Bullet('Profiles of minors hide precise locations everywhere on '
                  'the platform.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }
}

/// Map legend: the scouting color code from the spec.
class _ScoutingLegend extends StatelessWidget {
  const _ScoutingLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: RadarTheme.ink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            dot(RadarTheme.radar),
            const SizedBox(width: 6),
            const Text('🟢 Live now', style: _legendStyle),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            dot(RadarTheme.gold),
            const SizedBox(width: 6),
            const Text('🟡 Scheduled', style: _legendStyle),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            dot(RadarTheme.alert),
            const SizedBox(width: 6),
            const Text('🔴 Bounty active', style: _legendStyle),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shield_outlined, size: 10, color: RadarTheme.textDim),
            const SizedBox(width: 6),
            const Text('Minor-protected', style: _legendStyle),
          ]),
        ],
      ),
    );
  }

  static const _legendStyle =
      TextStyle(fontSize: 10.5, color: RadarTheme.textDim);
}

// ------------------------------------------------------------- filter chips

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(radarFilterProvider);
    final ctrl = ref.read(radarFilterProvider.notifier);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in RadarEventType.values)
          FilterChip(
            label: Text(t.label),
            selected: filter.types.contains(t),
            onSelected: (_) => ctrl.toggleType(t),
            avatar: Icon(t.icon, size: 15, color: filter.types.contains(t)
                ? RadarTheme.radar
                : RadarTheme.textDim),
          ),
        FilterChip(
          label: const Text('Boosted'),
          selected: filter.onlyBoosted,
          onSelected: ctrl.setOnlyBoosted,
          avatar: const Icon(Icons.bolt, size: 15, color: RadarTheme.gold),
        ),
        // Age-bracket picker (spec: instant sorting by age bracket).
        PopupMenuButton<AgeBracket>(
          tooltip: 'Filter by age bracket',
          onSelected: (b) => ctrl.setAgeBracket(
              filter.ageBracket == b ? null : b),
          itemBuilder: (_) => [
            for (final b in AgeBracket.values)
              PopupMenuItem(
                value: b,
                child: Row(
                  children: [
                    Icon(
                      filter.ageBracket == b
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                      color: RadarTheme.pi,
                    ),
                    const SizedBox(width: 8),
                    Text(b.label),
                  ],
                ),
              ),
          ],
          child: FilterChip(
            label: Text(filter.ageBracket?.label ?? 'Age'),
            selected: filter.ageBracket != null,
            onSelected: (_) {}, // opens the menu via the popup wrapper
            avatar: const Icon(Icons.cake_outlined,
                size: 15, color: RadarTheme.info),
          ),
        ),
        // Position requirement picker (spec: position requirements).
        PopupMenuButton<String>(
          tooltip: 'Filter by position needed',
          onSelected: (p) => ctrl.setPosition(
              filter.position == p ? null : p),
          itemBuilder: (_) => [
            for (final p in kFootballPositions)
              PopupMenuItem(
                value: p,
                child: Row(
                  children: [
                    Icon(
                      filter.position == p
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                      color: RadarTheme.pi,
                    ),
                    const SizedBox(width: 8),
                    Text(p),
                  ],
                ),
              ),
          ],
          child: FilterChip(
            label: Text(filter.position ?? 'Position'),
            selected: filter.position != null,
            onSelected: (_) {},
            avatar: const Icon(Icons.sports_soccer,
                size: 15, color: RadarTheme.radar),
          ),
        ),
        // Verified hosts only (spec: verification status filtering).
        FilterChip(
          label: const Text('Verified hosts'),
          selected: filter.verifiedHostsOnly,
          onSelected: ctrl.setVerifiedHostsOnly,
          avatar: const Icon(Icons.verified_outlined,
              size: 15, color: RadarTheme.radar),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- panels

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final RadarEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('E d MMM · HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? RadarTheme.panelHigh : RadarTheme.panel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(event.type.icon, size: 15, color: RadarTheme.radar),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (event.isBoosted)
                    const Icon(Icons.bolt, size: 15, color: RadarTheme.gold),
                  if (event.bountyPi != null) ...[
                    const SizedBox(width: 6),
                    Text('${event.bountyPi!.toStringAsFixed(0)} π',
                        style: const TextStyle(
                            fontSize: 11,
                            color: RadarTheme.gold,
                            fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 12,
                      color: event.isMinorProtected
                          ? RadarTheme.gold
                          : RadarTheme.textDim),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      event.safeLocationLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: RadarTheme.textDim),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${df.format(event.startsAt)}  ·  ${event.attendingCount}'
                '${event.capacity != null ? '/${event.capacity}' : ''} attending',
                style: const TextStyle(
                    fontSize: 11.5, color: RadarTheme.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventSidePanel extends StatelessWidget {
  const _EventSidePanel({
    required this.events,
    required this.selected,
    required this.onSelect,
  });

  final List<RadarEvent> events;
  final RadarEvent? selected;
  final ValueChanged<RadarEvent> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SectionHeader('Event feed',
                trailing: Text('${events.length}',
                    style: const TextStyle(color: RadarTheme.textDim))),
          ),
          Expanded(
            child: events.isEmpty
                ? const Center(
                    child: Text('No events match the current filters.',
                        style: TextStyle(color: RadarTheme.textDim)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      return _EventCard(
                        event: e,
                        selected: e.id == selected?.id,
                        onTap: () => onSelect(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Detail sheet shared by mobile tap & desktop selection.
class EventDetailsSheet extends ConsumerWidget {
  const EventDetailsSheet({super.key, required this.event});

  final RadarEvent event;

  void _openHostProfile(BuildContext context, WidgetRef ref, UserProfile host) {
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    if (size == WindowSize.compact) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RadarTheme.panel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: ProfileDetailSheet(profile: host),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: RadarTheme.panel,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: ProfileDetailSheet(profile: host),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('EEEE d MMMM · HH:mm');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: RadarTheme.radar.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(event.type.icon, size: 18, color: RadarTheme.radar),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(event.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoPill(
                  icon: Icons.shield_outlined,
                  label: event.safeLocationLabel(),
                  color: event.isMinorProtected
                      ? RadarTheme.gold
                      : RadarTheme.radar,
                ),
                if (event.isLive) const InfoPill(icon: Icons.circle, label: 'LIVE now', color: RadarTheme.alert),
                if (event.isBoosted) const InfoPill(icon: Icons.bolt, label: 'Boosted', color: RadarTheme.gold),
                if (event.minAge != null || event.maxAge != null)
                  InfoPill(
                    icon: Icons.cake_outlined,
                    label:
                        'Ages ${event.minAge ?? '?'}–${event.maxAge ?? '?'}',
                  ),
              ],
            ),
            if (event.description != null) ...[
              const SizedBox(height: 12),
              Text(event.description!,
                  style: const TextStyle(
                      fontSize: 13, color: RadarTheme.textPrimary)),
            ],
            const SizedBox(height: 12),
            Text('Hosted by ${event.hostName}',
                style:
                    const TextStyle(fontSize: 12, color: RadarTheme.textDim)),
            Text(df.format(event.startsAt),
                style:
                    const TextStyle(fontSize: 12, color: RadarTheme.textDim)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final host = (ref.read(profilesProvider).value ?? const <UserProfile>[])
                          .where((p) => p.id == event.hostProfileId)
                          .firstOrNull;
                      if (host == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Host profile is not available.')),
                        );
                        return;
                      }
                      requestConnection(
                        context,
                        ref,
                        host,
                        event: event,
                        initialType: event.type == RadarEventType.trial
                            ? ConnectionType.trialApplication
                            : ConnectionType.contact,
                      );
                    },
                    icon: const Icon(Icons.how_to_reg, size: 17),
                    label: Text(event.type == RadarEventType.trial
                        ? 'Apply to trial'
                        : 'Request attendance'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    final host = (ref.read(profilesProvider).value ?? const <UserProfile>[])
                        .where((p) => p.id == event.hostProfileId)
                        .firstOrNull;
                    if (host == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Host profile is not available.')),
                      );
                      return;
                    }
                    _openHostProfile(context, ref, host);
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Host profile'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                key: const ValueKey('event-full-details'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EventDetailScreen(event: event),
                  ),
                ),
                icon: const Icon(Icons.unfold_more, size: 16),
                label: const Text('Full details & applicants'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Bullet extends StatelessWidget {
  const Bullet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: RadarTheme.radar),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, height: 1.45)),
          ),
        ],
      ),
    );
  }
}


