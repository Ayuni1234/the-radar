import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/feed_post.dart' show distanceKm;
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../pi/pi_service.dart' show PiPaymentPhase;
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'blind_test_screen.dart';
import 'bounty_fulfillment_flow.dart';
import 'design/radar_design.dart';
import 'match_analytics_screen.dart';
import 'radar_theme.dart';
import 'radar_top_bar.dart';
import 'sheet_scaffold.dart';
import '../analytics/tracking_session.dart';

/// π Bounties — the uploaded "Pi Bounty Gig Hub" design.
///
/// Scout-funded escrows are listed as operator gigs. Every card opens the
/// four-step fulfilment flow (GPS check-in → record → upload → request
/// payment); releasing the escrow itself stays on the scout side, in the
/// Review tab.
class BountyBoardScreen extends ConsumerWidget {
  const BountyBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bountiesAsync = ref.watch(streamBountiesProvider);
    final session = ref.watch(sessionProvider);
    final flow = ref.watch(paymentFlowProvider);
    final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];

    final all = bountiesAsync.value ?? const <StreamBounty>[];
    final funded = all.where((b) => b.isFunded).toList();
    final completed = all.where((b) => b.status == 'completed').toList();
    final earnings = completed.fold<double>(0, (sum, b) => sum + b.amountPi);

    UserProfile? me;
    for (final p in profiles) {
      if (p.id == session?.profileId) {
        me = p;
        break;
      }
    }

    // Unfunded posts stay off the streamer board until their escrow is paid.
    final entries = funded;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: RefreshIndicator(
        color: RadarTheme.radar,
        backgroundColor: RadarTheme.panel,
        onRefresh: () => ref.read(streamBountiesProvider.notifier).refresh(),
        child: Column(
          children: [
            RadarTopBar(
              onAvatarTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const _OperatorProfileSheet()),
              ),
              onBalanceTap: () => _showWallet(context, earnings),
              trailing: IconButton(
                tooltip: 'Blind scouting test',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const BlindTestScreen()),
                ),
                icon: Icon(Icons.visibility_off_outlined,
                    size: 19, color: RadarTheme.textDim),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  _OperatorHeader(
                    session: session,
                    earnings: earnings,
                    completed: completed.length,
                    reputation: me?.credibilityScore ?? 0,
                  ),
                  const SizedBox(height: 12),
                  _ProximityRadar(count: funded.length),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'OPEN MATCH ESCROWS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RadarType.heading(
                            22,
                            weight: FontWeight.w700,
                            color: const Color(0xFFF0FFEE),
                            tracking: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: RadarTheme.radar.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'LIVE',
                          style: RadarType.capsTight.copyWith(
                            fontSize: 8.5,
                            color: RadarTheme.radar,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      RadarCaps(
                        'AUTO-REFRESH 10s',
                        size: 8,
                        color: RadarTheme.textDim,
                        tracking: 0.6,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (flow.phase == PiPaymentPhase.completed) ...[
                    _EscrowBanner(
                      message: flow.message ?? 'Escrow secured in your wallet.',
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (entries.isEmpty)
                    _EmptyBounties(
                      onPost: () => showPostBountySheet(context),
                    )
                  else
                    for (final (i, bounty) in entries.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: i == 0
                            ? _FeaturedEscrowCard(
                                bounty: bounty,
                                profiles: profiles,
                                session: session,
                                urgent: _isUrgent(bounty),
                              )
                            : _CompactEscrowCard(
                                bounty: bounty,
                                session: session,
                              ),
                      ),
                  const SizedBox(height: 6),
                  const _HowOperatorBountiesWork(),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => showPostBountySheet(context),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Post a new Pi bounty'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isUrgent(StreamBounty b) {
    final k = b.kickoffAt;
    if (k == null) return false;
    final d = k.difference(DateTime.now());
    return !d.isNegative && d.inMinutes <= 60;
  }

  static void _showWallet(BuildContext context, double earnings) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RadarTheme.panel,
      shape: const RoundedRectangleBorder(borderRadius: RadarRadius.sheetTop),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RadarSectionTitle(title: 'Escrow wallet'),
            const SizedBox(height: 12),
            Text(
              '${fmtPi(earnings)} π',
              style: RadarType.metricLg.copyWith(color: RadarTheme.goldBright),
            ),
            const SizedBox(height: 4),
            Text(
              'Released operator earnings. Escrow held for open gigs is '
              'released by the scout from the Review tab.',
              style: RadarType.bodySm.copyWith(color: RadarTheme.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperatorProfileSheet extends StatelessWidget {
  const _OperatorProfileSheet();

  @override
  Widget build(BuildContext context) {
    return const _SimpleSheet(
      title: 'Operator profile',
      body:
          'Camera pioneers complete the four-step fulfilment flow for every '
          'claimed gig. Reputation is earned from scout-approved deliveries.',
    );
  }
}

class _SimpleSheet extends StatelessWidget {
  const _SimpleSheet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: RadarRadius.sheetTop,
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadarSectionTitle(title: title),
          const SizedBox(height: 10),
          Text(body,
              style: RadarType.bodySm.copyWith(
                  color: RadarTheme.textDim, height: 1.5)),
        ],
      ),
    );
  }
}

class _OperatorHeader extends StatelessWidget {
  const _OperatorHeader({
    required this.session,
    required this.earnings,
    required this.completed,
    required this.reputation,
  });

  final RadarSession? session;
  final double earnings;
  final int completed;
  final double reputation;

  @override
  Widget build(BuildContext context) {
    final verified = session?.kycVerified ?? false;
    return RadarPanel(
      padding: const EdgeInsets.all(14),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          RadarTheme.panel,
          RadarTheme.panel.withValues(alpha: 0.92),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const LiveDot(size: 9, animate: false),
              const SizedBox(width: 6),
              Flexible(
                child: RadarCaps(
                  'Status: Available to Film',
                  size: 9.5,
                  color: RadarTheme.radar,
                  tracking: 1.0,
                ),
              ),
              const Spacer(),
              Icon(
                verified ? Icons.verified : Icons.verified_outlined,
                size: 13,
                color:
                    verified ? RadarTheme.goldBright : RadarTheme.textFaint,
              ),
              const SizedBox(width: 4),
              Text(
                verified ? 'Verified Pi Pioneer' : 'Pi Pioneer',
                style: RadarType.capsTight.copyWith(
                  fontSize: 8.5,
                  color: RadarTheme.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: 'My Filming Earnings',
                  trailing: 'ESCROW SECURE',
                  value: '${fmtPi(earnings)} π',
                  suffix: '~${(earnings * 31.5).toStringAsFixed(0)} USD',
                  accent: RadarTheme.goldBright,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricBox(
                  label: 'Reputation Score',
                  trailing: '',
                  value: '${reputation.toStringAsFixed(0)}%',
                  suffix: '$completed Matched',
                  accent: const Color(0xFFF0FFEE),
                  icon: Icons.speed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.trailing,
    required this.value,
    required this.suffix,
    required this.accent,
    this.icon,
  });

  final String label;
  final String trailing;
  final String value;
  final String suffix;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(RadarRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RadarCaps(label, size: 8.5, tracking: 0.6),
              ),
              if (icon != null)
                Icon(icon, size: 13, color: RadarTheme.radar)
              else
                RadarCaps(
                  trailing,
                  size: 7.5,
                  color: RadarTheme.goldBright,
                  tracking: 0.4,
                ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: RadarType.metricLg.copyWith(
                    fontSize: 24,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  suffix,
                  style: RadarType.bodySm.copyWith(
                    fontSize: 9.5,
                    color: RadarTheme.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProximityRadar extends StatelessWidget {
  const _ProximityRadar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final total = count;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(RadarRadius.sheet),
        boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 12)],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: RadarTheme.panelLowest,
              borderRadius: BorderRadius.circular(RadarRadius.card),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.radar,
                      size: 24, color: RadarTheme.cyanDeep),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: LiveDot(size: 5, color: RadarTheme.cyanDeep, animate: false),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadarCaps(
                  'HUD Range • 5 KM Radius',
                  size: 8.5,
                  color: RadarTheme.cyanDeep,
                  tracking: 1.0,
                ),
                const SizedBox(height: 2),
                Text(
                  '$total High-Value ${total == 1 ? 'Bounty' : 'Bounties'} active nearby',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.heading(
                    18,
                    weight: FontWeight.w600,
                    color: RadarTheme.textPrimary,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.tune, size: 19, color: RadarTheme.textDim),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

class _EscrowBadge extends StatelessWidget {
  const _EscrowBadge({required this.amount, this.label = 'Payout Escrow'});

  final double amount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(RadarRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          RadarCaps(label, size: 8, tracking: 0.5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fmtPi(amount),
                style: RadarType.metricLg.copyWith(
                  fontSize: 20,
                  color: RadarTheme.goldBright,
                ),
              ),
              const SizedBox(width: 2),
              Text('π',
                  style: RadarType.heading(15,
                      weight: FontWeight.w600,
                      color: RadarTheme.goldBright)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturedEscrowCard extends ConsumerStatefulWidget {
  const _FeaturedEscrowCard({
    required this.bounty,
    required this.profiles,
    required this.session,
    required this.urgent,
  });

  final StreamBounty bounty;
  final List<UserProfile> profiles;
  final RadarSession? session;
  final bool urgent;

  @override
  ConsumerState<_FeaturedEscrowCard> createState() =>
      _FeaturedEscrowCardState();
}

class _FeaturedEscrowCardState extends ConsumerState<_FeaturedEscrowCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.bounty;
    UserProfile? poster;
    for (final p in widget.profiles) {
      if (p.id == b.posterProfileId) {
        poster = p;
        break;
      }
    }
    final kickoff = b.kickoffAt;
    final remaining = kickoff?.difference(DateTime.now());
    final urgencyLabel = remaining == null
        ? 'ESCROW HELD'
        : (remaining.isNegative
            ? 'LIVE NOW'
            : 'KICKOFF IN ${_short(remaining).toUpperCase()}');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(RadarRadius.sheet),
        boxShadow: const [
          BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: widget.urgent
                ? const Color(0xFF93000A)
                : RadarTheme.panelHighest,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                Icon(
                  widget.urgent ? Icons.crisis_alert : Icons.lock_clock,
                  size: 15,
                  color: widget.urgent
                      ? const Color(0xFFFFDAD6)
                      : RadarTheme.goldBright,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.urgent
                        ? 'URGENT • $urgencyLabel'
                        : 'FUNDED ESCROW • $urgencyLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RadarType.caps.copyWith(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      color: widget.urgent
                          ? const Color(0xFFFFDAD6)
                          : RadarTheme.goldBright,
                    ),
                  ),
                ),
                Text(
                  'PITCH SLOT #${(b.id.hashCode.abs() % 9) + 1}',
                  style: RadarType.capsTight.copyWith(
                    fontSize: 8,
                    color: widget.urgent
                        ? const Color(0xB3FFDAD6)
                        : RadarTheme.textDim,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          RadarAvatar(
                            name: b.posterName,
                            url: poster?.avatarUrl,
                            size: 38,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        b.posterName.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: RadarType.caps.copyWith(
                                          fontSize: 9,
                                          color: RadarTheme.cyanDeep,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(Icons.star,
                                        size: 11,
                                        color: RadarTheme.goldBright),
                                    const SizedBox(width: 2),
                                    Text(
                                      (poster?.rating ?? 4.5)
                                          .toStringAsFixed(1),
                                      style: RadarType.capsTight.copyWith(
                                        fontSize: 8.5,
                                        color: RadarTheme.goldBright,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Verified European Scouting Network',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: RadarType.bodySm.copyWith(
                                    fontSize: 10,
                                    color: RadarTheme.textDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _EscrowBadge(amount: b.amountPi),
                  ],
                ),
                const SizedBox(height: 12),
                _ProspectPreview(bounty: b),
                const SizedBox(height: 10),
                _TelemetrySpecs(bounty: b),
                const SizedBox(height: 12),
                RadarPrimaryButton(
                  label: 'Claim bounty & navigate to pitch',
                  icon: _busy ? Icons.sync : Icons.lock_open,
                  height: 48,
                  onPressed: _busy ? null : () => _claim(b),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _claim(StreamBounty b) async {
    setState(() => _busy = true);
    if (b.status == 'funded') {
      await ref.read(streamBountiesProvider.notifier).acceptBounty(b.id);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BountyFulfillmentFlow(bounty: b),
    ));
  }
}

class _ProspectPreview extends StatelessWidget {
  const _ProspectPreview({required this.bounty});

  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(RadarRadius.card),
      child: SizedBox(
        height: 128,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: RadarTheme.panelHighest,
              child: CustomPaint(
                painter: TacticalGridPainter(spacing: 28),
              ),
            ),
            // Floodlit pitch suggestion, drawn rather than photographed so it
            // renders identically offline in the Pi Browser.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.2, -0.4),
                    radius: 1.1,
                    colors: [
                      RadarTheme.radar.withValues(alpha: 0.16),
                      RadarTheme.panelLowest.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      RadarTheme.panelLowest.withValues(alpha: 0),
                      RadarTheme.panelLowest.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadarCaps(
                    'PROSPECT FOCUS',
                    size: 8.5,
                    color: RadarTheme.greenDeep,
                    tracking: 1.0,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bounty.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RadarType.heading(
                      19,
                      weight: FontWeight.w600,
                      color: const Color(0xFFF0FFEE),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.pin_drop_outlined,
                          size: 12, color: RadarTheme.cyanDeep),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          bounty.venueName ?? bounty.areaName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RadarType.bodySm.copyWith(
                            fontSize: 10,
                            color: RadarTheme.cyanDeep,
                          ),
                        ),
                      ),
                      if (bounty.kickoffAt != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.schedule,
                            size: 12, color: RadarTheme.radar),
                        const SizedBox(width: 3),
                        Text(
                          DateFormat('EEE d MMM • HH:mm')
                              .format(bounty.kickoffAt!),
                          style: RadarType.bodySm.copyWith(
                            fontSize: 10,
                            color: RadarTheme.textPrimary,
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
    );
  }
}

class _TelemetrySpecs extends StatelessWidget {
  const _TelemetrySpecs({required this.bounty});

  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    final specs = <(IconData, String)>[
      (Icons.videocam_outlined, '1080p 60FPS or 4K'),
      (Icons.straighten, 'Midfield Elevation'),
      (Icons.timer_outlined, '${bounty.durationMinutes}m Uncut Tape'),
      (Icons.hardware_outlined, 'Tripod Recommended'),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(RadarRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadarCaps(
            'Scout Telemetry Specs',
            size: 8.5,
            color: RadarTheme.textDim,
            tracking: 0.8,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              for (final (icon, label) in specs)
                SizedBox(
                  width: 138,
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: RadarTheme.radar),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RadarType.capsTight.copyWith(
                            fontSize: 9,
                            color: RadarTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactEscrowCard extends ConsumerStatefulWidget {
  const _CompactEscrowCard({
    required this.bounty,
    required this.session,
  });

  final StreamBounty bounty;
  final RadarSession? session;

  @override
  ConsumerState<_CompactEscrowCard> createState() =>
      _CompactEscrowCardState();
}

class _CompactEscrowCardState extends ConsumerState<_CompactEscrowCard> {
  @override
  Widget build(BuildContext context) {
    final b = widget.bounty;
    final remaining = b.kickoffAt?.difference(DateTime.now());
    final standby = b.isFunded;
    final tag = standby ? 'STANDBY SLOT' : 'AWAITING FUNDING';
    final kickoff = remaining == null
        ? ''
        : (remaining.isNegative ? 'LIVE NOW' : 'KICKOFF IN ${_short(remaining).toUpperCase()}');
    final lat = widget.session?.viewerLatitude;
    final lon = widget.session?.viewerLongitude;
    final km = (lat == null || lon == null || b.latitude == null || b.longitude == null)
        ? null
        : distanceKm(lat1: lat, lon1: lon, lat2: b.latitude!, lon2: b.longitude!).round();
    final distance = km?.toString();

    return RadarPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (standby
                                    ? RadarTheme.info
                                    : RadarTheme.textFaint)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag,
                            style: RadarType.capsTight.copyWith(
                              fontSize: 7.5,
                              color: standby
                                  ? RadarTheme.cyanDeep
                                  : RadarTheme.textDim,
                            ),
                          ),
                        ),
                        if (kickoff.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              kickoff,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RadarType.capsTight.copyWith(
                                fontSize: 8,
                                color: RadarTheme.textDim,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      b.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        18,
                        weight: FontWeight.w600,
                        color: RadarTheme.textPrimary,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${b.posterName} • ${b.areaName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 10.5,
                        color: RadarTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _EscrowBadge(amount: b.amountPi, label: 'Escrow'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.navigation_outlined,
                  size: 13, color: RadarTheme.cyanDeep),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  distance == null ? b.areaName : '$distance km away',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.capsTight.copyWith(
                    fontSize: 8.5,
                    color: RadarTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.cell_tower, size: 13, color: RadarTheme.radar),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  standby ? 'Secondary Angle' : 'Awaiting Pi escrow',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.capsTight.copyWith(
                    fontSize: 8.5,
                    color: standby ? RadarTheme.radar : RadarTheme.textDim,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _open(context, b),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHighest,
                    borderRadius: BorderRadius.circular(RadarRadius.base),
                  ),
                  child: Text(
                    standby ? 'CLAIM STANDBY' : 'VIEW BOUNTY',
                    style: RadarType.capsTight.copyWith(
                      fontSize: 8.5,
                      color: standby
                          ? RadarTheme.cyanDeep
                          : RadarTheme.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, StreamBounty b) async {
    if (b.status == 'funded') {
      await ref.read(streamBountiesProvider.notifier).acceptBounty(b.id);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BountyFulfillmentFlow(bounty: b),
    ));
  }
}

class _HowOperatorBountiesWork extends StatelessWidget {
  const _HowOperatorBountiesWork();

  @override
  Widget build(BuildContext context) {
    final steps = <(String, String, String, Color)>[
      ('1', 'GPS Check-In', 'Geofenced pitch lock', RadarTheme.radar),
      ('2', 'Record', 'Uncut high-FPS tape', RadarTheme.cyanDeep),
      ('3', 'Upload', 'Direct Pi sync', RadarTheme.info),
      ('4', 'Request Payment', 'Escrow released', RadarTheme.goldBright),
    ];
    return RadarPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 19, color: RadarTheme.goldBright),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'HOW OPERATOR BOUNTIES WORK',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RadarType.heading(
                    17,
                    weight: FontWeight.w600,
                    color: const Color(0xFFF0FFEE),
                    tracking: 0.6,
                  ),
                ),
              ),
              RadarCaps('ZERO FRICTION',
                  size: 8, color: RadarTheme.radar),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (n, title, sub, color) in steps)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: RadarTheme.panelHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Text(n,
                            style: RadarType.caps.copyWith(
                                fontSize: 10, color: color)),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.capsTight.copyWith(
                          fontSize: 8.5,
                          color: n == '4'
                              ? RadarTheme.goldBright
                              : RadarTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.bodySm.copyWith(
                          fontSize: 9,
                          height: 1.25,
                          color: RadarTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EscrowBanner extends StatelessWidget {
  const _EscrowBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RadarRadius.card),
        border: Border.all(color: RadarTheme.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock, size: 15, color: RadarTheme.goldBright),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: RadarType.bodySm.copyWith(
                fontSize: 11,
                color: RadarTheme.goldBright,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBounties extends StatelessWidget {
  const _EmptyBounties({required this.onPost});

  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return RadarPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.videocam_off_outlined, size: 34, color: RadarTheme.textFaint),
          const SizedBox(height: 8),
          Text('No open escrows right now',
              style: RadarType.bodyMd.copyWith(color: RadarTheme.textDim)),
          const SizedBox(height: 8),
          TextButton(onPressed: onPost, child: const Text('Post a Pi bounty')),
        ],
      ),
    );
  }
}

String _short(Duration d) {
  if (d.inDays > 0) return '${d.inDays}D ${d.inHours.remainder(24)}H';
  if (d.inHours > 0) return '${d.inHours}H ${d.inMinutes.remainder(60)}M';
  return '${d.inMinutes} MINS';
}

// ---------------------------------------------------------------------------
// Post bounty sheet (exported for the Discover / Map CTAs)
// ---------------------------------------------------------------------------

/// Opens the Pi escrow composer, optionally pre-filled from a reel or a pitch.
Future<void> showPostBountySheet(
  BuildContext context, {
  String? title,
  double? amountPi,
  String? areaName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostBountySheet(
      initialTitle: title,
      initialAmount: amountPi,
      initialArea: areaName,
    ),
  );
}

class _PostBountySheet extends ConsumerStatefulWidget {
  const _PostBountySheet({
    this.initialTitle,
    this.initialAmount,
    this.initialArea,
  });

  final String? initialTitle;
  final double? initialAmount;
  final String? initialArea;

  @override
  ConsumerState<_PostBountySheet> createState() => _PostBountySheetState();
}

class _PostBountySheetState extends ConsumerState<_PostBountySheet> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.initialTitle ?? '');
  final _briefCtrl = TextEditingController();
  late final TextEditingController _areaCtrl =
      TextEditingController(text: widget.initialArea ?? '');
  final _venueCtrl = TextEditingController();
  late double _amount = (widget.initialAmount ?? 50).clamp(5, 500).toDouble();
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
      ref
          .read(streamBountiesProvider.notifier)
          .fundBounty(bountyId, _amount, _titleCtrl.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHighest,
        content: Text(
          'Bounty posted — confirm the ${_amount.toStringAsFixed(0)} π escrow in your Pi wallet',
          style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Post a stream bounty',
      icon: Icons.workspace_premium,
      iconColor: RadarTheme.goldBright,
      showClose: false,
      subtitle: 'Pi is escrowed from your wallet now and released to the '
          'streamer when you confirm the broadcast.',
      footer: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: RadarTheme.gold,
          foregroundColor: const Color(0xFF442B00),
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
      children: [
        TextField(
          controller: _titleCtrl,
          style: TextStyle(color: RadarTheme.textPrimary),
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
          style: TextStyle(color: RadarTheme.textPrimary),
          decoration: const InputDecoration(
            hintText:
                'Camera angle, player to track, upload stability, kickoff time…',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _areaCtrl,
          style: TextStyle(color: RadarTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Area, e.g. “Limbe — Omnisport Annex”',
            prefixIcon: Icon(Icons.place_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _venueCtrl,
          style: TextStyle(color: RadarTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Venue (optional)',
            prefixIcon: Icon(Icons.stadium_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Text('Escrow',
              style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
          const Spacer(),
          Text('${_amount.toStringAsFixed(0)} π',
              style: TextStyle(
                  color: RadarTheme.goldBright,
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
        Text('Stream length (minutes)',
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
              setState(() => _kickoff = DateTime(
                  date.year, date.month, date.day, time.hour, time.minute));
            }
          },
          icon: const Icon(Icons.event, size: 18),
          label: Text(DateFormat('EEE d MMM · HH:mm').format(_kickoff)),
        ),
      ],
    );
  }
}

/// Analytics entry point kept for the completed-gig receipt.
void openBountyAnalytics(BuildContext context, StreamBounty b) {
  final session = TrackingSession.synthetic(
    id: 'track-${b.id}',
    bountyId: b.id,
    playerLabel: 'Target player — CV jersey lock',
    durationMin: b.durationMinutes.clamp(15, 90),
    seed: b.id.hashCode & 0x7fffffff,
  );
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MatchAnalyticsScreen(bounty: b, session: session),
  ));
}

// Keeps `distanceKm` part of the public surface of this screen for callers
// that compute proximity from a post (unused internally, exported for tests).
double? bountyDistanceKm({
  required double lat,
  required double lon,
  required StreamBounty bounty,
}) {
  if (bounty.latitude == null || bounty.longitude == null) return null;
  return distanceKm(
    lat1: lat,
    lon1: lon,
    lat2: bounty.latitude!,
    lon2: bounty.longitude!,
  );
}
