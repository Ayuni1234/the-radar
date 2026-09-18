import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/enums.dart';
import '../models/user_profile.dart';
import '../state/radar_providers.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Searchable directory of players, scouts, clubs, academies, agents,
/// parents — with role filters and credibility indicators.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(profileFilterProvider);
    final ctrl = ref.read(profileFilterProvider.notifier);
    final profilesAsync = ref.watch(filteredProfilesProvider);
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final crossAxis = switch (size) {
      WindowSize.compact => 1,
      WindowSize.medium => 2,
      WindowSize.expanded => 3,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Directory'),
        actions: [
          SizedBox(
            width: 220,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                controller: _search,
                onChanged: ctrl.setQuery,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search name, city, position…',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // Role filter row.
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                ChoiceChip(
                  label: const Text('All roles'),
                  selected: filter.role == null,
                  onSelected: (_) => ctrl.setRole(null),
                ),
                const SizedBox(width: 8),
                for (final role in UserRole.values) ...[
                  ChoiceChip(
                    avatar: Icon(role.icon,
                        size: 15,
                        color: filter.role == role
                            ? RadarTheme.radar
                            : RadarTheme.textDim),
                    label: Text(role.label),
                    selected: filter.role == role,
                    onSelected: (_) => ctrl.setRole(role),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: profilesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Failed to load profiles: $e',
                    style: const TextStyle(color: RadarTheme.textDim)),
              ),
              data: (profiles) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(filteredProfilesProvider),
                child: GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxis,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 3.4,
                  ),
                  itemCount: profiles.length,
                  itemBuilder: (context, i) => ProfileCard(
                    profile: profiles[i],
                    onTap: () => _openProfile(context, profiles[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, UserProfile p) {
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
          child: ProfileDetailSheet(profile: p),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: RadarTheme.panel,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: ProfileDetailSheet(profile: p),
          ),
        ),
      );
    }
  }
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.profile, this.onTap});

  final UserProfile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar block.
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: RadarTheme.pi.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(p.role.icon, color: RadarTheme.pi, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.bestName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                        ),
                        if (p.kycVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              size: 15, color: RadarTheme.radar),
                        ],
                        if (p.isMinor) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.shield,
                              size: 15, color: RadarTheme.gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        p.role.label,
                        if (p.positions.isNotEmpty) p.positions.join(' · '),
                        if (p.city != null) p.city!,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: RadarTheme.textDim),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        CredibilityBar(score: p.credibilityScore),
                        if (p.videoShowcaseUrls.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          const Icon(Icons.play_circle_outline,
                              size: 15, color: RadarTheme.info),
                          Text(' ${p.videoShowcaseUrls.length}',
                              style: const TextStyle(
                                  fontSize: 11, color: RadarTheme.info)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal credibility meter (0–100).
class CredibilityBar extends StatelessWidget {
  const CredibilityBar({super.key, required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    final color = clamped >= 75
        ? RadarTheme.radar
        : clamped >= 45
            ? RadarTheme.gold
            : RadarTheme.alert;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 66,
          height: 4.5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped / 100,
              backgroundColor: RadarTheme.stroke,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4.5,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(clamped.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Full profile detail: role, CV, positions, videos, KYC & safety.
class ProfileDetailSheet extends StatelessWidget {
  const ProfileDetailSheet({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final df = DateFormat('MMM yyyy');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: RadarTheme.pi.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(p.role.icon, color: RadarTheme.pi, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(p.bestName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                        if (p.kycVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              size: 17, color: RadarTheme.radar),
                        ],
                      ],
                    ),
                    Text(
                        '${p.role.label}'
                        '${p.clubAffiliation != null ? ' · ${p.clubAffiliation}' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5, color: RadarTheme.textDim)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InfoPill(
                        icon: Icons.speed,
                        label: 'Credibility ${p.credibilityScore.toStringAsFixed(0)}/100',
                        color: p.credibilityScore >= 75
                            ? RadarTheme.radar
                            : RadarTheme.gold,
                      ),
                      if (p.kycVerified)
                        const InfoPill(
                            icon: Icons.verified_user_outlined,
                            label: 'KYC verified',
                            color: RadarTheme.radar)
                      else
                        const InfoPill(
                            icon: Icons.gpp_maybe_outlined,
                            label: 'KYC pending',
                            color: RadarTheme.gold),
                      if (p.country != null)
                        InfoPill(icon: Icons.public, label: p.country!),
                      if (p.rating > 0)
                        InfoPill(
                            icon: Icons.star_outline,
                            label: p.rating.toStringAsFixed(1)),
                    ],
                  ),
                  // Safety notice for minors.
                  if (p.isMinor) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RadarTheme.gold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: RadarTheme.gold.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 17, color: RadarTheme.gold),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This profile belongs to a player under 18. '
                              'Location details are approximated and contact '
                              'is moderated.',
                              style: TextStyle(
                                  fontSize: 12.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (p.positions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionHeader('Positions'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final pos in p.positions)
                          Chip(
                            label: Text(pos),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                  if (p.bio != null && p.bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionHeader('About'),
                    Text(p.bio!,
                        style: const TextStyle(
                            fontSize: 13.5, height: 1.5, color: RadarTheme.textPrimary)),
                  ],
                  if (p.footballCv != null && p.footballCv!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionHeader('Football CV'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: RadarTheme.panelHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(p.footballCv!,
                          style: const TextStyle(
                              fontSize: 13, height: 1.55)),
                    ),
                  ],
                  if (p.videoShowcaseUrls.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SectionHeader('Video showcase',
                        trailing: Text('${p.videoShowcaseUrls.length} clips',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: RadarTheme.textDim))),
                    for (final url in p.videoShowcaseUrls)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {}, // Deep-link handling by deployment.
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: RadarTheme.panelHigh,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: RadarTheme.stroke),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.play_circle_outline,
                                    color: RadarTheme.info, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    Uri.tryParse(url)?.host ?? url,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                const Icon(Icons.open_in_new,
                                    size: 14, color: RadarTheme.textDim),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'On The Radar since ${df.format(p.createdAt)}'
                    '${p.geohashArea != null && !p.isMinor ? ' · ${p.geohashArea}' : ''}',
                    style: const TextStyle(
                        fontSize: 11.5, color: RadarTheme.textDim),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.connect_without_contact, size: 17),
                  label: const Text('Request contact'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.bookmark_border, size: 17),
                label: const Text('Shortlist'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
