import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Module 4 — P2P scouting connections inbox.
///
/// Received requests can be accepted or declined; sent requests can be
/// withdrawn while pending. All state transitions go through the
/// `connection_requests` RLS-scoped repository path.
class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final myId = session?.profileId ?? '';
    final requestsAsync = ref.watch(connectionsProvider);
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: DefaultTabController(
            length: 2,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(86),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  title: const Text(
                    'Connections',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => ref
                          .read(connectionsProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                    const SizedBox(width: 8),
                  ],
                  bottom: TabBar(
                    indicatorColor: RadarTheme.radar,
                    labelColor: RadarTheme.textPrimary,
                    unselectedLabelColor: RadarTheme.textDim,
                    tabs: const [
                      Tab(text: 'Received'),
                      Tab(text: 'Sent'),
                    ],
                  ),
                ),
              ),
              body: requestsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => Center(
                  child: Text('Could not load requests: $e',
                      style: const TextStyle(color: RadarTheme.alert)),
                ),
                data: (all) {
                  final received = all
                      .where((r) => r.toProfile == myId)
                      .toList()
                    ..sort(_newestFirst);
                  final sent = all
                      .where((r) => r.fromProfile == myId)
                      .toList()
                    ..sort(_newestFirst);

                  UserProfile? profileOf(String id) {
                    for (final p in profiles) {
                      if (p.id == id) return p;
                    }
                    return null;
                  }

                  return TabBarView(
                    children: [
                      _RequestList(
                        requests: received,
                        emptyTitle: 'No requests yet',
                        emptyBody:
                            'When scouts, clubs or academies reach out — or '
                            'players apply to your trials — they appear here.',
                        profileOf: profileOf,
                      ),
                      _RequestList(
                        requests: sent,
                        emptyTitle: 'Nothing sent yet',
                        emptyBody:
                            'Open a player profile to request contact, or an '
                            'event to invite / apply — your requests and '
                            'their status show up here.',
                        profileOf: profileOf,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static int _newestFirst(ConnectionRequest a, ConnectionRequest b) {
    final ad = a.createdAt ?? DateTime(2000);
    final bd = b.createdAt ?? DateTime(2000);
    return bd.compareTo(ad);
  }
}

class _RequestList extends ConsumerWidget {
  const _RequestList({
    required this.requests,
    required this.emptyTitle,
    required this.emptyBody,
    required this.profileOf,
  });

  final List<ConnectionRequest> requests;
  final String emptyTitle;
  final String emptyBody;
  final UserProfile? Function(String id) profileOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final myId = session?.profileId ?? '';

    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.connect_without_contact,
                  size: 40, color: RadarTheme.stroke),
              const SizedBox(height: 12),
              Text(emptyTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                emptyBody,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: RadarTheme.textDim),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, i) {
        final r = requests[i];
        final incoming = r.toProfile == myId;
        final otherId = incoming ? r.fromProfile : r.toProfile;
        final other = profileOf(otherId);
        final otherName = other?.bestName ??
            (incoming ? r.fromName ?? 'Unknown' : r.toName ?? 'Unknown');

        return _RequestCard(
          request: r,
          incoming: incoming,
          otherName: otherName,
          otherRole: other?.role,
          otherCredibility: other?.credibilityScore,
        );
      },
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({
    required this.request,
    required this.incoming,
    required this.otherName,
    this.otherRole,
    this.otherCredibility,
  });

  final ConnectionRequest request;
  final bool incoming;
  final String otherName;
  final UserRole? otherRole;
  final double? otherCredibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('d MMM · HH:mm');
    final pending = request.isPending;

    final (typeIcon, typeColor) = switch (request.type) {
      ConnectionType.contact => (
          Icons.connect_without_contact,
          RadarTheme.info
        ),
      ConnectionType.trialInvite => (Icons.how_to_reg, RadarTheme.pi),
      ConnectionType.trialApplication => (
          Icons.sports_soccer,
          RadarTheme.radar
        ),
    };

    final (statusColor, statusLabel) = switch (request.status) {
      ConnectionStatus.pending => (RadarTheme.gold, 'Pending'),
      ConnectionStatus.accepted => (RadarTheme.radar, 'Accepted'),
      ConnectionStatus.declined => (RadarTheme.alert, 'Declined'),
      ConnectionStatus.withdrawn => (RadarTheme.textDim, 'Withdrawn'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pending
              ? RadarTheme.stroke
              : RadarTheme.stroke.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(typeIcon, size: 16, color: typeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  incoming
                      ? '${request.type.label} from $otherName'
                      : '${request.type.label} to $otherName',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              InfoPill(
                icon: pending ? Icons.hourglass_top : Icons.check_circle_outline,
                label: statusLabel,
                color: statusColor,
              ),
            ],
          ),
          if (request.message != null && request.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"${request.message}"',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: RadarTheme.textPrimary.withValues(alpha: 0.85),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            [
              if (otherRole != null)
                '${otherRole!.label}'
                '${otherCredibility != null && otherCredibility! > 0 ? " · credibility ${otherCredibility!.round()}" : ""}',
              if (request.createdAt != null) df.format(request.createdAt!),
            ].join('  ·  '),
            style: const TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
          ),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: incoming
                  ? [
                      OutlinedButton(
                        onPressed: () => _respond(
                            context, ref, ConnectionStatus.declined),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _respond(
                            context, ref, ConnectionStatus.accepted),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Accept'),
                      ),
                    ]
                  : [
                      TextButton.icon(
                        onPressed: () =>
                            _respond(context, ref, ConnectionStatus.withdrawn),
                        icon: const Icon(Icons.undo, size: 15),
                        label: const Text('Withdraw'),
                      ),
                    ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    ConnectionStatus status,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(connectionsProvider.notifier)
        .respond(request.id, status);
    final label = switch (status) {
      ConnectionStatus.accepted => 'Accepted — you are now connected.',
      ConnectionStatus.declined => 'Request declined.',
      ConnectionStatus.withdrawn => 'Request withdrawn.',
      ConnectionStatus.pending => 'Updated.',
    };
    messenger.showSnackBar(SnackBar(content: Text(label)));
  }
}
