import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'profiles_screen.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Deep-dive page for a single radar event: full metadata, safe location,
/// host identity, and the context-aware action & applicant hub.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.event});

  final RadarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final me = session?.profileId;
    final host = (ref.watch(profilesProvider).value ?? const <UserProfile>[])
        .where((p) => p.id == event.hostProfileId)
        .firstOrNull;
    final isHost = me != null && me == event.hostProfileId;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: Text(event.type.label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          _Header(event: event),
          const SizedBox(height: 14),
          _SafeLocationCard(event: event, viewerIsHost: isHost),
          const SizedBox(height: 14),
          _HostCard(host: host, event: event),
          const SizedBox(height: 14),
          _AboutCard(event: event),
          const SizedBox(height: 14),
          isHost
              ? _ApplicantHub(event: event, myProfileId: me)
              : _ActionHub(event: event, session: session, host: host),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — classification, schedule, status
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.event});

  final RadarEvent event;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEEE d MMMM yyyy · HH:mm');
    final duration = event.endsAt.difference(event.startsAt);
    final durationLabel = duration.inHours >= 1
        ? '${duration.inHours}h${duration.inMinutes % 60 > 0 ? ' ${duration.inMinutes % 60}m' : ''}'
        : '${duration.inMinutes}m';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RadarTheme.radar.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Icon(event.type.icon, size: 22, color: RadarTheme.radar),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(event.title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (event.isLive)
               InfoPill(
                  icon: Icons.circle, label: 'LIVE now', color: RadarTheme.alert)
            else if (event.isUpcoming)
               InfoPill(
                  icon: Icons.schedule, label: 'Upcoming', color: RadarTheme.info),
            if (event.isBoosted)
               InfoPill(icon: Icons.bolt, label: 'Boosted', color: RadarTheme.gold),
            if (event.bountyPi != null)
              InfoPill(
                  icon: Icons.emoji_events_outlined,
                  label: '${event.bountyPi!.toStringAsFixed(0)} π bounty',
                  color: RadarTheme.gold),
            if (event.isMinorProtected)
               InfoPill(
                  icon: Icons.shield_outlined,
                  label: 'Minor-protected',
                  color: RadarTheme.info),
          ]),
          const SizedBox(height: 12),
          Row(children: [
             Icon(Icons.event_outlined, size: 15, color: RadarTheme.textDim),
            const SizedBox(width: 7),
            Expanded(
              child: Text(df.format(event.startsAt),
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 5),
          Row(children: [
             Icon(Icons.timer_outlined, size: 15, color: RadarTheme.textDim),
            const SizedBox(width: 7),
            Text('Runs $durationLabel (until ${DateFormat('HH:mm').format(event.endsAt)})',
                style:  TextStyle(fontSize: 13, color: RadarTheme.textDim)),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Safe location — venue when exact, coarse geohash region when fenced
// ---------------------------------------------------------------------------

class _SafeLocationCard extends StatelessWidget {
  const _SafeLocationCard({required this.event, required this.viewerIsHost});

  final RadarEvent event;
  final bool viewerIsHost;

  @override
  Widget build(BuildContext context) {
    final exact = event.exposesCoordinatesTo(viewerIsHost: viewerIsHost);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.location_on_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Text('Location',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            exact ? Icons.place : Icons.shield_outlined,
            size: 19,
            color: exact ? RadarTheme.radar : RadarTheme.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.safeLocationLabel(viewerIsHost: viewerIsHost),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  exact
                      ? '${event.latitude.toStringAsFixed(4)}, ${event.longitude.toStringAsFixed(4)}'
                      : (viewerIsHost
                          ? 'You are the host — attendees see only “${event.areaName ?? 'the approximate area'}”.'
                          : 'Coarse region only. Exact coordinates are withheld'
                              ' by minor-safety geohash fencing.'),
                  style:  TextStyle(
                      fontSize: 12.5, color: RadarTheme.textDim, height: 1.35),
                ),
              ],
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Host identity with credibility & profile navigation
// ---------------------------------------------------------------------------

class _HostCard extends ConsumerWidget {
  const _HostCard({required this.host, required this.event});

  final UserProfile? host;
  final RadarEvent event;

  void _open(BuildContext context, UserProfile host) {
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: RadarTheme.pi.withValues(alpha: 0.22),
          child: Text(
            event.hostName.isNotEmpty ? event.hostName[0].toUpperCase() : '?',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.hostName,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (host != null)
                  InfoPill(
                      icon: host!.role.icon, label: host!.role.label)
                else
                  const InfoPill(icon: Icons.person_outline, label: 'Host'),
                if (host?.kycVerified ?? false)
                   InfoPill(
                      icon: Icons.verified_outlined,
                      label: 'KYC verified',
                      color: RadarTheme.radar),
                if (host != null && host!.credibilityScore > 0)
                  InfoPill(
                      icon: Icons.insights,
                      label: 'Credibility ${host!.credibilityScore.round()}',
                      color: RadarTheme.gold),
              ]),
            ],
          ),
        ),
        TextButton.icon(
          key: const ValueKey('view-host-profile'),
          onPressed: host == null ? null : () => _open(context, host!),
          icon: const Icon(Icons.chevron_right, size: 17),
          label: const Text('Profile'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// About — description, positions scouted, capacity
// ---------------------------------------------------------------------------

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.event});

  final RadarEvent event;

  @override
  Widget build(BuildContext context) {
    final capacity = event.capacity;
    final filled = capacity == null || capacity <= 0
        ? null
        : (event.attendingCount / capacity).clamp(0.0, 1.0);
    final isFull = capacity != null && event.attendingCount >= capacity;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.description_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Text('About this event',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(event.description!,
              style:  TextStyle(
                  fontSize: 13.5, height: 1.45, color: RadarTheme.textPrimary)),
        ],
        if (event.positionsRequired.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('POSITIONS BEING SCOUTED',
              style:  TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: RadarTheme.textDim)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final p in event.positionsRequired)
                InfoPill(icon: Icons.sports_soccer, label: p, color: RadarTheme.pi),
            ],
          ),
        ] else
          const SizedBox(height: 10),
        Row(children: [
          if (event.minAge != null || event.maxAge != null)
            const InfoPill(icon: Icons.cake_outlined, label: 'Age brackets set'),
          const SizedBox(width: 8),
          if (isFull)
             InfoPill(
                icon: Icons.do_not_disturb_on,
                label: 'Event full',
                color: RadarTheme.alert)
          else if (capacity != null)
            InfoPill(
                icon: Icons.groups,
                label: '${event.attendingCount}/$capacity spots filled',
                color: RadarTheme.radar),
        ]),
        if (filled != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: filled,
              minHeight: 6,
              backgroundColor: RadarTheme.panelHigh,
              valueColor: AlwaysStoppedAnimation<Color>(RadarTheme.radar),
            ),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Action hub — organizer applicant manager (host view)
// ---------------------------------------------------------------------------

class _ApplicantHub extends ConsumerWidget {
  const _ApplicantHub({required this.event, required this.myProfileId});

  final RadarEvent event;
  final String myProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(connectionsProvider).value ?? const [];
    final applicants = requests
        .where((r) => r.eventId == event.id && r.toProfile == myProfileId)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
           Icon(Icons.manage_accounts_outlined,
              size: 17, color: RadarTheme.radar),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Applicant hub',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          InfoPill(
              icon: Icons.how_to_reg,
              label: '${applicants.where((a) => a.isPending).length} pending',
              color: RadarTheme.gold),
        ]),
        const SizedBox(height: 12),
        if (applicants.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No applications for this event yet. Boost it from the Pi Wallet '
              'to reach more players on the radar.',
              style:  TextStyle(
                  fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
            ),
          )
        else
          for (final r in applicants)
            _ApplicantTile(request: r),
      ]),
    );
  }
}

class _ApplicantTile extends ConsumerWidget {
  const _ApplicantTile({required this.request});

  final ConnectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (request.status) {
      ConnectionStatus.pending => RadarTheme.gold,
      ConnectionStatus.accepted => RadarTheme.radar,
      ConnectionStatus.declined => RadarTheme.alert,
      ConnectionStatus.withdrawn => RadarTheme.textDim,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: RadarTheme.pi.withValues(alpha: 0.2),
            child: Text(
              (request.fromName ?? '?').isNotEmpty
                  ? request.fromName![0].toUpperCase()
                  : '?',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(request.fromName ?? 'Unknown applicant',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          InfoPill(
              icon: Icons.circle,
              label: request.status.label,
              color: statusColor),
        ]),
        if (request.message != null && request.message!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(request.message!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style:  TextStyle(
                  fontSize: 12.5, color: RadarTheme.textDim, height: 1.35)),
        ],
        if (request.isPending) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await ref
                      .read(connectionsProvider.notifier)
                      .respond(request.id, ConnectionStatus.accepted);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(ok
                            ? '${request.fromName ?? 'Applicant'} accepted — contact details unlocked'
                            : 'Could not update the application')));
                  }
                },
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Accept'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => ref
                    .read(connectionsProvider.notifier)
                    .respond(request.id, ConnectionStatus.declined),
                style: OutlinedButton.styleFrom(
                    foregroundColor: RadarTheme.alert),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Decline'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Action hub — apply / request attendance (visitor view)
// ---------------------------------------------------------------------------

class _ActionHub extends ConsumerWidget {
  const _ActionHub({required this.event, required this.session, required this.host});

  final RadarEvent event;
  final RadarSession? session;
  final UserProfile? host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = session?.profileId;
    final requests = ref.watch(connectionsProvider).value ?? const [];
    final mine = me == null
        ? const <ConnectionRequest>[]
        : requests
            .where((r) =>
                r.fromProfile == me &&
                r.eventId == event.id &&
                r.isPending)
            .toList();
    final hasPending = mine.isNotEmpty;
    final isTrial = event.type == RadarEventType.trial;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.bolt_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Text('Take action',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Text(
          isTrial
              ? 'Submit your application — the organizer reviews trial applicants here and on their inbox.'
              : 'Request to attend and the host will confirm your spot.',
          style:  TextStyle(
              fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (session == null || me == null)
           InfoPill(
              icon: Icons.lock_outline,
              label: 'Sign in with Pi to apply',
              color: RadarTheme.gold)
        else if (host == null)
          const InfoPill(
              icon: Icons.hourglass_empty,
              label: 'Host profile unavailable — try again later')
        else if (hasPending)
           InfoPill(
              key: ValueKey('application-pending'),
              icon: Icons.hourglass_top,
              label: 'Application pending review',
              color: RadarTheme.gold)
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('event-apply'),
              onPressed: () => requestConnection(
                context,
                ref,
                host!,
                event: event,
                initialType: isTrial
                    ? ConnectionType.trialApplication
                    : ConnectionType.contact,
              ),
              icon: Icon(isTrial ? Icons.how_to_reg : Icons.waving_hand,
                  size: 17),
              label: Text(isTrial ? 'Apply to trial' : 'Request attendance'),
            ),
          ),
        if (mine.any((r) => !r.isPending))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InfoPill(
              icon: Icons.history,
              label:
                  'Previous application: ${mine.last.status.label.toLowerCase()}',
              color: RadarTheme.textDim,
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

BoxDecoration _cardDecoration() => BoxDecoration(
      color: RadarTheme.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: RadarTheme.stroke),
    );
