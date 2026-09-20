import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/radar_repository.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'radar_theme.dart';
import 'shell.dart' show SectionHeader;

/// Player Football CV editor — Module 1 of the product spec.
///
/// Captures the vital stats (positions, dominant foot, age band via birth
/// year, height), free-text CV and video highlight links. Saves through the
/// existing repository upsert path (RLS: own profile only).
class CvEditorScreen extends ConsumerStatefulWidget {
  const CvEditorScreen({super.key});

  @override
  ConsumerState<CvEditorScreen> createState() => _CvEditorScreenState();
}

class _CvEditorScreenState extends ConsumerState<CvEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cvCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _birthYearCtrl;
  late final TextEditingController _videoCtrl;

  late Set<String> _positions;
  late String? _dominantFoot;
  bool _saving = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    UserProfile? profile;
    if (profileId != null) {
      // Start from whatever the directory already has for this user.
      final profiles = ref.read(profilesProvider).value ?? const [];
      for (final p in profiles) {
        if (p.id == profileId) profile = p;
      }
    }
    profile ??= _fallbackProfile();

    _positions = Set.of(profile.positions);
    _dominantFoot = profile.dominantFoot;
    _cvCtrl = TextEditingController(text: profile.footballCv ?? '');
    _heightCtrl =
        TextEditingController(text: profile.heightCm?.toString() ?? '');
    _birthYearCtrl =
        TextEditingController(text: profile.birthYear?.toString() ?? '');
    _videoCtrl = TextEditingController();
  }

  UserProfile _fallbackProfile() {
    final session = ref.read(sessionProvider);
    return UserProfile(
      id: session?.profileId ?? 'local',
      piUid: session?.piUid ?? '',
      username: session?.username ?? 'player',
      role: session?.role ?? UserRole.player,
      credibilityScore: 10,
      kycVerified: session?.kycVerified ?? false,
      createdAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _cvCtrl.dispose();
    _heightCtrl.dispose();
    _birthYearCtrl.dispose();
    _videoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });

    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    UserProfile? base;
    if (profileId != null) {
      final profiles = ref.read(profilesProvider).value ?? const [];
      for (final p in profiles) {
        if (p.id == profileId) base = p;
      }
    }
    base ??= _fallbackProfile();

    final birthYear = int.tryParse(_birthYearCtrl.text.trim());
    final height = int.tryParse(_heightCtrl.text.trim());

    final updated = base.copyWith(
      positions: _positions.toList(),
      dominantFoot: _dominantFoot,
      birthYear: birthYear,
      heightCm: height,
      footballCv: _cvCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );

    final ok = await RadarRepository.instance.upsertProfile(updated);
    setState(() {
      _saving = false;
      _isError = !ok;
      _message = ok
          ? 'Football CV saved.'
          : 'Could not save — check your connection and try again.';
    });
  }

  Future<void> _addVideo() async {
    final url = _videoCtrl.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      setState(() => _message = 'Enter a full URL (https://…)');
      return;
    }
    setState(() {
      _videos.add(url);
      _videoCtrl.clear();
      _message = null;
    });
  }

  final List<String> _videos = <String>[];

  @override
  Widget build(BuildContext context) {
    final isPlayer = ref.watch(sessionProvider)?.role == UserRole.player;
    final wide = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SectionHeader('Football CV'),
            const Text(
              'Your vitals and career story — this is what scouts search '
              'and filter on. Keep it honest and specific.',
              style: TextStyle(color: RadarTheme.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            // Positions.
            const Text('Positions',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pos in kFootballPositions)
                  FilterChip(
                    label: Text(pos),
                    selected: _positions.contains(pos),
                    onSelected: (_) => setState(() {
                      if (!_positions.remove(pos)) _positions.add(pos);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              children: [
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(right: wide ? 10 : 0, bottom: wide ? 0 : 10),
                    child: DropdownButtonFormField<String>(
                      initialValue: _dominantFoot,
                      decoration: const InputDecoration(
                        labelText: 'Dominant foot',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'left', child: Text('Left')),
                        DropdownMenuItem(value: 'right', child: Text('Right')),
                      ],
                      onChanged: (v) => setState(() => _dominantFoot = v),
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(right: wide ? 10 : 0, bottom: wide ? 0 : 10),
                    child: TextFormField(
                      controller: _birthYearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Birth year',
                        hintText: 'e.g. 2008',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final y = int.tryParse(v ?? '');
                        if (v != null && v.isNotEmpty && (y == null || y < 1950 || y > DateTime.now().year)) {
                          return 'Enter a valid year';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                Flexible(
                  child: TextFormField(
                    controller: _heightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      hintText: 'e.g. 178',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final h = int.tryParse(v ?? '');
                      if (v != null && v.isNotEmpty && (h == null || h < 120 || h > 230)) {
                        return 'Enter a valid height';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _cvCtrl,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Career history & achievements',
                alignLabelWithHint: true,
                hintText: 'Clubs, leagues, honours, standout matches, coach references…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            // Video highlights.
            const SectionHeader('Video highlights'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _videoCtrl,
                    decoration: const InputDecoration(
                      hintText: 'https://youtube.com/watch?v=…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addVideo(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: _addVideo,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_videos.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final v in _videos)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.play_circle_outline,
                      color: RadarTheme.info),
                  title: Text(v, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _videos.remove(v)),
                  ),
                ),
            ],
            if (!isPlayer) ...[
              const SizedBox(height: 10),
              const InfoNote(
                icon: Icons.info_outline,
                text: 'Your account role is not Player — a football CV is most '
                    'relevant for players, but scouts can still list credentials here.',
              ),
            ],
            const SizedBox(height: 26),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _message!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _isError ? RadarTheme.alert : RadarTheme.radar,
                  ),
                ),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: RadarTheme.pi,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save Football CV'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class InfoNote extends StatelessWidget {
  const InfoNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: RadarTheme.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: RadarTheme.textDim)),
          ),
        ],
      ),
    );
  }
}
