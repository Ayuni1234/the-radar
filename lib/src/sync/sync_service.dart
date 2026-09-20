import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_seed.dart';
import '../data/radar_repository.dart';
import '../supabase/supabase_config.dart';
import 'sync_bridge.dart';

/// One queued mutation waiting to reach Supabase.
@immutable
class SyncItem {
  const SyncItem({
    required this.id,
    required this.kind,
    required this.label,
    required this.createdAt,
    this.conflict,
  });

  final String id;
  final String kind;
  final String label;
  final DateTime createdAt;

  /// Server rejection captured on the last flush attempt (conflict state).
  final String? conflict;

  bool get hasConflict => conflict != null;

  SyncItem withConflict(String? message) =>
      SyncItem(id: id, kind: kind, label: label, createdAt: createdAt, conflict: message);
}

/// Where the local mirror of remote data stands.
enum SyncHealth { synced, pending, offline, syncing }

@immutable
class SyncState {
  const SyncState({
    this.online = true,
    this.wifi = false,
    this.health = SyncHealth.synced,
    this.queue = const [],
    this.lastSync,
    this.lastError,
  });

  final bool online;
  final bool wifi;
  final SyncHealth health;
  final List<SyncItem> queue;
  final DateTime? lastSync;
  final String? lastError;

  int get pendingCount => queue.where((i) => !i.hasConflict).length;
  int get conflictCount => queue.where((i) => i.hasConflict).length;

  SyncState copyWith({
    bool? online,
    bool? wifi,
    SyncHealth? health,
    List<SyncItem>? queue,
    DateTime? lastSync,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncState(
        online: online ?? this.online,
        wifi: wifi ?? this.wifi,
        health: health ?? this.health,
        queue: queue ?? this.queue,
        lastSync: lastSync ?? this.lastSync,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Offline-first plumbing: reachability monitor + mutation outbox.
/// The app stays fully usable offline; writes land in the outbox and
/// flush automatically when connectivity returns.
class SyncService extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _flushing = false;

  @override
  SyncState build() {
    _listenConnectivity();
    // Failed writes reported by the data layer land in the outbox.
    SyncBridge.instance.addListener((kind, label, error) {
      enqueue(kind, label, conflict: error);
    });
    return SyncState(
      online: SupabaseConfig.available,
      health:
          SupabaseConfig.available ? SyncHealth.synced : SyncHealth.offline,
      lastSync: SupabaseConfig.available ? DateTime.now() : null,
    );
  }

  void _listenConnectivity() {
    _connSub?.cancel();
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((results) {
      final r = results.isEmpty
          ? ConnectivityResult.none
          : results.first;
      final online = r != ConnectivityResult.none && SupabaseConfig.available;
      final wifi = r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet;
      final wasOffline = !state.online;
      state = state.copyWith(
          online: online, wifi: wifi, health: online ? state.health : SyncHealth.offline);
      if (online && wasOffline && state.queue.isNotEmpty) {
        flush();
      }
    });
  }

  /// Queues a mutation for the backend (used when offline or on failure).
  void enqueue(String kind, String label, {String? conflict}) {
    state = state.copyWith(
      queue: [
        SyncItem(
          id: 'q-${DateTime.now().microsecondsSinceEpoch}',
          kind: kind,
          label: label,
          createdAt: DateTime.now(),
          conflict: conflict,
        ),
        ...state.queue,
      ],
      health: state.online ? SyncHealth.pending : state.health,
    );
  }

  /// Marks the newest queued item as conflicting (rejected server-side).
  void flagConflict(String message) {
    if (state.queue.isEmpty) return;
    final updated = [...state.queue];
    updated[0] = updated[0].withConflict(message);
    state = state.copyWith(queue: updated);
  }

  /// Force a manual sync: replays the outbox against the backend.
  Future<void> flush() async {
    if (_flushing || !SupabaseConfig.available) return;
    _flushing = true;
    state = state.copyWith(health: SyncHealth.syncing, clearError: true);

    final remaining = <SyncItem>[];
    var pushed = 0;
    for (final item in state.queue) {
      try {
        final ok = await _replay(item);
        if (ok) {
          pushed++;
        } else {
          remaining.add(item);
        }
      } catch (e) {
        remaining.add(item.withConflict('$e'));
      }
    }

    state = state.copyWith(
      queue: remaining,
      health: remaining.isEmpty ? SyncHealth.synced : SyncHealth.pending,
      lastSync: DateTime.now(),
      lastError: remaining.isEmpty ? null : '${remaining.length} item(s) still queued',
    );
    _flushing = false;
    debugPrint('[Sync] flush done: $pushed pushed, ${remaining.length} left');
  }

  Future<bool> _replay(SyncItem item) async {
    // Demo stores replay locally; live mode re-fires through the repo.
    switch (item.kind) {
      case 'profile_edit':
        return RadarRepository.instance.replayProfileEdit();
      case 'event_create':
        return RadarRepository.instance.replayEventCreate();
      default:
        // Unknown kinds cannot be replayed — drop them with a note.
        debugPrint('[Sync] unknown kind ${item.kind}, dropped');
        return true;
    }
  }

  /// Resolves a conflicted item: either retries it now or drops it.
  Future<void> resolve(String itemId, {required bool retry}) async {
    final item =
        state.queue.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    if (retry) {
      final ok = await _replay(item);
      state = state.copyWith(
        queue: ok
            ? state.queue.where((i) => i.id != itemId).toList()
            : state.queue
                .map((i) => i.id == itemId
                    ? i.withConflict('retry failed again')
                    : i)
                .toList(),
        health: ok && state.queue.length == 1
            ? SyncHealth.synced
            : state.health,
      );
    } else {
      state = state.copyWith(
        queue: state.queue.where((i) => i.id != itemId).toList(),
        health: state.queue.length <= 1 ? SyncHealth.synced : state.health,
      );
    }
  }

  // -- Cache/storage settings -----------------------------------------------

  /// Purges stale offline data (demo stores restored to seed).
  Future<String> purgeStale() async {
    DemoSeed.resetDemoStores();
    return 'Stale cached events, profiles and demo requests purged.';
  }

  Future<String> clearAllCaches() async =>
      RadarRepository.instance.clearCaches();

  void disposeLater() => _connSub?.cancel();
}

/// Whether the app may download heavy data over mobile data (off = Wi-Fi only).
final wifiOnlyProvider = NotifierProvider<WifiOnlyController, bool>(
    WifiOnlyController.new);

class WifiOnlyController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final syncProvider =
    NotifierProvider<SyncService, SyncState>(SyncService.new);
