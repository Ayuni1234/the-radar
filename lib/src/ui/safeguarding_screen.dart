import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/content_report.dart';
import '../models/enums.dart';
import '../models/guardian_link.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'moderation_queue_screen.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Module 3 — Minor-Safety & Privacy Safeguards.
///
/// Two halves, one screen:
///  * Geofencing status — what the platform automatically masks for
///    minor-protected profiles (database-enforced, not a client promise).
///  * Consent management — minors invite their guardian; the guardian
///    approves the link and controls the two consent switches.
class SafeguardingScreen extends ConsumerWidget {
  const SafeguardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final linksAsync = ref.watch(guardianLinksProvider);
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];
    final isMinor = session?.isMinor ?? false;
    final isParent = session?.role == UserRole.parent;

    UserProfile profileOf(String id) =>
        profiles.firstWhere((p) => p.id == id, orElse: () => profiles.first);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Text(
                    'Safeguarding & Privacy',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  InfoPill(
                    icon: Icons.shield_outlined,
                    label: isMinor ? 'Minor protected' : 'Adult account',
                    color: isMinor ? RadarColors.stroke : RadarTheme.radar,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Automated geohash fencing and guardian consent, enforced at '
                'the database level — no client can bypass them.',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
              ),
              const SizedBox(height: 18),

              // -------------------------------------------- moderation (admin)
              if (session?.isAdmin ?? false) ...[
                const _AdminQueueCard(),
                const SizedBox(height: 18),
              ],

              // ------------------------------------------------ geofencing
              _GeofenceCard(isMinor: isMinor),
              const SizedBox(height: 18),

              // --------------------------------------------------- guardian
              if (isMinor) ...[
                _MinorGuardianSection(session: session!),
                const SizedBox(height: 18),
              ] else if (isParent) ...[
                const _GuardianConsentSection(),
                const SizedBox(height: 18),
              ] else ...[
                const _GuardianNoteCard(),
                const SizedBox(height: 18),
              ],

              // Shared list of links involving this account (either side).
              linksAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => _Panel(
                  child: Text(
                    'Could not load guardian links: $e',
                    style: const TextStyle(color: RadarTheme.alert),
                  ),
                ),
                data: (links) {
                  if (links.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Guardian links on this account'),
                        for (final link in links)
                          _GuardianLinkTile(
                            link: link,
                            viewerProfileId: session?.profileId ?? '',
                            minorName: profileOf(link.minorProfile).bestName,
                            guardianName:
                                profileOf(link.guardianProfile).bestName,
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // --------------------------------------- consent audit history
              _ConsentAuditPanel(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ panels

/// Admin entry point into the moderation queue. Only rendered for
/// profiles.is_admin (granted by operator SQL) — RLS makes the queue
/// itself harmless for everyone else.
class _AdminQueueCard extends ConsumerWidget {
  const _AdminQueueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(contentReportsProvider).value;
    final openCount = reports
        ?.where((r) =>
            r.status == ContentReportStatus.open ||
            r.status == ContentReportStatus.reviewing)
        .length;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ModerationQueueScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RadarTheme.gold.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          const Icon(Icons.gavel_outlined, color: RadarTheme.gold, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Moderation queue',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(
                  'Review reported posts, events and listings.',
                  style:
                      const TextStyle(color: RadarTheme.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          if (openCount != null && openCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: RadarTheme.gold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$openCount',
                  style: const TextStyle(
                      color: RadarTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: RadarTheme.textDim),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: child,
    );
  }
}

/// What automatic fencing means, personalized for the viewer.
class _GeofenceCard extends StatelessWidget {
  const _GeofenceCard({required this.isMinor});
  final bool isMinor;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Automatic geohash fencing',
            trailing: InfoPill(
              icon: Icons.lock_outline,
              label: 'DB-enforced',
              color: RadarTheme.info,
            ),
          ),
          _Bullet(
            isMinor
                ? 'Your location is locked to a coarse area label — exact '
                    'coordinates and venue names are stripped before storage.'
                : 'Events marked minor-protected always render an approximate '
                    'area — exact coordinates and venue names never reach the '
                    'client.',
          ),
          _Bullet(
            isMinor
                ? 'Any event you host is automatically fenced, even if you '
                    'forget to mark it.'
                : 'Events hosted by a minor are fenced automatically at '
                    'write time by the `enforce_minor_safety` trigger.',
          ),
          _Bullet(
            'Adults cannot contact a minor without the guardian\'s explicit '
            'consent — blocked in the database, not just hidden in the UI.',
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
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
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Education card for non-parent adults.
class _GuardianNoteCard extends StatelessWidget {
  const _GuardianNoteCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Why you may see consent walls'),
          Text(
            'When you reach out to a player flagged as a minor, The Radar '
            'asks their registered guardian for consent first. Requests '
            'without it are rejected by the platform itself — this protects '
            'young talent and keeps scouting on this platform clean.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: RadarTheme.textPrimary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minor side: invite a guardian, see link status (read-only consents).
class _MinorGuardianSection extends ConsumerStatefulWidget {
  const _MinorGuardianSection({required this.session});
  final RadarSession session;

  @override
  ConsumerState<_MinorGuardianSection> createState() =>
      _MinorGuardianSectionState();
}

class _MinorGuardianSectionState extends ConsumerState<_MinorGuardianSection> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final username = _controller.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Enter your guardian\'s Pi username.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final error =
        await ref.read(guardianLinksProvider.notifier).inviteGuardian(username);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
    });
    if (error == null) {
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite sent — your guardian can now approve it.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Link a parent or guardian'),
          Text(
            'Invite the adult who manages your football journey. They approve '
            'the link and then decide who may contact you and which events '
            'you may join.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: RadarTheme.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('guardian-username'),
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: "Guardian's Pi username (e.g. proud_rugby_dad)",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _invite(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const ValueKey('guardian-invite'),
                onPressed: _sending ? null : _invite,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('Invite'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: RadarTheme.alert)),
          ],
          const SizedBox(height: 10),
          const Text(
            'Consent switches are controlled by your guardian — you can '
            'revoke a link at any time, but never self-approve one.',
            style: TextStyle(fontSize: 12, color: RadarTheme.textDim),
          ),
        ],
      ),
    );
  }
}

/// Guardian side: approve pending invites, control the consent switches.
class _GuardianConsentSection extends ConsumerWidget {
  const _GuardianConsentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(guardianLinksProvider);
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];
    final session = ref.watch(sessionProvider);
    final myId = session?.profileId ?? '';

    String nameOf(String id) => profiles
        .where((p) => p.id == id)
        .map((p) => p.bestName)
        .firstOrNull ?? 'Unknown player';

    return linksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _Panel(
        child: Text('Could not load links: $e',
            style: const TextStyle(color: RadarTheme.alert)),
      ),
      data: (links) {
        final pending = links
            .where((l) => l.guardianProfile == myId && l.isPending)
            .toList();
        final active = links
            .where((l) => l.guardianProfile == myId && l.isActive)
            .toList();

        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Consent dashboard'),
              if (pending.isEmpty && active.isEmpty)
                const Text(
                  'No guardian invitations yet. When a young player invites '
                  'you, their request appears here.',
                  style: TextStyle(fontSize: 13.5, color: RadarTheme.textDim),
                ),
              for (final link in pending) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.mark_email_unread_outlined,
                        size: 18, color: RadarTheme.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${nameOf(link.minorProfile)} wants you as their guardian.',
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(guardianLinksProvider.notifier)
                          .declineLink(link.id),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      key: ValueKey('approve-${link.id}'),
                      onPressed: () => ref
                          .read(guardianLinksProvider.notifier)
                          .approveLink(link.id),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ],
              for (final link in active) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: RadarTheme.stroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guardian of ${nameOf(link.minorProfile)}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _ConsentSwitch(
                        title: 'Allow contact requests from verified adults',
                        subtitle:
                            'Scouts, clubs and agents may message the player.',
                        value: link.consentConnections,
                        onChanged: (v) => ref
                            .read(guardianLinksProvider.notifier)
                            .setConsent(link.id, consentConnections: v),
                        switchKey: ValueKey('consent-conn-${link.id}'),
                      ),
                      _ConsentSwitch(
                        title: 'Allow event participation',
                        subtitle:
                            'The player may be invited to trials and may apply.',
                        value: link.consentEvents,
                        onChanged: (v) => ref
                            .read(guardianLinksProvider.notifier)
                            .setConsent(link.id, consentEvents: v),
                        switchKey: ValueKey('consent-events-${link.id}'),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => ref
                              .read(guardianLinksProvider.notifier)
                              .revokeLink(link.id),
                          icon: const Icon(Icons.link_off, size: 15),
                          label: const Text('Revoke link'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConsentSwitch extends StatelessWidget {
  const _ConsentSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.switchKey,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13.5)),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 12, color: RadarTheme.textDim)),
            ],
          ),
        ),
        Switch(key: switchKey, value: value, onChanged: onChanged),
      ],
    );
  }
}

/// One guardian link row (shared by minor and guardian views).
class _GuardianLinkTile extends StatelessWidget {
  const _GuardianLinkTile({
    required this.link,
    required this.viewerProfileId,
    required this.minorName,
    required this.guardianName,
  });

  final GuardianLink link;
  final String viewerProfileId;
  final String minorName;
  final String guardianName;

  @override
  Widget build(BuildContext context) {
    final viewerIsGuardian = link.guardianProfile == viewerProfileId;
    final other = viewerIsGuardian ? minorName : guardianName;
    final relation = viewerIsGuardian ? 'guardian of' : 'linked to';

    final (color, icon) = switch (link.status) {
      GuardianLinkStatus.active => (RadarTheme.radar, Icons.verified_outlined),
      GuardianLinkStatus.pending => (RadarTheme.gold, Icons.hourglass_top),
      GuardianLinkStatus.declined => (RadarTheme.alert, Icons.block),
      GuardianLinkStatus.revoked => (RadarTheme.textDim, Icons.link_off),
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$relation $other',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${link.status.label}'
                  ' · contacts: ${link.consentConnections ? "allowed" : "blocked"}'
                  ' · events: ${link.consentEvents ? "allowed" : "blocked"}',
                  style: const TextStyle(
                      fontSize: 12, color: RadarTheme.textDim),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  InfoPill(
                    icon: link.consentConnections
                        ? Icons.connect_without_contact
                        : Icons.block,
                    label: link.consentConnections
                        ? 'Contacts allowed'
                        : 'Contacts blocked',
                    color: link.consentConnections
                        ? RadarTheme.radar
                        : RadarTheme.alert,
                  ),
                  InfoPill(
                    icon: link.consentEvents
                        ? Icons.emoji_events_outlined
                        : Icons.block,
                    label: link.consentEvents
                        ? 'Events allowed'
                        : 'Events blocked',
                    color: link.consentEvents
                        ? RadarTheme.radar
                        : RadarTheme.alert,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Transparent consent history — every guardian permission decision,
/// recorded by the `guardian_links_audit` database trigger and read back
/// through the participant-scoped `read_consent_audit` RPC.
class _ConsentAuditPanel extends ConsumerWidget {
  const _ConsentAuditPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(consentAuditProvider);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long, size: 17, color: RadarTheme.radar),
            const SizedBox(width: 8),
            const Expanded(
              child: SectionHeader('Consent history & audit log'),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 17),
              onPressed: () => unawaited(
                  ref.read(consentAuditProvider.notifier).refresh()),
            ),
          ]),
          Text(
            'Every approval, denial and consent switch is recorded by the '
            'database — this log cannot be edited from the app.',
            style: const TextStyle(
                fontSize: 12, color: RadarTheme.textDim, height: 1.4),
          ),
          const SizedBox(height: 10),
          auditAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text(
              'Could not load the audit log: $e',
              style: const TextStyle(color: RadarTheme.alert, fontSize: 12.5),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No consent decisions recorded yet. History appears here '
                    'as guardians approve links and manage permissions.',
                    style: TextStyle(
                        fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
                  ),
                );
              }
              return Column(children: [
                for (final e in entries.take(30))
                  _AuditTile(entry: e),
                if (entries.length > 30)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Showing the 30 most recent of ${entries.length} entries.',
                      style: const TextStyle(
                          fontSize: 11.5, color: RadarTheme.textDim),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final ConsentAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = entry.visual;
    final df = DateFormat('d MMM yyyy · HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(entry.label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        InfoPill(
          icon: entry.actorRole == 'guardian'
              ? Icons.family_restroom
              : Icons.person,
          label: entry.actorRole == 'guardian' ? 'Guardian' : 'Minor',
          color: RadarTheme.textDim,
        ),
        const SizedBox(width: 6),
        Text(
          entry.createdAt == null ? '' : df.format(entry.createdAt!),
          style: const TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
        ),
      ]),
    );
  }
}
