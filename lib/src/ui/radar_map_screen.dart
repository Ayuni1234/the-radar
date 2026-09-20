import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';
import '../state/radar_providers.dart';
import 'event_composer_screen.dart';
import 'event_detail_screen.dart';
import 'profiles_screen.dart';
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
  String? _hoveredId;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(filteredEventsProvider);
    final eventsAsync = ref.watch(radarEventsProvider);
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final wide = size != WindowSize.compact;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: RadarTheme.radar, shape: BoxShape.circle),
            ).pulsing(),
            const SizedBox(width: 10),
            const Text('LIVE RADAR'),
            const SizedBox(width: 10),
            Text(
              '${events.length} active',
              style: const TextStyle(
                  fontSize: 12.5, color: RadarTheme.textDim, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
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
                    Expanded(flex: 3, child: _radarCanvas(events, wide)),
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
                  children: [
                    Expanded(child: _radarCanvas(events, wide)),
                    SizedBox(
                      height: 190,
                      child: _EventStrip(
                        events: events,
                        onSelect: (e) => _openEventSheet(context, e),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _radarCanvas(List<RadarEvent> events, bool wide) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: RadarCanvasPainterWidget(
                events: events,
                selectedId: _selected?.id,
                hoveredId: _hoveredId,
                onSelect: (e) => wide
                    ? setState(() => _selected = e)
                    : _openEventSheet(context, e),
                onHover: (id) => setState(() => _hoveredId = id),
              ),
            ),
            const Positioned(top: 14, left: 14, child: _FilterChips()),
            const Positioned(bottom: 14, right: 14, child: _Legend()),
          ],
        ),
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

// ---------------------------------------------------------------- canvas

class RadarCanvasPainterWidget extends StatefulWidget {
  const RadarCanvasPainterWidget({
    super.key,
    required this.events,
    required this.selectedId,
    required this.hoveredId,
    required this.onSelect,
    required this.onHover,
  });

  final List<RadarEvent> events;
  final String? selectedId;
  final String? hoveredId;
  final ValueChanged<RadarEvent> onSelect;
  final ValueChanged<String?> onHover;

  @override
  State<RadarCanvasPainterWidget> createState() =>
      _RadarCanvasPainterWidgetState();
}

class _RadarCanvasPainterWidgetState extends State<RadarCanvasPainterWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))
        ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) => widget.onHover(_hitTest(e.localPosition)),
      onExit: (PointerExitEvent _) => widget.onHover(null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final id = _hitTest(d.localPosition);
          if (id != null) {
            final match =
                widget.events.where((e) => e.id == id).firstOrNull;
            if (match != null) widget.onSelect(match);
          }
        },
        child: AnimatedBuilder(
          animation: _sweep,
          builder: (context, _) => CustomPaint(
            painter: _RadarPaint(
              sweepAngle: _sweep.value * 2 * math.pi,
              events: widget.events,
              selectedId: widget.selectedId,
              hoveredId: widget.hoveredId,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  String? _hitTest(Offset pos) {
    final size = context.size;
    if (size == null) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 24;
    for (final blip in _layout(widget.events, center, radius)) {
      if ((blip.$2 - pos).distance <= 18) return blip.$1.id;
    }
    return null;
  }
}

List<(RadarEvent, Offset)> _layout(
    List<RadarEvent> events, Offset center, double radius) {
  final result = <(RadarEvent, Offset)>[];
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    // Deterministic pseudo-geo layout: bearing & distance from longitude &
    // latitude so the layout is stable across rebuilds.
    final bearing = (e.longitude.abs() * 40) % 360;
    final distance = 0.35 + ((e.latitude.abs() * 13) % 55) / 100;
    final angle = bearing * math.pi / 180 - math.pi / 2;
    final r = radius * distance * (e.isBoosted ? 0.82 : 1.0);
    final offset = Offset(
      center.dx + math.cos(angle) * r,
      center.dy + math.sin(angle) * r,
    );
    result.add((e, offset));
  }
  return result;
}

class _RadarPaint extends CustomPainter {
  _RadarPaint({
    required this.sweepAngle,
    required this.events,
    required this.selectedId,
    required this.hoveredId,
  });

  final double sweepAngle;
  final List<RadarEvent> events;
  final String? selectedId;
  final String? hoveredId;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 24;

    // Concentric rings + cross hairs.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = RadarTheme.stroke.withValues(alpha: 0.55);
    for (final f in const [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawCircle(center, radius * f, ring);
    }
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), ring);
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), ring);

    // Sweep gradient.
    final sweepRect = Rect.fromCircle(center: center, radius: radius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          RadarTheme.radar.withValues(alpha: 0.0),
          RadarTheme.radar.withValues(alpha: 0.16),
          RadarTheme.radar.withValues(alpha: 0.30),
        ],
        stops: const [0.55, 0.85, 1.0],
        transform: GradientRotation(sweepAngle - math.pi / 2),
      ).createShader(sweepRect);
    canvas.drawCircle(center, radius, sweepPaint);

    // Center "you are here".
    final youAreHere = Paint()..color = RadarTheme.radar;
    canvas.drawCircle(center, 5, youAreHere);
    canvas.drawCircle(center, 10, youAreHere..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // Event blips.
    for (final (event, pos) in _layout(events, center, radius)) {
      final isSel = event.id == selectedId;
      final isHov = event.id == hoveredId;
      final color = switch (event.type) {
        RadarEventType.trial => RadarTheme.pi,
        RadarEventType.match => RadarTheme.radar,
        RadarEventType.tournament => RadarTheme.gold,
        RadarEventType.trainingSession => RadarTheme.info,
      };

      if (event.isBoosted) {
        canvas.drawCircle(
            pos, 15, Paint()..color = RadarTheme.gold.withValues(alpha: 0.14));
      }
      if (isSel || isHov) {
        canvas.drawCircle(
            pos, 20, Paint()..color = color.withValues(alpha: 0.14));
      }

      final blip = Paint()
        ..color = color.withValues(alpha: event.isLive ? 1 : 0.75);
      canvas.drawCircle(pos, isSel ? 8 : 6, blip);
      canvas.drawCircle(
          pos, 12, Paint()..color = color.withValues(alpha: 0.18));

      if (event.isMinorProtected) {
        final shield = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = RadarTheme.textDim;
        canvas.drawCircle(pos, 13, shield);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPaint old) =>
      old.sweepAngle != sweepAngle ||
      old.selectedId != selectedId ||
      old.hoveredId != hoveredId ||
      old.events != events;
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

class _Legend extends StatelessWidget {
  const _Legend();

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
            const Text('Match', style: _legendStyle),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            dot(RadarTheme.pi),
            const SizedBox(width: 6),
            const Text('Trial', style: _legendStyle),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            dot(RadarTheme.gold),
            const SizedBox(width: 6),
            const Text('Tournament', style: _legendStyle),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            dot(RadarTheme.info),
            const SizedBox(width: 6),
            const Text('Training', style: _legendStyle),
          ]),
        ],
      ),
    );
  }

  static const _legendStyle = TextStyle(fontSize: 10.5, color: RadarTheme.textDim);
}

// ----------------------------------------------------------------- panels

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

class _EventStrip extends StatelessWidget {
  const _EventStrip({required this.events, required this.onSelect});

  final List<RadarEvent> events;
  final ValueChanged<RadarEvent> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      itemCount: events.length,
      itemBuilder: (context, i) => SizedBox(
        width: 280,
        child: _EventCard(event: events[i], selected: false, onTap: () => onSelect(events[i])),
      ),
    );
  }
}

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
                  Icon(event.type.icon,
                      size: 15, color: RadarTheme.radar),
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

extension _Pulse on Widget {
  Widget pulsing() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, v, child) =>
          Opacity(opacity: v, child: Transform.scale(scale: v, child: child)),
      onEnd: () {},
    );
  }
}
