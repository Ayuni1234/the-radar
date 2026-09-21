import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/enums.dart';
import '../models/radar_event.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Publish-a-event flow for organizers, scouts, club & academy directors.
///
/// Mirrors the spec's Event Creation & Publishing page:
///  1. Classification & metadata (type, title, description, age brackets)
///  2. Precision location (pin drop → coordinates + geohash area label, with
///     automatic minor-safety downgrade when the event targets minors)
///  3. Capacity & position requirements
///  4. Instant publication through the RLS-scoped repository path — the
///     database trigger `enforce_minor_safety` remains the authoritative gate.
class EventComposerScreen extends ConsumerStatefulWidget {
  const EventComposerScreen({super.key});

  /// Opens the composer as a full-screen dialog. Returns true if published.
  static Future<bool> show(BuildContext context) async {
    final published = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const EventComposerScreen(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
    return published ?? false;
  }

  @override
  ConsumerState<EventComposerScreen> createState() =>
      _EventComposerScreenState();
}

class _EventComposerScreenState extends ConsumerState<EventComposerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();

  RadarEventType _type = RadarEventType.trial;
  final Set<AgeBracket> _brackets = {};
  int? _capacity;
  final Set<String> _positions = {};
  DateTime _start = DateTime.now().add(const Duration(days: 3, hours: 2));
  Duration _duration = const Duration(hours: 2);

  // Location state.
  double _lat = 51.5072;
  double _lng = -0.1276;
  String _areaName = 'Central London';
  String? _venueName;
  bool _dropMode = false;

  bool get _targetsMinors => _brackets.any((b) => b != AgeBracket.open);

  /// The precision this event will be stored with. The minor-safety trigger
  /// enforces the same rule server-side; mirroring it here keeps the UI
  /// honest about what the viewer will see.
  GeoPrecision get _effectivePrecision =>
      _targetsMinors ? GeoPrecision.approximate : GeoPrecision.exact;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _venueCtrl.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      _titleCtrl.text.trim().isNotEmpty &&
      _areaName.trim().isNotEmpty &&
      _end.isAfter(_start);

  DateTime get _end => _start.add(_duration);

  Future<void> _publish() async {
    if (!(_formKey.currentState?.validate() ?? false) || !_canPublish) return;

    final session = ref.read(sessionProvider);
    final event = RadarEvent(
      id: _uuid(),
      type: _type,
      title: _titleCtrl.text.trim(),
      hostProfileId: session?.profileId ?? 'demo-host',
      hostName: session?.username ?? 'Unknown host',
      latitude: _lat,
      longitude: _lng,
      startsAt: _start,
      endsAt: _end,
      precision: _effectivePrecision,
      venueName: _venueName?.trim().isEmpty == true ? null : _venueName?.trim(),
      areaName: _areaName.trim(),
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      capacity: _capacity,
      minAge: _brackets.isEmpty ? null : _brackets.map((b) => b.min).reduce((a, b) => a < b ? a : b),
      maxAge: _brackets.isEmpty ? null : _brackets.map((b) => b.max).reduce((a, b) => a > b ? a : b),
      positionsRequired: _positions.toList(),
      isMinorProtected: _targetsMinors,
    );

    final outcome =
        await ref.read(radarEventsProvider.notifier).createEvent(event);
    if (!mounted) return;
    if (outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHigh,
        content: Row(children: [
          const Icon(Icons.publish, color: RadarTheme.radar, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '“${event.title}” is live on the Radar',
              style: const TextStyle(color: RadarTheme.textPrimary),
            ),
          ),
        ]),
      ));
      Navigator.of(context).pop(true);
    } else {
      final queued = outcome.queued;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.alert,
        content: Text(queued
            ? '${outcome.message ?? 'Publish failed'} — saved and will retry automatically'
            : 'Could not publish: ${outcome.message ?? 'unknown error'}'),
        action: queued
            ? null
            : SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: () { _publish(); }),
      ));
      if (queued) Navigator.of(context).pop(false);
      // Hard rejections keep the form open so the reason can be read and
      // the draft fixed (e.g. a validation rule the server rejected).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: const Text('Publish an event'),
        actions: [
          Padding(
            key: const ValueKey('publish-event'),
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _canPublish ? _publish : null,
              icon: const Icon(Icons.rocket_launch, size: 18),
              label: const Text('Publish'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _Section(
              icon: Icons.category_outlined,
              title: 'Classification & metadata',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in RadarEventType.values)
                        _TypeChip(
                          type: t,
                          selected: _type == t,
                          onTap: () => setState(() => _type = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const ValueKey('event-title'),
                    controller: _titleCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Event title',
                      hintText: 'e.g. Open trial — U17 wingers',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'A title is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText:
                          'Format, what scouts will evaluate, what to bring…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Target age brackets',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: RadarTheme.textDim)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in AgeBracket.values)
                        FilterChip(
                          label: Text(b.label),
                          selected: _brackets.contains(b),
                          onSelected: (on) => setState(() =>
                              on ? _brackets.add(b) : _brackets.remove(b)),
                        ),
                    ],
                  ),
                  if (_targetsMinors) ...[
                    const SizedBox(height: 10),
                    const _MinorSafetyNote(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              icon: Icons.location_on_outlined,
              title: 'Precision location',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PinPicker(
                          lat: _lat,
                          lng: _lng,
                          dropMode: _dropMode,
                          onDrop: (lat, lng) => setState(() {
                            _lat = lat;
                            _lng = lng;
                            _dropMode = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                setState(() => _dropMode = !_dropMode),
                            icon: Icon(_dropMode
                                ? Icons.close
                                : Icons.ads_click),
                            label: Text(_dropMode
                                ? 'Cancel pin'
                                : 'Drop pin'),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: RadarTheme.textDim,
                                fontFeatures: []),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const ValueKey('event-area'),
                    initialValue: _areaName,
                    onChanged: (v) => setState(() => _areaName = v),
                    decoration: const InputDecoration(
                      labelText: 'Area label (geohash region)',
                      helperText:
                          'Coarse public label — the only location minors ever see.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'An area label is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _venueCtrl,
                    decoration: InputDecoration(
                      labelText: 'Venue name (optional)',
                      helperText: _targetsMinors
                          ? 'Hidden automatically — minor-protected events expose the area only.'
                          : 'Shown only when location precision is exact.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InfoPill(
                    icon: _targetsMinors ? Icons.shield : Icons.lock_open,
                    label: _targetsMinors
                        ? 'Minor-protected: fenced to approximate area'
                        : 'Exact precision: venue visible to viewers',
                    color: _targetsMinors ? RadarTheme.info : RadarTheme.radar,
                    tooltip:
                        'Enforced again by the enforce_minor_safety trigger at insert time.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              icon: Icons.groups_2_outlined,
              title: 'Capacity & role requirements',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Participant limit'),
                      const Spacer(),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 12, label: Text('12')),
                          ButtonSegment(value: 24, label: Text('24')),
                          ButtonSegment(value: 48, label: Text('48')),
                          ButtonSegment(value: 100, label: Text('100')),
                        ],
                        selected: {_capacity ?? 24},
                        onSelectionChanged: (s) =>
                            setState(() => _capacity = s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Positions being scouted',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: RadarTheme.textDim)),
                  const SizedBox(height: 4),
                  Text('Leave empty for open-to-all sessions.',
                      style: const TextStyle(
                          fontSize: 11.5, color: RadarTheme.textDim)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final p in kFootballPositions)
                        FilterChip(
                          label: Text(p),
                          selected: _positions.contains(p),
                          onSelected: (on) => setState(
                              () => on ? _positions.add(p) : _positions.remove(p)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickStart,
                          icon: const Icon(Icons.event_outlined, size: 18),
                          label: Text(DateFormat('E d MMM · HH:mm')
                              .format(_start)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDuration,
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(_duration.inHours >= 1
                              ? '${_duration.inHours}h'
                              : '${_duration.inMinutes}m'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// RFC-4122 v4 id — the `radar_events.id` column is a uuid primary key.
  String _uuid() {
    final r = DateTime.now().microsecondsSinceEpoch;
    String hex4(int seed) =>
        ((r ^ seed * 2654435761) & 0xffff).toRadixString(16).padLeft(4, '0');
    final v = hex4(1) + hex4(2) + hex4(3) + hex4(4) + hex4(5) + hex4(6) +
        hex4(7) + hex4(8);
    return '${v.substring(0, 8)}-${v.substring(8, 12)}-4${v.substring(13, 16)}-'
        'a${v.substring(17, 20)}-${v.substring(20, 32)}';
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickDuration() async {
    final picked = await showDialog<Duration>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Duration'),
        children: [
          for (final d in const [
            Duration(hours: 1),
            Duration(hours: 2),
            Duration(hours: 3),
            Duration(hours: 5),
            Duration(hours: 8),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: Text('${d.inHours} hours'),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _duration = picked);
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: RadarTheme.radar),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final RadarEventType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = selected ? RadarTheme.radar : RadarTheme.stroke;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? RadarTheme.radar.withValues(alpha: 0.14)
              : RadarTheme.panelHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c, width: selected ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(type.icon,
              size: 16, color: selected ? RadarTheme.radar : RadarTheme.textDim),
          const SizedBox(width: 7),
          Text(type.label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? RadarTheme.radar
                      : RadarTheme.textPrimary)),
        ]),
      ),
    );
  }
}

class _MinorSafetyNote extends StatelessWidget {
  const _MinorSafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RadarTheme.info.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 17, color: RadarTheme.info),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Minor-protected event: the venue name is stripped and the pin is '
            'fenced to the coarse area label by the database — players under '
            '18 see only the region until guardians grant event consent.',
            style: TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ]),
    );
  }
}

/// Simplified interactive pin-drop surface (tap to place the marker).
class _PinPicker extends StatelessWidget {
  const _PinPicker({
    required this.lat,
    required this.lng,
    required this.dropMode,
    required this.onDrop,
  });

  final double lat;
  final double lng;
  final bool dropMode;
  final void Function(double lat, double lng) onDrop;

  @override
  Widget build(BuildContext context) {
    // Deterministic pseudo-projection so the marker tracks drags/taps
    // without pulling in a full map dependency.
    Offset project(double lat, double lng) => Offset(
          ((lng + 180) / 360) * 1000,
          ((90 - lat) / 180) * 500,
        );
    final p = project(lat, lng);

    return GestureDetector(
      onTapUp: dropMode
          ? (d) {
              final box = context.findRenderObject() as RenderBox;
              final local = d.localPosition;
              final size = box.size;
              onDrop(
                90 - (local.dy / size.height) * 180,
                (local.dx / size.width) * 360 - 180,
              );
            }
          : null,
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          color: RadarTheme.panelHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dropMode ? RadarTheme.radar : RadarTheme.stroke,
            width: dropMode ? 1.4 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(painter: _GridPainter()),
            ),
            Positioned(
              left: (p.dx / 1000).clamp(0.02, 0.98) *
                  MediaQuery.sizeOf(context).width *
                  0.0, // placeholder, replaced below
              child: const SizedBox.shrink(),
            ),
            LayoutBuilder(builder: (context, constraints) {
              final x = (p.dx / 1000) * constraints.maxWidth;
              final y = (p.dy / 500) * constraints.maxHeight;
              return Stack(children: [
                Positioned(
                  left: (x - 12).clamp(0.0, constraints.maxWidth - 24),
                  top: (y - 24).clamp(0.0, constraints.maxHeight - 28),
                  child: const Icon(Icons.location_on,
                      color: RadarTheme.radar, size: 24),
                ),
                if (dropMode)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          'Tap the map to place the pin',
                          style: TextStyle(
                              fontSize: 12, color: RadarTheme.textDim),
                        ),
                      ),
                    ),
                  ),
              ]);
            }),
          ]),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = RadarTheme.stroke.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    const step = 34.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Equator hint.
    final eq = Paint()
      ..color = RadarTheme.radar.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), eq);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
