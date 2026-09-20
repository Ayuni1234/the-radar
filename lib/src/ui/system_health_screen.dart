import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../diagnostics/diagnostics.dart';
import '../state/radar_providers.dart';
import '../supabase/supabase_config.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// System Health & Admin Diagnostics — real-time backend sync, server
/// health, edge responsiveness, security posture, realtime channels and
/// cache/log tooling for technical administrators.
class SystemHealthScreen extends ConsumerStatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  ConsumerState<SystemHealthScreen> createState() =>
      _SystemHealthScreenState();
}

class _SystemHealthScreenState extends ConsumerState<SystemHealthScreen> {
  List<ProbeResult>? _probes;
  Map<String, Object?>? _security;
  String? _actionMessage;
  bool _running = false;
  int _lastLogCount = -1;

  @override
  void initState() {
    super.initState();
    _runProbes();
  }

  Future<void> _runProbes() async {
    setState(() => _running = true);
    final edgePing = SupabaseConfig.available
        ? () async {
            final res = await SupabaseConfig.functions
                .invoke('pi-session', body: {'__ping': true});
            return res.data is Map
                ? Map<String, Object?>.from(res.data as Map)
                : <String, Object?>{};
          }
        : null;
    final results = await Diagnostics.instance.probe(edgePing: edgePing);
    final security = await Diagnostics.instance.fetchSecurityDiagnostics();
    if (!mounted) return;
    setState(() {
      _probes = results;
      _security = security;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = SupabaseConfig.available;
    final logs = Diagnostics.instance.logs;
    final logCount = logs.length;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: const Text('System health'),
        actions: [
          IconButton(
            tooltip: 'Re-run diagnostics',
            onPressed: _running ? null : _runProbes,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.monitor_heart_outlined, size: 20),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          _ModeCard(live: live),
          const SizedBox(height: 14),

          // ------------------------------------------ connectivity monitor
          _SectionCard(
            icon: Icons.speed,
            title: 'Backend connectivity',
            trailing: TextButton(
              onPressed: _running ? null : _runProbes,
              child: const Text('Re-probe'),
            ),
            child: _probes == null
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Column(children: [
                    for (final p in _probes!) _ProbeTile(result: p),
                  ]),
          ),
          const SizedBox(height: 14),

          // ------------------------------------------ security checker
          _SectionCard(
            icon: Icons.security_outlined,
            title: 'RLS & security policy checker',
            child: _security == null
                ? Text(
                    live
                        ? 'Could not load security diagnostics — check the logs below.'
                        : 'Demo mode: connect Supabase to inspect live policies.',
                    style: const TextStyle(
                        fontSize: 12.5, color: RadarTheme.textDim),
                  )
                : _SecurityPosture(security: _security!),
          ),
          const SizedBox(height: 14),

          // ------------------------------------------ realtime channels
          _SectionCard(
            icon: Icons.sensors,
            title: 'Realtime subscriptions',
            child: Builder(builder: (context) {
              final channels = Diagnostics.instance.channels();
              if (channels.isEmpty) {
                return const Text(
                  'No active websocket channels. Live event/profile feeds '
                  'join automatically when their screens load.',
                  style: TextStyle(
                      fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
                );
              }
              return Column(children: [
                for (final c in channels)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: RadarTheme.panelHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: RadarTheme.stroke),
                    ),
                    child: Row(children: [
                      const Icon(Icons.sensors,
                          size: 16, color: RadarTheme.radar),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(c.topic,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace')),
                      ),
                      InfoPill(
                        icon: Icons.circle,
                        label: c.joined ? 'joined' : 'reconnecting',
                        color: c.joined
                            ? RadarTheme.radar
                            : RadarTheme.gold,
                      ),
                    ]),
                  ),
              ]);
            }),
          ),
          const SizedBox(height: 14),

          // ------------------------------------------ cache & controls
          _SectionCard(
            icon: Icons.build_circle_outlined,
            title: 'Diagnostics & cache controls',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  onPressed: _resetState,
                  icon: const Icon(Icons.cleaning_services, size: 16),
                  label: const Text('Clear caches / reset state'),
                ),
                OutlinedButton.icon(
                  onPressed: _refreshToken,
                  icon: const Icon(Icons.token, size: 16),
                  label: const Text('Refresh session token'),
                ),
                OutlinedButton.icon(
                  onPressed: _reconnectRealtime,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Reconnect realtime'),
                ),
              ]),
              if (_actionMessage != null) ...[
                const SizedBox(height: 10),
                Text(_actionMessage!,
                    style: const TextStyle(
                        fontSize: 12, color: RadarTheme.radar)),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          // ------------------------------------------ logs
          _SectionCard(
            icon: Icons.article_outlined,
            title: 'Recent system logs (${logCount > _lastLogCount && _lastLogCount >= 0 ? '+' : ''}${logCount - (_lastLogCount < 0 ? 0 : _lastLogCount)})',
            trailing: TextButton(
              onPressed: () => setState(() {
                Diagnostics.instance.clearLogs();
                _lastLogCount = 0;
              }),
              child: const Text('Clear'),
            ),
            child: logs.isEmpty
                ? const Text('No entries yet.',
                    style: TextStyle(
                        fontSize: 12.5, color: RadarTheme.textDim))
                : Column(children: [
                    for (final l in logs.reversed.take(40))
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 5),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: RadarTheme.ink,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: RadarTheme.stroke),
                        ),
                        child: Text(
                          '${DateFormat('HH:mm:ss').format(l.at)}  ${l.source.padRight(8)} ${l.message}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: RadarTheme.textDim),
                        ),
                      ),
                    if (logCount > 40)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Showing the 40 most recent of $logCount entries.',
                          style: const TextStyle(
                              fontSize: 11, color: RadarTheme.textDim),
                        ),
                      ),
                  ]),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _resetState() async {
    final msg = await Diagnostics.instance.resetClientState();
    // Rebuild every provider so the app refetches from a clean slate.
    ref.invalidate(radarEventsProvider);
    ref.invalidate(profilesProvider);
    if (!mounted) return;
    setState(() => _actionMessage = msg);
  }

  Future<void> _refreshToken() async {
    final msg = await Diagnostics.instance.refreshSession();
    setState(() => _actionMessage = msg);
  }

  Future<void> _reconnectRealtime() async {
    final msg = await Diagnostics.instance.reconnectRealtime();
    setState(() => _actionMessage = msg);
  }
}

// ---------------------------------------------------------------------------
// Cards & tiles
// ---------------------------------------------------------------------------

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: live
                ? RadarTheme.radar.withValues(alpha: 0.5)
                : RadarTheme.gold.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(live ? Icons.cloud_done : Icons.cloud_off,
            size: 19, color: live ? RadarTheme.radar : RadarTheme.gold),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            live
                ? 'Live Supabase project — diagnostics run against production'
                : 'Demo mode — Supabase not configured; probes are limited',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: RadarTheme.radar),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _ProbeTile extends StatelessWidget {
  const _ProbeTile({required this.result});

  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = result.ok
        ? (RadarTheme.radar, Icons.check_circle_outline)
        : (RadarTheme.alert, Icons.error_outline);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(result.name,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(
            result.detail ?? (result.ok ? 'operational' : 'unavailable'),
            style: const TextStyle(
                fontSize: 11.5, color: RadarTheme.textDim),
          ),
        ),
        if (result.latencyMs != null)
          InfoPill(
            icon: Icons.timer_outlined,
            label: '${result.latencyMs} ms',
            color: result.latencyMs! < 400
                ? RadarTheme.radar
                : result.latencyMs! < 1200
                    ? RadarTheme.gold
                    : RadarTheme.alert,
          ),
      ]),
    );
  }
}

class _SecurityPosture extends StatelessWidget {
  const _SecurityPosture({required this.security});

  final Map<String, Object?> security;

  @override
  Widget build(BuildContext context) {
    final tables = (security['tables'] as List?) ?? const [];
    final policies = (security['policies'] as List?) ?? const [];
    final triggers = (security['triggers'] as List?) ?? const [];
    final functions = (security['functions'] as List?) ?? const [];
    final realtimeTables = security['realtime_tables']?.toString() ?? '0';

    final rlsOn = tables
        .where((t) => (t as Map)['rls'] == true)
        .length;
    Widget section(String title, List items, Widget Function(Object) tile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: RadarTheme.textDim)),
        const SizedBox(height: 6),
        if (items.isEmpty)
          const Text('none found',
              style: TextStyle(fontSize: 12, color: RadarTheme.alert))
        else
          for (final item in items) tile(item),
        const SizedBox(height: 12),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoPill(
        icon: Icons.verified_user_outlined,
        label:
            'RLS enabled on $rlsOn/${tables.length} protected tables · realtime covers $realtimeTables/2 tables',
        color: rlsOn == tables.length ? RadarTheme.radar : RadarTheme.gold,
      ),
      const SizedBox(height: 12),
      section('Critical tables', tables, (item) {
        final m = item as Map;
        final ok = m['rls'] == true;
        return _checkRow('${m['table']}', ok ? 'RLS enabled' : 'RLS OFF', ok);
      }),
      section('Safety triggers', triggers, (item) {
        final m = item as Map;
        return _checkRow('${m['trigger']}',
            '${m['function']} on ${('${m['table']}').split('.').last} · ${m['enabled'] == true ? 'enabled' : 'DISABLED'}',
            m['enabled'] == true);
      }),
      section('Consent & identity functions', functions, (item) {
        final m = item as Map;
        return _checkRow('${m['function']}()', 'present', true);
      }),
      section('Policies (${policies.length})', policies.take(8).toList(),
          (item) {
        final m = item as Map;
        return _checkRow('${m['policy']}', '${m['table']} · ${m['cmd']}', true);
      }),
      if (policies.length > 8)
        Text('… and ${policies.length - 8} more policies.',
            style: const TextStyle(fontSize: 11.5, color: RadarTheme.textDim)),
    ]);
  }

  Widget _checkRow(String name, String detail, bool ok) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: RadarTheme.panelHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: Row(children: [
          Icon(ok ? Icons.check : Icons.close,
              size: 14, color: ok ? RadarTheme.radar : RadarTheme.alert),
          const SizedBox(width: 9),
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.3, fontWeight: FontWeight.w600)),
          ),
          Text(detail,
              style: const TextStyle(
                  fontSize: 10.8, color: RadarTheme.textDim)),
        ]),
      );
}
