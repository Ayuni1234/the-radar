import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/enums.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';
import '../state/radar_providers.dart';
import 'event_detail_screen.dart';
import 'player_cv_screen.dart';
import 'profiles_screen.dart' show CredibilityBar;
import 'radar_theme.dart';
import 'shell.dart';

/// Global Search & Advanced Filter — the discovery interface for scouts,
/// club officials and agents. One query spans the talent directory and the
/// event feed, with savable criteria for active scouting windows.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  String _text = '';
  Set<String> _positions = {};
  AgeBracket? _ageBracket;
  String? _country;
  String? _city;
  String? _foot;
  double _minCredibility = 0;
  Set<RadarEventType> _eventTypes = {};
  bool _playersScope = true;
  bool _eventsScope = true;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() => _text = _textCtrl.text));
    _cityCtrl.addListener(() => setState(() => _city = _cityCtrl.text.trim()));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  GlobalSearchQuery get _query => GlobalSearchQuery(
        text: _text,
        positions: _positions,
        ageBracket: _ageBracket,
        country: _country,
        city: _city,
        dominantFoot: _foot,
        minCredibility: _minCredibility,
        eventTypes: _eventTypes,
        playersScope: _playersScope,
        eventsScope: _eventsScope,
      );

  bool get _hasCriteria {
    final q = _query;
    return q.text.isNotEmpty ||
        q.positions.isNotEmpty ||
        q.ageBracket != null ||
        q.country != null ||
        (q.city != null && q.city!.isNotEmpty) ||
        q.dominantFoot != null ||
        q.minCredibility > 0 ||
        q.eventTypes.isNotEmpty;
  }

  void _applyQuery(GlobalSearchQuery q) {
    setState(() {
      _textCtrl.text = q.text;
      _text = q.text;
      _positions = Set.of(q.positions);
      _ageBracket = q.ageBracket;
      _country = q.country;
      _cityCtrl.text = q.city ?? '';
      _city = q.city;
      _foot = q.dominantFoot;
      _minCredibility = q.minCredibility;
      _eventTypes = Set.of(q.eventTypes);
      _playersScope = q.playersScope;
      _eventsScope = q.eventsScope;
    });
  }

  void _reset() {
    setState(() {
      _textCtrl.clear();
      _cityCtrl.clear();
      _positions = {};
      _ageBracket = null;
      _country = null;
      _city = null;
      _foot = null;
      _minCredibility = 0;
      _eventTypes = {};
      _playersScope = true;
      _eventsScope = true;
    });
  }

  Future<void> _saveSearch() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: RadarTheme.panel,
          title: const Text('Save this search'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              hintText: 'e.g. U17 left-footed CAMs',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty || !mounted) return;
    ref.read(savedSearchesProvider.notifier).save(name, _query);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Saved “$name” — apply it from the presets row.'),
      ));
    }
  }

  // -- Matching ------------------------------------------------------------

  List<UserProfile> _matchingPlayers(List<UserProfile> all) {
    final q = _query;
    final t = q.text.toLowerCase();
    return all.where((p) {
      if (p.role != UserRole.player) return false;
      if (t.isNotEmpty) {
        final haystack =
            '${p.bestName} ${p.username} ${p.bio ?? ''} ${p.clubAffiliation ?? ''} '
                    '${p.city ?? ''} ${p.country ?? ''} ${p.positions.join(' ')}'
                .toLowerCase();
        if (!haystack.contains(t)) return false;
      }
      if (q.positions.isNotEmpty &&
          !p.positions.any(q.positions.contains)) {
        return false;
      }
      if (q.ageBracket != null) {
        final age = p.age;
        if (age == null ||
            age < q.ageBracket!.min ||
            age > q.ageBracket!.max) {
          return false;
        }
      }
      if (q.country != null &&
          (p.country ?? '').toLowerCase() != q.country!.toLowerCase()) {
        return false;
      }
      if (q.city != null &&
          q.city!.isNotEmpty &&
          !(p.city ?? '').toLowerCase().contains(q.city!.toLowerCase())) {
        return false;
      }
      if (q.dominantFoot != null &&
          (p.dominantFoot ?? '').toLowerCase() != q.dominantFoot) {
        return false;
      }
      if (q.minCredibility > 0 && p.credibilityScore < q.minCredibility) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.credibilityScore.compareTo(a.credibilityScore));
  }

  List<RadarEvent> _matchingEvents(List<RadarEvent> all) {
    final q = _query;
    final t = q.text.toLowerCase();
    final now = DateTime.now();
    return all.where((e) {
      if (e.endsAt.isBefore(now)) return false;
      if (q.eventTypes.isNotEmpty && !q.eventTypes.contains(e.type)) {
        return false;
      }
      if (t.isNotEmpty) {
        final haystack =
            '${e.title} ${e.description ?? ''} ${e.areaName ?? ''} ${e.venueName ?? ''} ${e.hostName}'
                .toLowerCase();
        if (!haystack.contains(t)) return false;
      }
      if (q.ageBracket != null &&
          !q.ageBracket!.matches(e.minAge, e.maxAge)) {
        return false;
      }
      if (q.positions.isNotEmpty &&
          !e.positionsRequired.any(q.positions.contains)) {
        return false;
      }
      if (q.city != null &&
          q.city!.isNotEmpty &&
          !(e.areaName ?? '').toLowerCase().contains(q.city!.toLowerCase())) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];
    final saved = ref.watch(savedSearchesProvider);
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final crossAxis = switch (size) {
      WindowSize.compact => 1,
      WindowSize.medium => 2,
      WindowSize.expanded => 3,
    };

    final players = _playersScope ? _matchingPlayers(profiles) : const <UserProfile>[];
    final eventsList = _eventsScope ? _matchingEvents(events) : const <RadarEvent>[];
    final countries = profiles
        .map((p) => p.country)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: const Text('Global search',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Save this search',
            onPressed: _hasCriteria ? _saveSearch : null,
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Clear all filters',
            onPressed: _hasCriteria ? _reset : null,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          // Multi-criteria search input.
          TextField(
            key: const ValueKey('global-search-field'),
            controller: _textCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 17),
                      onPressed: () => _textCtrl.clear(),
                    ),
              hintText: 'Search players, positions, keywords, events…',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),

          // Saved filters & quick presets.
          _PresetsRow(
            saved: saved,
            onApply: _applyQuery,
            onRemove: (id) =>
                ref.read(savedSearchesProvider.notifier).remove(id),
          ),
          const SizedBox(height: 12),

          // Scope toggle.
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true, icon: Icon(Icons.groups, size: 16), label: Text('Players')),
              ButtonSegment(
                  value: false, icon: Icon(Icons.event, size: 16), label: Text('Events')),
            ],
            selected: {
              if (_playersScope && !_eventsScope) true,
              if (_eventsScope && !_playersScope) false,
            },
            emptySelectionAllowed: true,
            onSelectionChanged: (s) => setState(() {
              _playersScope = s.contains(true);
              _eventsScope = s.contains(false);
            }),
          ),
          const SizedBox(height: 12),

          // Advanced filters.
          _FilterPanel(
            positions: _positions,
            ageBracket: _ageBracket,
            country: _country,
            countries: countries,
            cityCtrl: _cityCtrl,
            foot: _foot,
            minCredibility: _minCredibility,
            eventTypes: _eventTypes,
            showEventTypes: _eventsScope,
            onChanged: (positions, bracket, country, foot, cred, types) =>
                setState(() {
              _positions = positions;
              _ageBracket = bracket;
              _country = country;
              _foot = foot;
              _minCredibility = cred;
              _eventTypes = types;
            }),
          ),
          const SizedBox(height: 14),

          // Instant results.
          if (!_playersScope && !_eventsScope)
            const _EmptyScope()
          else ...[
            Row(children: [
              Text(
                _resultsLabel(players.length, eventsList.length),
                style:  TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: RadarTheme.textDim),
              ),
              const Spacer(),
              if (_hasCriteria)
                 InfoPill(
                    icon: Icons.filter_alt,
                    label: 'Filtered',
                    color: RadarTheme.radar),
            ]),
            const SizedBox(height: 10),
            if (_playersScope && players.isEmpty && eventsList.isEmpty)
              _NoResults(onReset: _reset),
            if (_playersScope)
              GridView.count(
                crossAxisCount: crossAxis,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 3.4,
                children: [
                  for (final p in players)
                    _PlayerResultCard(
                      profile: p,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlayerCvScreen(profile: p),
                        ),
                      ),
                    ),
                ],
              ),
            if (_eventsScope && eventsList.isNotEmpty) ...[
              if (_playersScope && players.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 10),
                  child: SectionHeader('Matching events'),
                ),
              GridView.count(
                crossAxisCount: crossAxis,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 3.4,
                children: [
                  for (final e in eventsList)
                    _EventResultCard(
                      event: e,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EventDetailScreen(event: e),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _resultsLabel(int players, int events) {
    final parts = <String>[];
    if (_playersScope) parts.add('$players player${players == 1 ? '' : 's'}');
    if (_eventsScope) parts.add('$events event${events == 1 ? '' : 's'}');
    return parts.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// Saved presets row
// ---------------------------------------------------------------------------

class _PresetsRow extends StatelessWidget {
  const _PresetsRow({
    required this.saved,
    required this.onApply,
    required this.onRemove,
  });

  final List<SavedSearch> saved;
  final ValueChanged<GlobalSearchQuery> onApply;
  final ValueChanged<String> onRemove;

  static const _quickPresets = <(String, GlobalSearchQuery)>[
    (
      'U17 talents',
      GlobalSearchQuery(
          ageBracket: AgeBracket.u17, playersScope: true, eventsScope: false),
    ),
    (
      'Open-age attackers',
      GlobalSearchQuery(
        positions: {'LW', 'RW', 'ST'},
        ageBracket: AgeBracket.open,
        playersScope: true,
        eventsScope: false,
      ),
    ),
    (
      'High-credibility pros',
      GlobalSearchQuery(
          minCredibility: 70, playersScope: true, eventsScope: false),
    ),
    (
      'Upcoming trials',
      GlobalSearchQuery(
        eventTypes: {RadarEventType.trial},
        playersScope: false,
        eventsScope: true,
      ),
    ),
    (
      'Left-footed players',
      GlobalSearchQuery(
          dominantFoot: 'left', playersScope: true, eventsScope: false),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (name, query) in _quickPresets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar:  Icon(Icons.flash_on, size: 14, color: RadarTheme.gold),
                label: Text(name, style: const TextStyle(fontSize: 12)),
                onPressed: () => onApply(query),
              ),
            ),
          for (final s in saved)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar:  Icon(Icons.bookmark, size: 14, color: RadarTheme.pi),
                label: Text(s.name, style: const TextStyle(fontSize: 12)),
                onPressed: () => onApply(s.query),
                onDeleted: () => onRemove(s.id),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Advanced filter panel
// ---------------------------------------------------------------------------

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.positions,
    required this.ageBracket,
    required this.country,
    required this.countries,
    required this.cityCtrl,
    required this.foot,
    required this.minCredibility,
    required this.eventTypes,
    required this.showEventTypes,
    required this.onChanged,
  });

  final Set<String> positions;
  final AgeBracket? ageBracket;
  final String? country;
  final List<String> countries;
  final TextEditingController cityCtrl;
  final String? foot;
  final double minCredibility;
  final Set<RadarEventType> eventTypes;
  final bool showEventTypes;
  final void Function(Set<String>, AgeBracket?, String?, String?, double,
      Set<RadarEventType>) onChanged;

  @override
  Widget build(BuildContext context) {
    void push({
      Set<String>? pos,
      AgeBracket? bracket,
      String? ctry,
      String? ft,
      double? cred,
      Set<RadarEventType>? types,
    }) =>
        onChanged(
          pos ?? positions,
          bracket ?? ageBracket,
          ctry ?? country,
          ft ?? foot,
          cred ?? minCredibility,
          types ?? eventTypes,
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.tune, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Text('Advanced filters',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),

        Text('POSITIONS',
            style:  TextStyle(
                fontSize: 10.5, letterSpacing: 1, color: RadarTheme.textDim)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final p in kFootballPositions)
              FilterChip(
                label: Text(p, style: const TextStyle(fontSize: 11.5)),
                selected: positions.contains(p),
                onSelected: (on) {
                  final next = Set.of(positions);
                  on ? next.add(p) : next.remove(p);
                  push(pos: next);
                },
              ),
          ],
        ),
        const SizedBox(height: 12),

        Text('AGE BRACKET',
            style:  TextStyle(
                fontSize: 10.5, letterSpacing: 1, color: RadarTheme.textDim)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final b in AgeBracket.values)
              ChoiceChip(
                label: Text(b.label, style: const TextStyle(fontSize: 11.5)),
                selected: ageBracket == b,
                onSelected: (on) => push(bracket: on ? b : null),
              ),
          ],
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: country,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Regional base (country)',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in countries)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => push(ctry: v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: cityCtrl,
              decoration: const InputDecoration(
                labelText: 'City / area',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        Row(children: [
           Text('Dominant foot',
              style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim)),
          const SizedBox(width: 10),
          ChoiceChip(
            label: const Text('Left', style: TextStyle(fontSize: 11.5)),
            selected: foot == 'left',
            onSelected: (on) => push(ft: on ? 'left' : null),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Right', style: TextStyle(fontSize: 11.5)),
            selected: foot == 'right',
            onSelected: (on) => push(ft: on ? 'right' : null),
          ),
          const Spacer(),
          Text('Skill level: ${minCredibility.round()}+',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        Slider(
          value: minCredibility,
          max: 100,
          divisions: 10,
          label: minCredibility == 0 ? 'Any' : '${minCredibility.round()}+',
          activeColor: RadarTheme.radar,
          onChanged: (v) => push(cred: v),
        ),

        if (showEventTypes) ...[
          const SizedBox(height: 4),
          Text('EVENT TYPES',
              style:  TextStyle(
                  fontSize: 10.5, letterSpacing: 1, color: RadarTheme.textDim)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final t in RadarEventType.values)
                FilterChip(
                  avatar: Icon(t.icon, size: 13, color: RadarTheme.radar),
                  label: Text(t.label, style: const TextStyle(fontSize: 11.5)),
                  selected: eventTypes.contains(t),
                  onSelected: (on) {
                    final next = Set.of(eventTypes);
                    on ? next.add(t) : next.remove(t);
                    push(types: next);
                  },
                ),
            ],
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Result cards
// ---------------------------------------------------------------------------

class _PlayerResultCard extends StatelessWidget {
  const _PlayerResultCard({required this.profile, required this.onOpen});

  final UserProfile profile;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: RadarTheme.pi.withValues(alpha: 0.2),
            child: Text(
              p.bestName.isNotEmpty ? p.bestName[0].toUpperCase() : '?',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(p.bestName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  if (p.kycVerified) ...[
                    const SizedBox(width: 5),
                     Icon(Icons.verified,
                        size: 14, color: RadarTheme.radar),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    if (p.positions.isNotEmpty) p.positions.join(' · '),
                    if (p.age != null) '~${p.age}y',
                    if (p.dominantFoot != null) '${p.dominantFoot}-footed',
                    if (p.country != null) p.country!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                      fontSize: 11.5, color: RadarTheme.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CredibilityBar(score: p.credibilityScore),
        ]),
      ),
    );
  }
}

class _EventResultCard extends StatelessWidget {
  const _EventResultCard({required this.event, required this.onOpen});

  final RadarEvent event;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: RadarTheme.radar.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(e.type.icon, size: 18, color: RadarTheme.radar),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('E d MMM · HH:mm').format(e.startsAt)} · ${e.safeLocationLabel()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                      fontSize: 11.5, color: RadarTheme.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (e.isBoosted)
             Icon(Icons.bolt, size: 16, color: RadarTheme.gold)
          else if (e.isMinorProtected)
             Icon(Icons.shield_outlined, size: 15, color: RadarTheme.info),
        ]),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(children: [
         Icon(Icons.search_off, size: 30, color: RadarTheme.textDim),
        const SizedBox(height: 10),
        const Text('No matches for these criteria',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
         Text(
          'Try widening the age bracket, lowering the skill level, '
          'or clearing the region.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: onReset, child: const Text('Clear filters')),
      ]),
    );
  }
}

class _EmptyScope extends StatelessWidget {
  const _EmptyScope();

  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Text(
          'Pick a scope — Players, Events, or both — to start searching.',
          style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
        ),
      ),
    );
  }
}
