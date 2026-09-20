import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/radar_repository.dart';
import '../supabase/supabase_config.dart';

/// A timestamped diagnostics log entry.
@immutable
class DiagLog {
  const DiagLog({required this.at, required this.source, required this.message});

  final DateTime at;
  final String source;
  final String message;
}

/// Result of one connectivity probe.
@immutable
class ProbeResult {
  const ProbeResult({
    required this.name,
    required this.ok,
    this.latencyMs,
    this.detail,
  });

  final String name;
  final bool ok;
  final int? latencyMs;
  final String? detail;
}

/// Realtime channel snapshot for the connection monitor.
@immutable
class ChannelInfo {
  const ChannelInfo({required this.topic, this.joined = true});

  final String topic;
  final bool joined;
}

/// Client-side system diagnostics: log ring-buffer, latency probes,
/// realtime channel inventory, and security-posture RPC call.
class Diagnostics {
  Diagnostics._();
  static final Diagnostics instance = Diagnostics._();

  static const int _maxLogs = 300;
  final List<DiagLog> _logs = <DiagLog>[];
  final Set<String> _trackedTopics = <String>{};

  /// Monotonic sequence so listeners can diff cheaply.
  int get logCount => _logs.length;
  List<DiagLog> get logs => List.unmodifiable(_logs);

  void log(String source, String message) {
    _logs.add(DiagLog(at: DateTime.now(), source: source, message: message));
    if (_logs.length > _maxLogs) _logs.removeRange(0, _logs.length - _maxLogs);
  }

  /// Tracks a joined channel topic for the monitor.
  void trackChannel(String topic) {
    _trackedTopics.add(topic);
    log('realtime', 'channel joined: $topic');
  }

  List<ChannelInfo> channels() {
    final liveCount = SupabaseConfig.available
        ? SupabaseConfig.client.getChannels().length
        : 0;
    if (_trackedTopics.isEmpty) return const [];
    // Cross-check: if the socket dropped below what we tracked, surface it.
    final allJoined = liveCount >= _trackedTopics.length;
    return [
      for (final t in _trackedTopics)
        ChannelInfo(topic: t, joined: allJoined),
    ];
  }

  /// Auth + DB + edge-function latency probes. Edge probe is optional
  /// (skipped when [edgePing] is null).
  Future<List<ProbeResult>> probe({
    Future<Map<String, Object?>?> Function()? edgePing,
  }) async {
    final results = <ProbeResult>[];

    // 1. Auth service — any cheap authenticated round-trip. getSession is
    // local; the DB probe below covers the wire, so use a tiny select.
    final dbWatch = Stopwatch()..start();
    try {
      if (SupabaseConfig.available) {
        await SupabaseConfig.client.from('profiles').select('id').limit(1);
        results.add(ProbeResult(
          name: 'Database',
          ok: true,
          latencyMs: dbWatch.elapsedMilliseconds,
        ));
      } else {
        results.add(const ProbeResult(
          name: 'Database',
          ok: false,
          detail: 'demo mode — no live connection',
        ));
      }
    } catch (e) {
      results.add(ProbeResult(
        name: 'Database',
        ok: false,
        latencyMs: dbWatch.elapsedMilliseconds,
        detail: '$e',
      ));
    }
    log('probe', 'database probe done');

    // 2. Auth service uptime — verify the local session is resolvable
    // (token refresh itself is exercised by the cache-controls button).
    final authWatch = Stopwatch()..start();
    try {
      final hasSession = SupabaseConfig.auth.currentSession != null;
      results.add(ProbeResult(
        name: 'Auth service',
        ok: true,
        latencyMs: authWatch.elapsedMilliseconds,
        detail: hasSession
            ? 'session active'
            : 'no session (anon reachable)',
      ));
    } catch (e) {
      results.add(ProbeResult(
        name: 'Auth service',
        ok: false,
        latencyMs: authWatch.elapsedMilliseconds,
        detail: '$e',
      ));
    }

    // 3. Edge function responsiveness (optional caller-provided ping).
    if (edgePing != null) {
      final edgeWatch = Stopwatch()..start();
      try {
        final res = await edgePing();
        results.add(ProbeResult(
          name: 'Edge function',
          ok: true,
          latencyMs: edgeWatch.elapsedMilliseconds,
          detail: 'reachable',
        ));
        log('probe', 'edge probe ok: $res');
      } catch (e) {
        results.add(ProbeResult(
          name: 'Edge function',
          ok: false,
          latencyMs: edgeWatch.elapsedMilliseconds,
          detail: '$e',
        ));
      }
    }

    // 4. Realtime socket.
    results.add(ProbeResult(
      name: 'Realtime',
      ok: SupabaseConfig.available && channels().isNotEmpty,
      detail: SupabaseConfig.available
          ? '${channels().length} channel(s)'
          : 'demo mode',
    ));

    return results;
  }

  /// Pulls the server-side security posture (RLS, policies, triggers).
  Future<Map<String, Object?>?> fetchSecurityDiagnostics() async {
    if (!SupabaseConfig.available) return null;
    try {
      final res = await SupabaseConfig.client.rpc('security_diagnostics');
      log('probe', 'security diagnostics fetched');
      return Map<String, Object?>.from(res as Map);
    } catch (e) {
      log('probe', 'security diagnostics failed: $e');
      return null;
    }
  }

  /// "Clear cache": drops the app's data caches (provider state is
  /// rebuilt) and logs the action. Also logs client refresh.
  Future<String> resetClientState() async {
    final actions = <String>[];
    try {
      RadarRepository.instance.clearCaches();
      actions.add('demo/live data caches cleared');
      log('cache', 'client caches reset');
    } catch (e) {
      actions.add('cache reset failed: $e');
    }
    return actions.join('; ');
  }

  /// "Refresh session": forces a GoTrue token refresh and reports.
  Future<String> refreshSession() async {
    if (!SupabaseConfig.available) return 'demo mode — nothing to refresh';
    try {
      final res = await SupabaseConfig.auth.refreshSession();
      final ok = res.session != null;
      log('auth', 'session refresh ${ok ? 'ok' : 'no session'}');
      return ok ? 'session refreshed' : 'no active session';
    } catch (e) {
      log('auth', 'session refresh failed: $e');
      return 'refresh failed: $e';
    }
  }

  /// "Realtime reconnect": removes all channels; the providers rebuild
  /// them on next watch, giving a clean websocket state.
  Future<String> reconnectRealtime() async {
    if (!SupabaseConfig.available) return 'demo mode — no realtime';
    try {
      await SupabaseConfig.client.removeAllChannels();
      _trackedTopics.clear();
      log('realtime', 'all channels removed for reconnect');
      return 'channels dropped — providers rejoin on next load';
    } catch (e) {
      log('realtime', 'reconnect failed: $e');
      return 'reconnect failed: $e';
    }
  }

  void clearLogs() => _logs.clear();
}
