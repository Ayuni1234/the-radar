import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show HomeShell;
import '../models/enums.dart';
import '../models/feed_post.dart' as feed_geo;
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/map_focus.dart';
import '../state/radar_providers.dart';
import 'bounty_board_screen.dart';
import 'design/radar_design.dart';
import 'event_composer_screen.dart';
import 'profile_hub_screen.dart';
import 'radar_theme.dart';
import 'radar_top_bar.dart';
import 'search_screen.dart';

/// Live Radar — the uploaded "Live Pitch Map" design.
///
/// A nocturnal tactical canvas (grid, range rings, rotating sweep) with the
/// spec's pin treatments, a search/filter header, and the pitch-intel drawer
/// underneath. Pins come from the same event + bounty providers the rest of
/// the app uses, so the Discover deep link lands on the host's pin with their
/// intel already open.
class RadarMapScreen extends ConsumerStatefulWidget {
  const RadarMapScreen({super.key});

  @override
  ConsumerState<RadarMapScreen> createState() => _RadarMapScreenState();
}

class _RadarMapScreenState extends ConsumerState<RadarMapScreen> {
  RadarEvent? _selected;
  final TextEditingController _searchCtrl = TextEditingController(
    text: 'Hackney Marshes & Mabley Green',
  );
  int _filter = 0;
  int _seenFocus = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(filteredEventsProvider);
    final bounties =
        ref.watch(streamBountiesProvider).value ?? const <StreamBounty>[];

    // Cross-tab deep link from the Discover invitation card.
    ref.listen(mapFocusProvider, (previous, next) {
      if (next == null || next.token == _seenFocus) return;
      _seenFocus = next.token;
      _applyFocus(next, events);
    });

    final activeBounties =
        bounties.where((b) => b.isFunded).toList();
    final visible = _applyFilter(events);
    final selected = _selected ??
        (visible.isNotEmpty ? visible.first : (events.isNotEmpty ? events.first : null));

    final session = ref.watch(sessionProvider);
    int? distance;
    if (selected != null &&
        session?.viewerLatitude != null &&
        session?.viewerLongitude != null) {
      distance = feed_geo
          .distanceKm(
            lat1: session!.viewerLatitude!,
            lon1: session.viewerLongitude!,
            lat2: selected.latitude,
            lon2: selected.longitude,
          )
          .round();
    }

    final wide = windowSizeFor(MediaQuery.sizeOf(context).width) !=
        WindowSize.compact;

    final map = _TacticalRadarMap(
      events: visible,
      bounties: activeBounties,
      selectedId: selected?.id,
      onSelect: (e) => setState(() => _selected = e),
    );

    final sheet = _PitchIntelSheet(
      event: selected,
      distanceKm: distance,
      profiles: ref.watch(profilesProvider).value ?? const [],
      onBounty: () => showPostBountySheet(
        context,
        title: selected == null
            ? 'Camera / drone bounty'
            : 'Pitch-side camera · ${selected.title}',
        amountPi: 30,
        areaName: selected?.areaName,
      ),
      onRoute: () => _routeTo(selected),
      onOpenMapTab: () => HomeShell.goTo(context, 2),
    );

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: Column(
        children: [
          RadarTopBar(
            onAvatarTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileHubScreen()),
            ),
            onBalanceTap: () => HomeShell.goTo(context, 2),
          ),
          _MapHeader(
            controller: _searchCtrl,
            onQuery: (_) => setState(() {}),
            onRecenter: () => setState(() {
              _searchCtrl.text = '';
              _filter = 0;
            }),
            onSearch: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
            onAdd: () => EventComposerScreen.show(context),
            filter: _filter,
            onFilter: (i) => setState(() => _filter = i),
            count: visible.length,
          ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: map),
                      Expanded(flex: 2, child: sheet),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: map),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.47,
                        ),
                        child: sheet,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _applyFocus(MapFocusRequest request, List<RadarEvent> events) {
    RadarEvent? match;
    if (request.profileId != null) {
      for (final e in events) {
        if (e.hostProfileId == request.profileId) {
          match = e;
          break;
        }
      }
    }
    match ??= _nearest(request.lat, request.lon, events);
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHighest,
        content: Text(
          'No pitch pin is scheduled for ${request.label ?? 'that player'} yet.',
          style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary),
        ),
      ));
      return;
    }
    setState(() {
      _selected = match;
      _filter = 0;
      _searchCtrl.text = '';
    });
  }

  RadarEvent? _nearest(double? lat, double? lon, List<RadarEvent> events) {
    if (events.isEmpty) return null;
    if (lat == null || lon == null) return events.first;
    RadarEvent? best;
    var bestD = double.infinity;
    for (final e in events) {
      final d = feed_geo.distanceKm(
        lat1: lat,
        lon1: lon,
        lat2: e.latitude,
        lon2: e.longitude,
      );
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  List<RadarEvent> _applyFilter(List<RadarEvent> events) {
    final q = _searchCtrl.text.trim().toLowerCase();
    var list = events;
    if (q.isNotEmpty && q != 'hackney marshes & mabley green') {
      list = list
          .where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.hostName.toLowerCase().contains(q) ||
              (e.areaName ?? '').toLowerCase().contains(q) ||
              (e.venueName ?? '').toLowerCase().contains(q))
          .toList();
    }
    List<RadarEvent> filtered;
    switch (_filter) {
      case 0:
        final soon = DateTime.now().add(const Duration(hours: 2));
        filtered = list
            .where((e) => e.isLive || e.startsAt.isBefore(soon))
            .toList();
      case 1:
        filtered = list.where((e) => e.isLive).toList();
      case 2:
        filtered = list.where((e) => (e.minAge ?? 0) <= 17).toList();
      case 3:
        filtered = list
            .where((e) => (e.minAge ?? 0) <= 19 && (e.maxAge ?? 99) >= 17)
            .toList();
      case 4:
        filtered = list
            .where((e) => e.positionsRequired
                .any((p) => const ['ST', 'LW', 'RW'].contains(p.toUpperCase())))
            .toList();
      case 5:
        filtered =
            list.where((e) => e.precision == GeoPrecision.exact).toList();
      default:
        filtered = list;
    }
    // A filter that matches nothing must not blank the radar: fall back to the
    // full set, soonest kick-off first, so pitches stay discoverable.
    if (filtered.isEmpty && list.isNotEmpty) {
      filtered = List<RadarEvent>.from(list)
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    return filtered;
  }

  void _routeTo(RadarEvent? event) {
    if (event == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHighest,
      content: Text(
        'Route ready — ${event.safeLocationLabel()}',
        style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary),
      ),
      action: SnackBarAction(
        label: 'DISMISS',
        textColor: RadarTheme.radar,
        onPressed: () {},
      ),
    ));
  }
}

// ---------------------------------------------------------------------------
// Header: search + filter pill rail
// ---------------------------------------------------------------------------

class _MapHeader extends StatelessWidget {
  const _MapHeader({
    required this.controller,
    required this.onQuery,
    required this.onRecenter,
    required this.onSearch,
    required this.onAdd,
    required this.filter,
    required this.onFilter,
    required this.count,
  });

  final TextEditingController controller;
  final ValueChanged<String> onQuery;
  final VoidCallback onRecenter;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final int filter;
  final ValueChanged<int> onFilter;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            RadarTheme.panelLowest.withValues(alpha: 0.95),
            RadarTheme.panelLowest.withValues(alpha: 0),
          ],
        ),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RadarSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: RadarTheme.panelHighest,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Icon(Icons.explore_outlined,
                            size: 19, color: RadarTheme.radar),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            onChanged: onQuery,
                            textInputAction: TextInputAction.search,
                            style: RadarType.bodySm.copyWith(
                              fontSize: 12.5,
                              color: RadarTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintText:
                                  'Search pitch, player name, or borough...',
                              hintStyle: RadarType.bodySm.copyWith(
                                fontSize: 12.5,
                                color:
                                    RadarTheme.textDim.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Recenter GPS',
                          onPressed: onRecenter,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.my_location,
                              size: 19, color: RadarTheme.info),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _SquareAction(
                  icon: Icons.add_location_alt_outlined,
                  tooltip: 'Publish a live pitch',
                  onTap: onAdd,
                ),
                _SquareAction(
                  icon: Icons.search,
                  tooltip: 'Global search',
                  onTap: onSearch,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          RadarPillRail(children: [
            RadarPill(
              label: 'Starting Soon (< 2h)',
              icon: Icons.timer_outlined,
              selected: filter == 0,
              onTap: () => onFilter(0),
              trailing: count == 0
                  ? null
                  : Text(
                      '$count',
                      style: RadarType.capsTight.copyWith(
                        fontSize: 9,
                        color: filter == 0
                            ? RadarTheme.onAccent
                            : RadarTheme.textDim,
                      ),
                    ),
            ),
            RadarPill(
              label: 'Live Now',
              dot: true,
              color: RadarTheme.cyanDeep,
              selected: filter == 1,
              onTap: () => onFilter(1),
            ),
            RadarPill(
              label: 'U-17',
              selected: filter == 2,
              onTap: () => onFilter(2),
            ),
            RadarPill(
              label: 'U-19',
              selected: filter == 3,
              onTap: () => onFilter(3),
            ),
            RadarPill(
              label: 'Strikers',
              icon: Icons.sports_soccer,
              selected: filter == 4,
              onTap: () => onFilter(4),
            ),
            RadarPill(
              label: 'Verified Scouts Only',
              icon: Icons.verified_outlined,
              selected: filter == 5,
              onTap: () => onFilter(5),
            ),
          ]),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 30,
          height: 44,
          child: Icon(icon, size: 19, color: RadarTheme.textDim),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tactical radar canvas
// ---------------------------------------------------------------------------

class _TacticalRadarMap extends StatefulWidget {
  const _TacticalRadarMap({
    required this.events,
    required this.bounties,
    required this.selectedId,
    required this.onSelect,
  });

  final List<RadarEvent> events;
  final List<StreamBounty> bounties;
  final String? selectedId;
  final ValueChanged<RadarEvent> onSelect;

  @override
  State<_TacticalRadarMap> createState() => _TacticalRadarMapState();
}

class _TacticalRadarMapState extends State<_TacticalRadarMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  final TransformationController _view = TransformationController();

  @override
  void dispose() {
    _sweep.dispose();
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: RadarTheme.panelLowest,
            child: CustomPaint(
              painter: TacticalGridPainter(spacing: 24, dot: true),
            ),
          ),
        ),
        // HUD coordinate watermark.
        Positioned(
          top: 8,
          left: 14,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.satellite_alt_outlined,
                        size: 12, color: RadarTheme.info),
                    const SizedBox(width: 4),
                    RadarCaps(
                      'EAST LONDON SECTOR 04 // 51.5542° N, 0.0271° W',
                      size: 8.5,
                      color: RadarTheme.info.withValues(alpha: 0.7),
                      tracking: 0.9,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                RadarCaps(
                  'PITCH RECON FREQ: 914.8 MHz • LATENCY: 12ms',
                  size: 8,
                  color: RadarTheme.textFaint.withValues(alpha: 0.7),
                  weight: FontWeight.w500,
                  tracking: 0.4,
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: LayoutBuilder(builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final projection =
                _Projection.fit(widget.events, widget.bounties, size);
            final selectedPoint = (widget.selectedId != null
                    ? projection.pointFor(widget.selectedId!)
                    : null) ??
                Offset(size.width * 0.46, size.height * 0.42);

            return ClipRect(
              child: InteractiveViewer(
                transformationController: _view,
                minScale: 0.85,
                maxScale: 2.6,
                boundaryMargin: const EdgeInsets.all(80),
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _sweep,
                            builder: (context, _) => CustomPaint(
                              painter: _RadarPainter(
                                center: selectedPoint,
                                progress: _sweep.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: selectedPoint.dx - 7,
                        top: selectedPoint.dy - 7,
                        child: IgnorePointer(
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: RadarTheme.info,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      RadarTheme.info.withValues(alpha: 0.8),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: RadarTheme.panelLowest,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final event in widget.events)
                        if (projection.pointFor(event.id) != null)
                          _eventPin(event, projection.pointFor(event.id)!),
                      for (final bounty in widget.bounties)
                        if (projection.pointFor('b-${bounty.id}') != null)
                          _bountyPin(
                              bounty, projection.pointFor('b-${bounty.id}')!),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(
            children: [
              _MapTool(
                icon: Icons.layers_outlined,
                tooltip: 'Layer switch',
                onTap: () => _toast('Tactical layer active'),
              ),
              const SizedBox(height: 8),
              _MapTool(
                icon: Icons.radar,
                tooltip: 'Radar radius',
                onTap: () => _toast('Radar sweep active'),
              ),
              const SizedBox(height: 8),
              _MapTool(
                icon: Icons.center_focus_strong,
                tooltip: 'Recenter',
                onTap: () => _view.value = Matrix4.identity(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _eventPin(RadarEvent event, Offset point) {
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1.0),
        child: GestureDetector(
          onTap: () => widget.onSelect(event),
          child: _PitchPin(
            event: event,
            selected: event.id == widget.selectedId,
            live: event.isLive,
          ),
        ),
      ),
    );
  }

  Widget _bountyPin(StreamBounty bounty, Offset point) {
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1.0),
        child: GestureDetector(
          onTap: () =>
              _toast('${fmtPi(bounty.amountPi)} π bounty · ${bounty.areaName}'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: RadarTheme.panel.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(RadarRadius.card),
                  boxShadow: const [
                    BoxShadow(color: Color(0x99000000), blurRadius: 14),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      bounty.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 10.5,
                        color: RadarTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 13,
                          height: 13,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: RadarTheme.goldBright,
                            shape: BoxShape.circle,
                          ),
                          child: Text('π',
                              style: RadarType.capsTight.copyWith(
                                fontSize: 8,
                                color: const Color(0xFF442B00),
                                height: 1,
                              )),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            '${fmtPi(bounty.amountPi)} π Bounty Open',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RadarType.capsTight.copyWith(
                              fontSize: 8,
                              color: RadarTheme.goldBright,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RadarTheme.goldBright,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: RadarTheme.gold.withValues(alpha: 0.55),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Text('π',
                    style: RadarType.capsTight.copyWith(
                      fontSize: 9,
                      color: const Color(0xFF442B00),
                      height: 1,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHighest,
      duration: const Duration(milliseconds: 1600),
      content: Text(
        message,
        style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary),
      ),
    ));
  }
}

class _PitchPin extends StatelessWidget {
  const _PitchPin({
    required this.event,
    required this.selected,
    required this.live,
  });

  final RadarEvent event;
  final bool selected;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final accent = live ? RadarTheme.radar : RadarTheme.cyanDeep;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 206),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: RadarTheme.panelHighest.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(RadarRadius.sheet),
            boxShadow: const [
              BoxShadow(
                color: Color(0xB3000000),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      event.venueName ?? event.areaName ?? event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        16,
                        weight: FontWeight.w600,
                        color: const Color(0xFFF0FFEE),
                        height: 1.0,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: RadarTheme.panelLowest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LiveDot(size: 5, animate: false),
                          const SizedBox(width: 3),
                          Text(
                            live ? 'ACTIVE' : 'PINNED',
                            style: RadarType.capsTight.copyWith(
                              fontSize: 7.5,
                              color: RadarTheme.radar,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                event.hostName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RadarType.bodySm.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: RadarTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    live ? 'LIVE NOW' : 'KO in ${_relative(event.startsAt)}',
                    style: RadarType.capsTight.copyWith(
                      fontSize: 8,
                      color: live ? RadarTheme.radar : RadarTheme.greenDeep,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('•',
                      style: RadarType.capsTight.copyWith(
                          fontSize: 8, color: RadarTheme.textFaint)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${event.attendingCount} scouts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.capsTight.copyWith(
                        fontSize: 8,
                        color: RadarTheme.info,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: live ? RadarTheme.radar : RadarTheme.cyanDeep,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.7),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Icon(
                live ? Icons.sports_soccer : Icons.videocam_outlined,
                size: 15,
                color: live ? RadarTheme.onAccent : const Color(0xFF001F24),
              ),
            ),
          ],
        ),
        Container(
          width: 5,
          height: 7,
          decoration: BoxDecoration(
            color: accent,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(999)),
          ),
        ),
      ],
    );
  }

  static String _relative(DateTime when) {
    final d = when.difference(DateTime.now());
    if (d.isNegative) return 'now';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }
}

class _MapTool extends StatelessWidget {
  const _MapTool({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: RadarTheme.panelHighest.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: RadarTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Fits every pitch into the canvas with an inset so callouts never clip.
class _Projection {
  _Projection._(this.size, this.minLat, this.maxLat, this.minLon, this.maxLon,
      this.points);

  final Size size;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final Map<String, ({double lat, double lon})> points;

  factory _Projection.fit(
    List<RadarEvent> events,
    List<StreamBounty> bounties,
    Size size,
  ) {
    final points = <String, ({double lat, double lon})>{
      for (final e in events) e.id: (lat: e.latitude, lon: e.longitude),
      for (final b in bounties)
        if (b.latitude != null && b.longitude != null)
          'b-${b.id}': (lat: b.latitude!, lon: b.longitude!),
    };
    if (points.isEmpty) {
      return _Projection._(size, -1, 1, -1, 1, points);
    }
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final p in points.values) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    if ((maxLat - minLat).abs() < 0.02) {
      minLat -= 0.05;
      maxLat += 0.05;
    }
    if ((maxLon - minLon).abs() < 0.02) {
      minLon -= 0.05;
      maxLon += 0.05;
    }
    return _Projection._(size, minLat, maxLat, minLon, maxLon, points);
  }

  Offset? pointFor(String id) {
    final p = points[id];
    if (p == null) return null;
    final usableW = math.max(size.width - 130, 50.0);
    final usableH = math.max(size.height - 190, 50.0);
    final x = ((p.lon - minLon) / (maxLon - minLon)).clamp(0.0, 1.0);
    final y = 1 - ((p.lat - minLat) / (maxLat - minLat)).clamp(0.0, 1.0);
    return Offset(65 + x * usableW, 76 + y * usableH);
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.center, required this.progress});

  final Offset center;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Range rings.
    for (final (i, r) in const [60.0, 120.0, 180.0, 240.0].indexed) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = RadarTheme.info.withValues(alpha: 0.10 * (1 - i * 0.14));
      canvas.drawCircle(center, r, paint);
    }

    // Sweeping cyan sector.
    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          RadarTheme.info.withValues(alpha: 0),
          RadarTheme.info.withValues(alpha: 0.05),
          RadarTheme.radar.withValues(alpha: 0.16),
          RadarTheme.info.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.55, 0.86, 1.0],
        transform: GradientRotation(progress * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: 170));
    canvas.drawCircle(center, 170, sweep);

    // Crosshair ticks.
    final tick = Paint()
      ..color = RadarTheme.info.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (var a = 0; a < 12; a++) {
      final angle = a * math.pi / 6;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * 240;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * 247;
      canvas.drawLine(inner, outer, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.center != center || old.progress != progress;
}

// ---------------------------------------------------------------------------
// Pitch intel drawer
// ---------------------------------------------------------------------------

class _PitchIntelSheet extends StatelessWidget {
  const _PitchIntelSheet({
    required this.event,
    required this.distanceKm,
    required this.profiles,
    required this.onBounty,
    required this.onRoute,
    required this.onOpenMapTab,
  });

  final RadarEvent? event;
  final int? distanceKm;
  final List<UserProfile> profiles;
  final VoidCallback onBounty;
  final VoidCallback onRoute;
  final VoidCallback onOpenMapTab;

  @override
  Widget build(BuildContext context) {
    final e = event;
    UserProfile? host;
    if (e != null) {
      for (final p in profiles) {
        if (p.id == e.hostProfileId) {
          host = p;
          break;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: RadarTheme.panel.withValues(alpha: 0.98),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(RadarRadius.sheet)),
        border: Border.all(color: RadarTheme.stroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB3000000),
            blurRadius: 32,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: RadarTheme.lineStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            _header(e),
            const SizedBox(height: 12),
            if (e == null)
              _EmptyIntel(onOpen: onOpenMapTab)
            else ...[
              _PlayerTelemetry(event: e, host: host),
              const SizedBox(height: 10),
              _AccessProtocol(event: e),
              const SizedBox(height: 10),
              _ScoutPresence(
                event: e,
                trusted: e.precision == GeoPrecision.exact,
              ),
              const SizedBox(height: 12),
              RadarPrimaryButton(
                label: 'Start turn-by-turn GPS directions',
                icon: Icons.turn_right,
                height: 48,
                onPressed: onRoute,
              ),
              const SizedBox(height: 6),
              RadarGhostButton(
                label: 'Drop 30 π Drone/Camera Bounty',
                icon: Icons.sensors,
                tone: RadarGhostTone.gold,
                height: 44,
                onPressed: onBounty,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(RadarEvent? e) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      e == null
                          ? 'NO PITCH SELECTED'
                          : (e.venueName ?? e.areaName ?? e.title)
                              .toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        24,
                        weight: FontWeight.w700,
                        color: const Color(0xFFF0FFEE),
                        tracking: 0.6,
                        height: 1.05,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: RadarTheme.radar,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'MATCH RADAR',
                      style: RadarType.capsTight.copyWith(
                        fontSize: 8,
                        color: RadarTheme.onAccent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.navigation_outlined,
                      size: 14, color: RadarTheme.info),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      distanceKm == null
                          ? (e?.areaName ?? 'No GPS fix')
                          : '$distanceKm km (${_drive(distanceKm!)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: RadarTheme.info,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('•',
                      style: RadarType.capsTight
                          .copyWith(color: RadarTheme.textFaint)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      e == null
                          ? 'Pick a pin'
                          : '${e.type.label} • ${e.precision == GeoPrecision.exact ? 'Exact venue' : 'Approximate area'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 11.5,
                        color: RadarTheme.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: RadarTheme.panelHighest,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 10),
            ],
          ),
          child: Icon(Icons.directions_car_outlined,
              size: 21, color: RadarTheme.radar),
        ),
      ],
    );
  }
}

class _PlayerTelemetry extends StatelessWidget {
  const _PlayerTelemetry({required this.event, required this.host});

  final RadarEvent event;
  final UserProfile? host;

  @override
  Widget build(BuildContext context) {
    final name = host?.bestName ?? event.hostName;
    final positions = host?.positions ?? const <String>[];
    final pos = positions.isNotEmpty ? positions.first : '—';
    final pac =
        ((host?.credibilityScore ?? 60) * 0.6 + 55).clamp(40, 99).round();
    final dri =
        ((host?.credibilityScore ?? 60) * 0.5 + 50).clamp(40, 99).round();
    final age = host?.age;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(RadarRadius.sheet),
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(RadarRadius.card),
                child: RadarAvatar(name: name, url: host?.avatarUrl, size: 60),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: RadarTheme.radar,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    pos,
                    style: RadarType.capsTight.copyWith(
                      fontSize: 8,
                      color: RadarTheme.onAccent,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.heading(
                          19,
                          weight: FontWeight.w600,
                          color: const Color(0xFFF0FFEE),
                          height: 1.0,
                        ),
                      ),
                    ),
                    if (age != null) ...[
                      const SizedBox(width: 6),
                      RadarCaps('AGE $age',
                          size: 9, color: RadarTheme.textDim),
                    ],
                    const Spacer(),
                    Text(
                      '$pac PAC',
                      style: RadarType.metricMd.copyWith(
                        fontSize: 15,
                        color: RadarTheme.greenDeep,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    MetricChip(
                        code: 'DRI', value: '$dri', accent: RadarTheme.info),
                    MetricChip(
                      code: 'CRED',
                      value: (host?.credibilityScore ?? 0).toStringAsFixed(0),
                      accent: RadarTheme.radar,
                    ),
                    MetricChip(
                      code: 'FORM',
                      value: (host?.rating ?? 0).toStringAsFixed(1),
                      accent: RadarTheme.goldBright,
                    ),
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

class _AccessProtocol extends StatelessWidget {
  const _AccessProtocol({required this.event});

  final RadarEvent event;

  @override
  Widget build(BuildContext context) {
    final text = (event.description ?? '').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(RadarRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 17, color: RadarTheme.cyanDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadarCaps(
                  'PITCHSIDE ACCESS PROTOCOL',
                  size: 9.5,
                  color: RadarTheme.cyanDeep,
                  tracking: 0.9,
                ),
                const SizedBox(height: 3),
                Text(
                  text.isEmpty
                      ? 'Venue instructions are shared by the host after registration. Bring club scout accreditation to reception.'
                      : text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.bodySm.copyWith(
                    fontSize: 11.5,
                    height: 1.35,
                    color: RadarTheme.textDim,
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

class _ScoutPresence extends StatelessWidget {
  const _ScoutPresence({required this.event, required this.trusted});

  final RadarEvent event;
  final bool trusted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(RadarRadius.card),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 24,
            child: Stack(
              children: [
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left: i * 11,
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: RadarTheme.panel,
                        shape: BoxShape.circle,
                      ),
                      child: RadarAvatar(
                        name: trusted ? 'WH' : 'RA',
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${event.attendingCount} Scouts Checked In',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RadarType.bodySm.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: RadarTheme.textPrimary,
              ),
            ),
          ),
          RadarCaps(
            trusted ? 'WEST HAM • BRENTFORD' : 'AREA ONLY',
            size: 8,
            color: RadarTheme.textFaint,
            tracking: 0.7,
          ),
        ],
      ),
    );
  }
}

class _EmptyIntel extends StatelessWidget {
  const _EmptyIntel({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.radar, size: 34, color: RadarTheme.textFaint),
          const SizedBox(height: 8),
          Text(
            'No live pitches match this filter yet.',
            style: RadarType.bodySm.copyWith(color: RadarTheme.textDim),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onOpen, child: const Text('Open the bounty board')),
        ],
      ),
    );
  }
}

String _drive(int km) => '${math.max(1, (km * 2.5).round())} mins drive';
