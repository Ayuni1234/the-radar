import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/radar_providers.dart';
import '../supabase/supabase_config.dart';
import '../sync/sync_service.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Offline & Data Sync Center — connectivity status, outbox queue,
/// cache inspection, conflict resolution and offline storage settings.
class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final wifiOnly = ref.watch(wifiOnlyProvider);
    final events = ref.watch(radarEventsProvider).value ?? const [];
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final live = SupabaseConfig.available;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: const Text('Data & sync'),
        actions: [
          IconButton(
            tooltip: 'Force sync now',
            onPressed: () => ref.read(syncProvider.notifier).flush(),
            icon: const Icon(Icons.sync, size: 20),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          _StatusCard(sync: sync, live: live),
          const SizedBox(height: 14),
          _OutboxCard(sync: sync),
          const SizedBox(height: 14),
          _CacheCard(
            events: events.length,
            profiles: profiles.length,
            live: live,
          ),
          const SizedBox(height: 14),
          _SettingsCard(wifiOnly: wifiOnly),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection & sync status
// ---------------------------------------------------------------------------

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.sync, required this.live});

  final SyncState sync;
  final bool live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connColor = sync.online ? RadarTheme.radar : RadarTheme.alert;
    final connIcon = sync.online ? Icons.cloud_done : Icons.cloud_off;
    final connLabel = !sync.online
        ? (live ? 'Backend unreachable' : 'Demo mode (offline-first)')
        : sync.wifi
            ? 'Online · Wi-Fi'
            : 'Online · mobile data';

    final (healthColor, healthLabel) = switch (sync.health) {
      SyncHealth.synced => (RadarTheme.radar, 'All changes synced'),
      SyncHealth.pending =>
        (RadarTheme.gold, '${sync.pendingCount} item(s) waiting to push'),
      SyncHealth.offline => (RadarTheme.alert, 'Offline — writes queued'),
      SyncHealth.syncing => (RadarTheme.info, 'Syncing now…'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.wifi_tethering, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Connection & sync status',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Icon(connIcon, size: 18, color: connColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(connLabel,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          InfoPill(
            icon: sync.health == SyncHealth.syncing
                ? Icons.sync
                : Icons.check_circle_outline,
            label: healthLabel,
            color: healthColor,
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          sync.lastSync == null
              ? 'No sync completed yet this session.'
              : 'Last successful sync: ${DateFormat('d MMM · HH:mm:ss').format(sync.lastSync!)}',
          style:
               TextStyle(fontSize: 12, color: RadarTheme.textDim),
        ),
        if (sync.lastError != null) ...[
          const SizedBox(height: 4),
          Text(sync.lastError!,
              style:  TextStyle(fontSize: 12, color: RadarTheme.gold)),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Outbox — pending items & conflict resolution
// ---------------------------------------------------------------------------

class _OutboxCard extends ConsumerWidget {
  const _OutboxCard({required this.sync});

  final SyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(syncProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
           Icon(Icons.outbox_outlined, size: 17, color: RadarTheme.radar),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Synchronization queue',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          InfoPill(
            icon: Icons.hourglass_top,
            label:
                '${sync.pendingCount} pending · ${sync.conflictCount} conflict${sync.conflictCount == 1 ? '' : 's'}',
            color: sync.queue.isEmpty ? RadarTheme.textDim : RadarTheme.gold,
          ),
        ]),
        const SizedBox(height: 12),
        if (sync.queue.isEmpty)
           Text(
            'The outbox is empty. Mutations made while offline (or ones the '
            'backend rejects) wait here and push automatically when the '
            'connection returns.',
            style: TextStyle(
                fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
          )
        else
          for (final item in sync.queue)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RadarTheme.panelHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: item.hasConflict
                        ? RadarTheme.alert.withValues(alpha: 0.5)
                        : RadarTheme.stroke),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Icon(
                    item.hasConflict
                        ? Icons.error_outline
                        : Icons.schedule_send_outlined,
                    size: 16,
                    color: item.hasConflict
                        ? RadarTheme.alert
                        : RadarTheme.gold,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    DateFormat('HH:mm').format(item.createdAt),
                    style:  TextStyle(
                        fontSize: 11, color: RadarTheme.textDim),
                  ),
                ]),
                if (item.hasConflict) ...[
                  const SizedBox(height: 6),
                  Text('Conflict: ${item.conflict}',
                      style:  TextStyle(
                          fontSize: 11.5, color: RadarTheme.alert)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            notifier.resolve(item.id, retry: true),
                        icon: const Icon(Icons.refresh, size: 15),
                        label: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            notifier.resolve(item.id, retry: false),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: RadarTheme.alert),
                        icon: const Icon(Icons.delete_sweep, size: 15),
                        label: const Text('Discard'),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
        if (sync.queue.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => notifier.flush(),
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Sync now'),
            ),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Local cache inspector
// ---------------------------------------------------------------------------

class _CacheCard extends StatelessWidget {
  const _CacheCard({
    required this.events,
    required this.profiles,
    required this.live,
  });

  final int events;
  final int profiles;
  final bool live;

  @override
  Widget build(BuildContext context) {
    // Compute an indicative footprint of the in-memory mirror.
    final approxKb = (events * 1.2 + profiles * 0.9).ceil();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.inventory_2_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Local cache inspector',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        _kvRow('Cached event feed records', '$events events'),
        _kvRow('Offline profile records', '$profiles profiles'),
        _kvRow('Approximate mirror size', '$approxKb KB in memory'),
        _kvRow('Storage backend',
            live ? 'Device memory (per session)' : 'Demo seed (per session)'),
        const SizedBox(height: 6),
         Text(
          'The Radar keeps a read-through mirror of the event feed and '
          'directory so the map, search and inbox keep working when the '
          'network drops. It never stores credentials or Pi wallet data.',
          style: TextStyle(
              fontSize: 12, color: RadarTheme.textDim, height: 1.45),
        ),
      ]),
    );
  }

  Widget _kvRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          SizedBox(
              width: 190,
              child: Text(k,
                  style:  TextStyle(
                      fontSize: 12, color: RadarTheme.textDim))),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Offline storage settings
// ---------------------------------------------------------------------------

class _SettingsCard extends ConsumerWidget {
  const _SettingsCard({required this.wifiOnly});

  final bool wifiOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(syncProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.tune, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Offline storage settings',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: wifiOnly,
          onChanged: (v) => ref.read(wifiOnlyProvider.notifier).set(v),
          title: const Text('Download heavy data on Wi-Fi only',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle:  Text(
            'Restrict full feed refreshes and media prefetch to unmetered '
            'connections to conserve mobile bandwidth.',
            style: TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
          ),
        ),
         Divider(height: 22, color: RadarTheme.stroke),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: () async {
              final msg = await notifier.purgeStale();
              ref.invalidate(radarEventsProvider);
              ref.invalidate(profilesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating, content: Text(msg)));
              }
            },
            icon: const Icon(Icons.auto_delete_outlined, size: 16),
            label: const Text('Purge stale data'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final msg = await notifier.clearAllCaches();
              ref.invalidate(radarEventsProvider);
              ref.invalidate(profilesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating, content: Text(msg)));
              }
            },
            icon: const Icon(Icons.cleaning_services, size: 16),
            label: const Text('Clear all caches'),
          ),
        ]),
      ]),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
      color: RadarTheme.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: RadarTheme.stroke),
    );
