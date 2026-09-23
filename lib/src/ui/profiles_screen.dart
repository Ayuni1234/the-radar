import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/radar_repository.dart';
import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/guardian_link.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'player_cv_screen.dart';
import 'radar_theme.dart';
import 'search_screen.dart';
import 'sheet_scaffold.dart';
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
          IconButton(
            tooltip: 'Global search',
            icon: const Icon(Icons.travel_explore, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
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
                    avatar: Icon(
                      role.icon,
                      size: 15,
                      color: filter.role == role
                          ? RadarTheme.radar
                          : RadarTheme.textDim,
                    ),
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
                child: Text(
                  'Failed to load profiles: $e',
                  style: const TextStyle(color: RadarTheme.textDim),
                ),
              ),
              data: (profiles) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(filteredProfilesProvider),
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
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (p.kycVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 15,
                            color: RadarTheme.radar,
                          ),
                        ],
                        if (p.isMinor) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.shield,
                            size: 15,
                            color: RadarTheme.gold,
                          ),
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
                        fontSize: 12,
                        color: RadarTheme.textDim,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        CredibilityBar(score: p.credibilityScore),
                        if (p.videoShowcaseUrls.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.play_circle_outline,
                            size: 15,
                            color: RadarTheme.info,
                          ),
                          Text(
                            ' ${p.videoShowcaseUrls.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: RadarTheme.info,
                            ),
                          ),
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
        Text(
          clamped.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 10.5,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Full profile detail: role, CV, positions, videos, KYC & safety.
class ProfileDetailSheet extends ConsumerWidget {
  const ProfileDetailSheet({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                          child: Text(
                            p.bestName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (p.kycVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 17,
                            color: RadarTheme.radar,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${p.role.label}'
                      '${p.clubAffiliation != null ? ' · ${p.clubAffiliation}' : ''}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: RadarTheme.textDim,
                      ),
                    ),
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
                        label:
                            'Credibility ${p.credibilityScore.toStringAsFixed(0)}/100',
                        color: p.credibilityScore >= 75
                            ? RadarTheme.radar
                            : RadarTheme.gold,
                      ),
                      if (p.kycVerified)
                        const InfoPill(
                          icon: Icons.verified_user_outlined,
                          label: 'KYC verified',
                          color: RadarTheme.radar,
                        )
                      else
                        const InfoPill(
                          icon: Icons.gpp_maybe_outlined,
                          label: 'KYC pending',
                          color: RadarTheme.gold,
                        ),
                      if (p.country != null)
                        InfoPill(icon: Icons.public, label: p.country!),
                      if (p.rating > 0)
                        InfoPill(
                          icon: Icons.star_outline,
                          label: p.rating.toStringAsFixed(1),
                        ),
                    ],
                  ),
                  if (p.role == UserRole.player) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('view-full-cv'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PlayerCvScreen(profile: p),
                          ),
                        ),
                        icon: const Icon(Icons.badge_outlined, size: 17),
                        label: const Text('Full CV & portfolio'),
                      ),
                    ),
                  ],
                  // Safety notice for minors.
                  if (p.isMinor) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RadarTheme.gold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: RadarTheme.gold.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 17,
                            color: RadarTheme.gold,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This profile belongs to a player under 18. '
                              'Location details are approximated and contact '
                              'is moderated.',
                              style: TextStyle(fontSize: 12.5, height: 1.4),
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
                    Text(
                      p.bio!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: RadarTheme.textPrimary,
                      ),
                    ),
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
                      child: Text(
                        p.footballCv!,
                        style: const TextStyle(fontSize: 13, height: 1.55),
                      ),
                    ),
                  ],
                  if (p.videoShowcaseUrls.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SectionHeader(
                      'Video showcase',
                      trailing: Text(
                        '${p.videoShowcaseUrls.length} clips',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: RadarTheme.textDim,
                        ),
                      ),
                    ),
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
                                const Icon(
                                  Icons.play_circle_outline,
                                  color: RadarTheme.info,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    Uri.tryParse(url)?.host ?? url,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                const Icon(
                                  Icons.open_in_new,
                                  size: 14,
                                  color: RadarTheme.textDim,
                                ),
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
                      fontSize: 11.5,
                      color: RadarTheme.textDim,
                    ),
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
                  onPressed: () => requestConnection(context, ref, profile),
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

/// Public connection-sheet entry point (the P2P request form). Returns
/// the draft when submitted, or null when dismissed. Exposed for tests.
Future<ConnectionSheetDraft?> openConnectionSheet(
  BuildContext context, {
  required String targetName,
  required bool canInvite,
  RadarEvent? event,
  ConnectionType initialType = ConnectionType.contact,
}) async {
  return showModalBottomSheet<ConnectionSheetDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RadarTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetCtx) => _ConnectionSheet(
      targetName: targetName,
      canInvite: canInvite,
      event: event,
      initialType: initialType,
    ),
  );
}

/// Opens the P2P connection request sheet (Module 4): contact request,
/// trial invite or trial application, with a short message. When [event]
/// is set, the sheet is event-scoped — organizers invite the player to
/// that event, players apply to it.
Future<void> requestConnection(
  BuildContext context,
  WidgetRef ref,
  UserProfile target, {
  RadarEvent? event,
  ConnectionType? initialType,
}) async {
  final session = ref.read(sessionProvider);
  final me = session?.profileId;
  if (me == null || me == target.id) return;

  // Scout/club/agent can invite; players apply; everyone can request contact.
  final isOrganizer =
      session?.role == UserRole.scout ||
      session?.role == UserRole.club ||
      session?.role == UserRole.academy;

  final result = await openConnectionSheet(
    context,
    targetName: target.bestName,
    canInvite: isOrganizer && target.role == UserRole.player,
    event: event,
    initialType: initialType ??
        (event != null
            ? (isOrganizer && target.role == UserRole.player
                ? ConnectionType.trialInvite
                : event.type == RadarEventType.trial
                    ? ConnectionType.trialApplication
                    : ConnectionType.contact)
            : ConnectionType.contact),
  );
  if (result == null || !context.mounted) return;

  // Module 3: guardian-consent pre-check (fail-closed UX). The
  // authoritative gate is the connection_requests_minor_consent trigger —
  // this only replaces a raw DB error with a clear explanation.
  final targetConsent =
      await RadarRepository.instance.fetchConsentStatus(target.id);
  final selfConsent = (session?.isMinor ?? false)
      ? await RadarRepository.instance.fetchConsentStatus(me)
      : null;
  final blockReason = _consentBlockReason(
    type: result.type,
    targetConsent: targetConsent,
    selfConsent: selfConsent,
  );
  if (blockReason != null) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ConsentWallDialog(reason: blockReason),
    );
    return;
  }

  final ok = await RadarRepository.instance.createConnectionRequest(
    ConnectionRequest(
      id: '',
      fromProfile: me,
      toProfile: target.id,
      type: result.type,
      status: ConnectionStatus.pending,
      message: result.message,
      eventId: result.eventId,
    ),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? 'Request sent to ${target.bestName} — track it in the Inbox.'
            : 'Could not send the request — try again.',
      ),
    ),
  );
}

/// Returns a human-readable reason when guardian consent blocks this
/// request, or null when it may proceed.
String? _consentBlockReason({
  required ConnectionType type,
  required MinorConsent targetConsent,
  required MinorConsent? selfConsent,
}) {
  // A minor applying for a trial themselves needs event consent.
  if (selfConsent != null &&
      selfConsent.isMinor &&
      type == ConnectionType.trialApplication &&
      !selfConsent.allowsEvents) {
    return 'Your guardian has not enabled event participation yet. '
        'Ask them to allow it on the Safety tab.';
  }
  if (!targetConsent.isMinor) return null;
  switch (type) {
    case ConnectionType.contact:
      if (!targetConsent.allowsContact) {
        return "${targetConsent.allowsEvents ? "This player's" : "This young player's"} "
            'guardian has not enabled contact requests yet. Your message '
            'would be rejected — the request can be sent once they allow it.';
      }
      return null;
    case ConnectionType.trialInvite:
      if (!targetConsent.allowsEvents) {
        return 'This player\'s guardian has not enabled event '
            'participation yet. Trial invites can be sent once they do.';
      }
      return null;
    case ConnectionType.trialApplication:
      if (!targetConsent.allowsContact && !targetConsent.allowsEvents) {
        return 'This player\'s guardian consent is required before any '
            'connection can be made.';
      }
      return null;
  }
}

/// Consent-wall dialog shown when a guardian has not enabled a request.
class _ConsentWallDialog extends StatelessWidget {
  const _ConsentWallDialog({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: RadarTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.shield_outlined, color: RadarTheme.info, size: 32),
      title: const Text(
        'Guardian consent required',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: Text(
        reason,
        style: const TextStyle(fontSize: 13.5, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Understood'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------- connection sheet
/// What the user chose in the connection sheet.
class ConnectionSheetDraft {
  const ConnectionSheetDraft(this.type, this.message, [this.eventId]);

  final ConnectionType type;
  final String? message;
  final String? eventId;
}

/// Bottom sheet for composing a connection request (Module 4).
class _ConnectionSheet extends StatefulWidget {
  const _ConnectionSheet({
    required this.targetName,
    required this.canInvite,
    this.event,
    this.initialType = ConnectionType.contact,
  });

  final String targetName;
  final bool canInvite;
  final RadarEvent? event;
  final ConnectionType initialType;

  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  late ConnectionType _type = widget.initialType;
  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Connect with ${widget.targetName}',
      subtitle: 'Your message goes to their inbox. Contact details stay '
          'private until they accept.',
      footer: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: RadarTheme.pi,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
        ),
        onPressed: () => Navigator.of(context).pop(
          ConnectionSheetDraft(
            _type,
            _messageCtrl.text.trim().isEmpty
                ? null
                : _messageCtrl.text.trim(),
            // Attach the event for event-scoped requests.
            widget.event != null &&
                    (_type == ConnectionType.trialInvite ||
                        _type == ConnectionType.trialApplication)
                ? widget.event!.id
                : null,
          ),
        ),
        icon: const Icon(Icons.send_outlined, size: 17),
        label: const Text('Send request'),
      ),
      children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(widget.event == null
                      ? 'Contact request'
                      : 'Contact ${widget.event!.hostName}'),
                  selected: _type == ConnectionType.contact,
                  onSelected: (_) =>
                      setState(() => _type = ConnectionType.contact),
                ),
                if (widget.canInvite)
                  ChoiceChip(
                    label: Text(widget.event == null
                        ? 'Trial invite'
                        : "Invite to '${widget.event!.title}'"),
                    selected: _type == ConnectionType.trialInvite,
                    onSelected: (_) =>
                        setState(() => _type = ConnectionType.trialInvite),
                  ),
                if (widget.event != null && !widget.canInvite)
                  ChoiceChip(
                    label: Text(widget.event!.type == RadarEventType.trial
                        ? "Apply to '${widget.event!.title}'"
                        : "Request attendance"),
                    selected: _type == ConnectionType.trialApplication,
                    onSelected: (_) => setState(
                        () => _type = ConnectionType.trialApplication),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                hintText: 'Introduce yourself — who you are, why you are reaching out…',
                border: OutlineInputBorder(),
              ),
            ),
      ],
    );
  }
}
