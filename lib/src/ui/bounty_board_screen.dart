import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../analytics/tracking_session.dart';
import '../models/stream_bounty.dart';
import '../pi/pi_service.dart' show PiPaymentPhase;
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'blind_test_screen.dart';
import 'match_analytics_screen.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Scout Bounties — the "Talent Watcher" gig economy.
///
/// Scouts anywhere post Pi-backed bounties for live tactical streams of
/// grassroots matches; local videographers accept the gig, go live, and
/// the escrowed Pi is released to them on broadcast completion. Escrow is
/// real: funding runs through the Pi U2A flow, and release is a poster-only
/// SECURITY DEFINER RPC guarded by a database state-machine trigger.
class BountyBoardScreen extends ConsumerWidget {
  const BountyBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bountiesAsync = ref.watch(streamBountiesProvider);
    final session = ref.watch(sessionProvider);
    final signedIn = session?.profileId != null;
    final flow = ref.watch(paymentFlowProvider);

    final all = bountiesAsync.value ?? const <StreamBounty>[];
    final openGigs = all
        .where((b) => b.status == 'open' || b.status == 'funded')
        .toList();
    final myWork = all
        .where((b) =>
            session?.profileId != null &&
            (b.posterProfileId == session!.profileId ||
             b.streamerProfileId == session.profileId))
        .toList();

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: SafeArea(
        child: RefreshIndicator(
          color: RadarTheme.radar,
          backgroundColor: RadarTheme.panel,
          onRefresh: () => ref.read(streamBountiesProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: RadarTheme.ink.withValues(alpha: 0.96),
                title: Row(children: [
                  const Icon(Icons.workspace_premium,
                      color: RadarTheme.gold, size: 22),
                  const SizedBox(width: 8),
                  const Text('Talent Watcher',
                      style: TextStyle(
                          color: RadarTheme.textPrimary,
                          fontWeight: FontWeight.w700)),
                ]),
                actions: [
                  IconButton(
                    tooltip: 'Blind scouting test',
                    icon: const Icon(Icons.visibility_off, size: 19),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BlindTestScreen())),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _HowItWorksCard(onPost: () => _openPostSheet(context, ref)),
                ),
              ),
              if (flow.phase == PiPaymentPhase.completed)
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
              if (myWork.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionHeader('My bounties & gigs',
                      trailing: Text('${myWork.length}',
                          style: const TextStyle(
                              color: RadarTheme.textDim, fontSize: 12))),
                ),
                SliverList.builder(
                  itemCount: myWork.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _BountyCard(bounty: myWork[i]),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: SectionHeader('Open gigs',
                    trailing: Text('${openGigs.length} available',
                        style: const TextStyle(
                            color: RadarTheme.textDim, fontSize: 12))),
              ),
              if (openGigs.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.videocam_off_outlined,
                              size: 40, color: RadarTheme.textDim),
                          SizedBox(height: 10),
                          Text('No open gigs right now',
                              style: TextStyle(color: RadarTheme.textDim)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: openGigs.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _BountyCard(bounty: openGigs[i]),
                  ),
                ),
              if (!signedIn)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sign in to post bounties or accept streaming gigs.',
                      style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPostSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PostBountySheet(),
    );
  }
}

// ------------------------------------------------------------- how it works

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.onPost});

  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            RadarTheme.gold.withValues(alpha: 0.10),
            RadarTheme.panel,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.live_tv, color: RadarTheme.gold, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Pi-backed live-stream bounties',
                  style: TextStyle(
                      color: RadarTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: RadarTheme.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: onPost,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Post bounty',
                  style: TextStyle(fontSize: 12.5)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            '1 · A scout posts a bounty — Pi is escrowed up front through the '
            'Pi wallet.\n'
            '2 · A local videographer accepts and streams the match live.\n'
            '3 · On completion the scout releases the escrow — instant payout.',
            style: const TextStyle(
                color: RadarTheme.textDim, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- bounty card

class _BountyCard extends ConsumerStatefulWidget {
  const _BountyCard({required this.bounty});

  final StreamBounty bounty;

  @override
  ConsumerState<_BountyCard> createState() => _BountyCardState();
}

class _BountyCardState extends ConsumerState<_BountyCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.bounty;
    final session = ref.watch(sessionProvider);
    final myId = session?.profileId;
    final isPoster = myId == b.posterProfileId;
    final isStreamer = myId == b.streamerProfileId;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: b.isLive
              ? RadarTheme.radar.withValues(alpha: 0.6)
              : b.status == 'completed'
                  ? RadarTheme.radar.withValues(alpha: 0.25)
                  : RadarTheme.stroke,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: RadarTheme.gold.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.videocam,
                    color: RadarTheme.gold, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.title,
                        style: const TextStyle(
                            color: RadarTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text(
                      'by ${b.posterName} · ${b.areaName}',
                      style: const TextStyle(
                          color: RadarTheme.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_fmtPi(b.amountPi)} π',
                      style: const TextStyle(
                          color: RadarTheme.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 2),
                  Text('${b.durationMinutes} min',
                      style: const TextStyle(
                          color: RadarTheme.textDim, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(b.brief,
              style: const TextStyle(
                  color: RadarTheme.textPrimary,
                  fontSize: 13,
                  height: 1.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(
                icon: _statusIcon(b.status),
                label: b.statusLabel,
                color: _statusColor(b.status),
              ),
              if (b.kickoffAt != null)
                _pill(
                  icon: Icons.schedule,
                  label: DateFormat('EEE d MMM · HH:mm').format(b.kickoffAt!),
                  color: RadarTheme.info,
                ),
              if (b.streamerName != null)
                _pill(
                  icon: Icons.person,
                  label: 'Streamer: ${b.streamerName}',
                  color: RadarTheme.radar,
                ),
              if (b.status == 'open')
                _pill(
                  icon: Icons.lock_clock,
                  label: 'Not yet funded',
                  color: RadarTheme.textDim,
                ),
            ],
          ),
          if (b.isLive && b.streamUrl != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RadarTheme.radar.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: RadarTheme.radar.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.podcasts, color: RadarTheme.radar, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(b.streamUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: RadarTheme.radar, fontSize: 12)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          ..._actionRow(b, isPoster: isPoster, isStreamer: isStreamer),
        ],
      ),
    );
  }

  List<Widget> _actionRow(StreamBounty b,
      {required bool isPoster, required bool isStreamer}) {
    final actions = <Widget>[];

    switch (b.status) {
      case 'open':
        if (isPoster) {
          actions.add(_button(
            label: 'Fund escrow · ${_fmtPi(b.amountPi)} π',
            icon: Icons.lock,
            onPressed: _busy ? null : () => _fund(b),
            primary: true,
          ));
          actions.add(_button(
            label: 'Cancel',
            icon: Icons.close,
            onPressed: _busy ? null : () => _cancel(b),
          ));
        } else {
          actions.add(Text(
            'Awaiting scout funding — first come, first served once funded.',
            style: const TextStyle(color: RadarTheme.textDim, fontSize: 12),
          ));
        }
        break;
      case 'funded':
        if (!isPoster) {
          actions.add(_button(
            label: 'Accept gig · earn ${_fmtPi(b.amountPi)} π',
            icon: Icons.back_hand,
            onPressed: _busy ? null : () => _accept(b),
            primary: true,
          ));
        } else {
          actions.add(const Text(
            'Escrow held — waiting for a local streamer to accept.',
            style: TextStyle(color: RadarTheme.textDim, fontSize: 12),
          ));
        }
        break;
      case 'accepted':
        if (isStreamer) {
          actions.add(_button(
            label: 'I\'m live — post stream link',
            icon: Icons.podcasts,
            onPressed: _busy ? null : () => _goLive(b),
            primary: true,
          ));
        } else {
          actions.add(Text(
            '${b.streamerName ?? 'A streamer'} is assigned — broadcast pending.',
            style: const TextStyle(color: RadarTheme.textDim, fontSize: 12),
          ));
        }
        break;
      case 'live':
        if (isStreamer) {
          actions.add(_button(
            label: 'Broadcast finished',
            icon: Icons.flag,
            onPressed: _busy ? null : () => _finish(b),
          ));
        }
        if (isPoster) {
          actions.add(_button(
            label: 'Release ${_fmtPi(b.amountPi)} π to streamer',
            icon: Icons.payment,
            onPressed: _busy ? null : () => _release(b),
            primary: true,
          ));
        }
        if (actions.isEmpty) {
          actions.add(const Row(children: [
            Icon(Icons.podcasts, color: RadarTheme.radar, size: 15),
            SizedBox(width: 6),
            Text('Broadcast in progress — watch from the stream link.',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
          ]));
        }
        actions.add(_button(
          label: 'Live tracking report',
          icon: Icons.radar,
          onPressed: () => _openAnalytics(b),
        ));
        break;
      case 'completed':
        actions.add(Row(children: [
          const Icon(Icons.verified, color: RadarTheme.radar, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Escrow released · ${b.watchedMinutes} min streamed'
              '${b.completedAt != null ? ' · ${DateFormat.MMMd().format(b.completedAt!)}' : ''}',
              style: const TextStyle(color: RadarTheme.radar, fontSize: 12),
            ),
          ),
        ]));
        actions.add(_button(
          label: 'Match analytics report',
          icon: Icons.query_stats,
          onPressed: () => _openAnalytics(b),
          primary: false,
        ));
        break;
      default:
        actions.add(Text(
          'This bounty is ${b.statusLabel.toLowerCase()}.',
          style: const TextStyle(color: RadarTheme.textDim, fontSize: 12),
        ));
    }

    return [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in actions) a,
      ]),
    ];
  }

  void _openAnalytics(StreamBounty b) {
    final session = TrackingSession.synthetic(
      id: 'track-${b.id}',
      bountyId: b.id,
      playerLabel: _playerFromTitle(b.title),
      durationMin: b.durationMinutes.clamp(15, 90),
      seed: b.id.hashCode & 0x7fffffff,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MatchAnalyticsScreen(bounty: b, session: session),
    ));
  }

  /// Derives the tracked-player label from the bounty wording ("Player #7…").
  String _playerFromTitle(String title) {
    final match = RegExp(r'Player\s*#?(\d+)').firstMatch(title);
    if (match != null) return 'Player #${match.group(1)} — CV jersey lock';
    return 'Target player — CV jersey lock';
  }

  String _fmtPi(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _button({
    required String label,
    required IconData icon,
    VoidCallback? onPressed,
    bool primary = false,
  }) =>
      primary
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: RadarTheme.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: onPressed,
              icon: Icon(icon, size: 15),
              label: Text(label, style: const TextStyle(fontSize: 12.5)),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: RadarTheme.textDim,
                side: const BorderSide(color: RadarTheme.stroke),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: onPressed,
              icon: Icon(icon, size: 15),
              label: Text(label, style: const TextStyle(fontSize: 12.5)),
            );

  Color _statusColor(String status) => switch (status) {
        'open' => RadarTheme.textDim,
        'funded' => RadarTheme.gold,
        'accepted' => RadarTheme.info,
        'live' => RadarTheme.radar,
        'completed' => RadarTheme.radar,
        'disputed' => RadarTheme.alert,
        _ => RadarTheme.textDim,
      };

  IconData _statusIcon(String status) => switch (status) {
        'open' => Icons.hourglass_empty,
        'funded' => Icons.account_balance_wallet,
        'accepted' => Icons.back_hand,
        'live' => Icons.podcasts,
        'completed' => Icons.check_circle,
        'disputed' => Icons.gavel,
        _ => Icons.help_outline,
      };

  Future<void> _fund(StreamBounty b) async {
    ref
        .read(streamBountiesProvider.notifier)
        .fundBounty(b.id, b.amountPi, b.title);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHigh,
      content: Text(
          'Opening your Pi wallet to escrow ${_fmtPi(b.amountPi)} π…',
          style: const TextStyle(color: RadarTheme.textPrimary)),
    ));
  }

  Future<void> _cancel(StreamBounty b) async {
    setState(() => _busy = true);
    await ref.read(streamBountiesProvider.notifier).cancelBounty(b.id);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _accept(StreamBounty b) async {
    setState(() => _busy = true);
    final ok = await ref.read(streamBountiesProvider.notifier).acceptBounty(b.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHigh : RadarTheme.alert,
      content: Text(ok
          ? 'Gig accepted — head to the pitch and go live before kickoff ends'
          : 'Could not accept — someone may have claimed it first'),
    ));
  }

  Future<void> _goLive(StreamBounty b) async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: b.streamUrl ?? '');
        return AlertDialog(
          backgroundColor: RadarTheme.panelHigh,
          title: const Text('Your live stream link'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Pi Media / YouTube live / any stable link'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Go live')),
          ],
        );
      },
    );
    if (url == null) return;
    setState(() => _busy = true);
    await ref.read(streamBountiesProvider.notifier).goLive(b.id, url);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish(StreamBounty b) async {
    setState(() => _busy = true);
    await ref
        .read(streamBountiesProvider.notifier)
        .finishBroadcast(b.id, b.durationMinutes);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHigh,
      content: Text(
          'Broadcast logged — the scout can now release your payout'),
    ));
  }

  Future<void> _release(StreamBounty b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RadarTheme.panelHigh,
        title: const Text('Release escrow?'),
        content: Text(
            'Release ${_fmtPi(b.amountPi)} π to ${b.streamerName ?? 'the streamer'} '
            'for the completed broadcast? This pays out the bounty.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RadarTheme.gold,
                  foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Release & pay')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final (ok, message) =
        await ref.read(streamBountiesProvider.notifier).releaseEscrow(b.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHigh : RadarTheme.alert,
      content: Text(message),
    ));
  }
}

// ------------------------------------------------------------ post bounty UI

class _PostBountySheet extends ConsumerStatefulWidget {
  const _PostBountySheet();

  @override
  ConsumerState<_PostBountySheet> createState() => _PostBountySheetState();
}

class _PostBountySheetState extends ConsumerState<_PostBountySheet> {
  final _titleCtrl = TextEditingController();
  final _briefCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();
  double _amount = 50;
  int _duration = 90;
  DateTime _kickoff = DateTime.now().add(const Duration(days: 1));
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _briefCtrl.dispose();
    _areaCtrl.dispose();
    _venueCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _briefCtrl.text.trim().isEmpty ||
        _areaCtrl.text.trim().isEmpty ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    final bountyId = await ref.read(streamBountiesProvider.notifier).postBounty(
          title: _titleCtrl.text,
          brief: _briefCtrl.text,
          areaName: _areaCtrl.text,
          venueName: _venueCtrl.text,
          amountPi: _amount,
          durationMinutes: _duration,
          kickoffAt: _kickoff,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context);
    if (bountyId != null) {
      // Straight into the escrow payment — the gig only becomes claimable
      // once the Pi is held.
      ref
          .read(streamBountiesProvider.notifier)
          .fundBounty(bountyId, _amount, _titleCtrl.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHigh,
        content: Text(
            'Bounty posted — confirm the ${_amount.toStringAsFixed(0)} π escrow in your Pi wallet',
            style: const TextStyle(color: RadarTheme.textPrimary)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      decoration: const BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.workspace_premium,
                  color: RadarTheme.gold, size: 20),
              const SizedBox(width: 8),
              const Text('Post a stream bounty',
                  style: TextStyle(
                      color: RadarTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Pi is escrowed from your wallet now and released to the '
              'streamer when you confirm the broadcast.',
              style: TextStyle(color: RadarTheme.textDim, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText:
                    'e.g. “90-min tactical stream of Player #7 — Thursday match”',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _briefCtrl,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText:
                    'Camera angle, player to track, upload stability, kickoff time…',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _areaCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Area, e.g. “Limbe — Omnisport Annex”',
                prefixIcon: Icon(Icons.place_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _venueCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Venue (optional)',
                prefixIcon: Icon(Icons.stadium_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Escrow',
                  style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
              const Spacer(),
              Text('${_amount.toStringAsFixed(0)} π',
                  style: const TextStyle(
                      color: RadarTheme.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ]),
            Slider(
              value: _amount,
              min: 5,
              max: 500,
              divisions: 99,
              label: '${_amount.toStringAsFixed(0)} π',
              activeColor: RadarTheme.gold,
              onChanged: (v) => setState(() => _amount = v),
            ),
            const SizedBox(height: 6),
            const Text('Stream length (minutes)',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            Slider(
              value: _duration.toDouble(),
              min: 15,
              max: 180,
              divisions: 11,
              label: '$_duration min',
              activeColor: RadarTheme.radar,
              onChanged: (v) => setState(() => _duration = v.round()),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _kickoff,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_kickoff),
                );
                if (time != null) {
                  setState(() => _kickoff =
                      DateTime(date.year, date.month, date.day, time.hour, time.minute));
                }
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text(DateFormat('EEE d MMM · HH:mm').format(_kickoff)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: RadarTheme.gold,
                foregroundColor: Colors.black,
              ),
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.workspace_premium, size: 18),
              label: const Text('Post & escrow Pi'),
            ),
          ],
        ),
      ),
    );
  }
}
