import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../state/auth_controller.dart';
import 'radar_theme.dart';
import 'shell.dart' show InfoPill, RadarMark;

/// Guided onboarding for newly authenticated users.
///
/// Three steps:
///   1. Role assignment — the user's classification in the football ecosystem.
///   2. Regional & demographic setup — country/city anchor + safeguarding.
///   3. Initial profile — display name, bio, baseline credentials.
///
/// Answers persist to the user's `profiles` row and stamp `onboarded_at`,
/// which releases the app shell.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;

  // Step 1 — role.
  UserRole? _role;

  // Step 2 — region & demographics.
  final _countryCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _isMinor = false;

  // Step 3 — profile.
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  @override
  void dispose() {
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _role != null;
      case 1:
        return _countryCtrl.text.trim().isNotEmpty;
      default:
        return _nameCtrl.text.trim().isNotEmpty;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).finishOnboarding(
            role: _role ?? UserRole.player,
            displayName: _nameCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            country: _countryCtrl.text.trim(),
            city: _cityCtrl.text.trim(),
            isMinor: _isMinor,
          );
      // RadarApp watches authProvider and routes to HomeShell on
      // AuthSignedIn; nothing to navigate manually.
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save your profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 720;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.9),
            radius: 1.4,
            colors: [Color(0xFF14203A), RadarTheme.ink],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 760 : 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: RadarMark(size: 44)),
                    const SizedBox(height: 14),
                    Text(
                      _titles[_step],
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitles[_step],
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: RadarTheme.textDim, fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                    _ProgressDots(step: _step),
                    const SizedBox(height: 22),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _step == 0
                          ? _RoleStep(
                              key: const ValueKey(0),
                              selected: _role,
                              onSelect: (r) => setState(() => _role = r),
                            )
                          : _step == 1
                              ? _RegionStep(
                                  key: const ValueKey(1),
                                  countryCtrl: _countryCtrl,
                                  cityCtrl: _cityCtrl,
                                  isMinor: _isMinor,
                                  onMinorChanged: (v) => setState(() => _isMinor = v),
                                  onTextChanged: () => setState(() {}),
                                )
                              : _ProfileStep(
                                  key: const ValueKey(2),
                                  nameCtrl: _nameCtrl,
                                  bioCtrl: _bioCtrl,
                                  role: _role,
                                  onTextChanged: () => setState(() {}),
                                ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(color: RadarTheme.alert, fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        if (_step > 0)
                          OutlinedButton(
                            onPressed: _saving ? null : () => setState(() => _step--),
                            child: const Text('Back'),
                          ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: RadarTheme.pi,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: !_canContinue || _saving
                              ? null
                              : () {
                                  if (_step < 2) {
                                    setState(() {
                                      _step++;
                                      _error = null;
                                    });
                                  } else {
                                    _submit();
                                  }
                                },
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(_step < 2 ? Icons.arrow_forward : Icons.check),
                          label: Text(
                            _saving
                                ? 'Saving…'
                                : _step < 2
                                    ? 'Continue'
                                    : 'Enter The Radar',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _titles = <String>[
  'Join The Radar',
  'Where do you scout for talent?',
  'Set up your profile',
];

const _subtitles = <String>[
  'Pick your role in the football ecosystem — it shapes what you see and do.',
  'We anchor you to local sessions, trials and regional talent pools.',
  'A display name and short bio help others find and trust you.',
];

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: i == step ? 34 : 12,
            height: 6,
            decoration: BoxDecoration(
              color: i <= step ? RadarTheme.pi : RadarTheme.panelHigh,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- step 1: role

const _roleDescriptions = <UserRole, String>{
  UserRole.player: 'Build your CV, get seen by scouts, join sessions and trials.',
  UserRole.scout: 'Discover talent, file structured reports and attend events.',
  UserRole.club: 'Post trials, track targets and manage your scouting team.',
  UserRole.academy: 'Showcase your players and host sessions on the radar.',
  UserRole.agent: 'Represent players, connect clubs and manage transitions.',
  UserRole.parent: 'Follow your child’s journey with privacy-first safeguards.',
};

class _RoleStep extends StatelessWidget {
  const _RoleStep({super.key, required this.selected, required this.onSelect});

  final UserRole? selected;
  final ValueChanged<UserRole> onSelect;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 720;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 3 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: wide ? 1.35 : 1.15,
      ),
      children: [
        for (final role in UserRole.values)
          _RoleCard(
            role: role,
            selected: selected == role,
            onTap: () => onSelect(role),
          ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? RadarTheme.pi : RadarTheme.stroke;
    return Material(
      color: selected ? RadarTheme.pi.withValues(alpha: 0.10) : RadarTheme.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(role.icon, size: 22, color: selected ? RadarTheme.pi : RadarTheme.textDim),
              const SizedBox(height: 8),
              Text(
                role.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? RadarTheme.textPrimary : RadarTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  _roleDescriptions[role]!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: RadarTheme.textDim, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- step 2: region

class _RegionStep extends StatelessWidget {
  const _RegionStep({
    super.key,
    required this.countryCtrl,
    required this.cityCtrl,
    required this.isMinor,
    required this.onMinorChanged,
    required this.onTextChanged,
  });

  final TextEditingController countryCtrl;
  final TextEditingController cityCtrl;
  final bool isMinor;
  final ValueChanged<bool> onMinorChanged;

  /// Notifies the wizard state so the Continue button re-evaluates.
  final VoidCallback onTextChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledField(
            key: const ValueKey('onboarding-country'),
            label: 'Country *',
            controller: countryCtrl,
            hint: 'e.g. Cameroon',
            onChanged: (_) => onTextChanged(),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            key: const ValueKey('onboarding-city'),
            label: 'City',
            controller: cityCtrl,
            hint: 'e.g. Douala',
            onChanged: (_) => onTextChanged(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'I am under 18',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Your exact location is never shown — only an approximate '
                      'area name. Adults see the same safeguarding on your '
                      'sessions.',
                      style:
                          TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isMinor,
                onChanged: onMinorChanged,
                activeThumbColor: RadarTheme.pi,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ step 3: profile

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    super.key,
    required this.nameCtrl,
    required this.bioCtrl,
    required this.role,
    required this.onTextChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController bioCtrl;
  final UserRole? role;

  /// Notifies the wizard state so the Continue button re-evaluates.
  final VoidCallback onTextChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledField(
            key: const ValueKey('onboarding-name'),
            label: 'Display name *',
            controller: nameCtrl,
            hint: 'How you appear on the radar',
            maxLength: 40,
            onChanged: (_) => onTextChanged(),
          ),
          const SizedBox(height: 12),
          _LabeledField(
            key: const ValueKey('onboarding-bio'),
            label: 'Short bio',
            onChanged: (_) => onTextChanged(),
            controller: bioCtrl,
            hint: switch (role) {
              UserRole.player => 'Position, current club, standout moments…',
              UserRole.scout => 'Regions covered, past discoveries, focus areas…',
              UserRole.club => 'League, division, what you recruit for…',
              UserRole.academy => 'Age groups, location, notable alumni…',
              UserRole.agent => 'Agencies represented, markets, services…',
              UserRole.parent => 'Your child’s age group and goals…',
              null => 'Tell the community who you are…',
            },
            maxLines: 4,
            maxLength: 280,
          ),
          if (role != null && (role == UserRole.scout || role == UserRole.club || role == UserRole.academy)) ...[
            const SizedBox(height: 12),
            const InfoPill(
              icon: Icons.verified_outlined,
              label: 'Verified badge review after onboarding',
              color: RadarTheme.gold,
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: RadarTheme.textDim),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          buildCounter: maxLength == null
              ? null
              : (context, {required currentLength, required isFocused, maxLength}) => null,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: RadarTheme.ink,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: RadarTheme.stroke),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: RadarTheme.stroke),
            ),
          ),
        ),
      ],
    );
  }
}
