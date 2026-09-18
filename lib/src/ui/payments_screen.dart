import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pi_payment.dart';
import '../pi/pi_service.dart';
import '../state/radar_providers.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Pi Wallet checkout: premium scouting searches, session boosts and bounty
/// rewards — all via `Pi.createPayment` with backend webhooks.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(paymentFlowProvider);
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final wide = size != WindowSize.compact;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.account_balance_wallet, size: 20),
            const SizedBox(width: 10),
            const Text('Pi Wallet'),
          ],
        ),
        actions: [
          if (flow.phase != PiPaymentPhase.idle)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: InfoPill(
                  icon: _phaseIcon(flow.phase),
                  label: _phaseLabel(flow.phase),
                  color: _phaseColor(flow.phase),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (flow.message != null) _FlowBanner(flow: flow),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Premium tools, paid in Pi',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Payments are processed by the Pi Network wallet. The Radar '
                    'never sees your passphrase — you approve every transaction.',
                    style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: wide ? 3 : 1,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: wide ? 1.05 : 2.4,
                    ),
                    children: [
                      _ProductCard(
                        icon: Icons.manage_search,
                        accent: RadarTheme.pi,
                        title: 'Premium Scouting Search',
                        description:
                            '30 days of unlimited advanced searches: filter by '
                            'position, age band, region and credibility. '
                            'Saved searches & instant alerts included.',
                        price: 5.0,
                        product: 'premium_search_30d',
                        cta: 'Unlock with Pi',
                      ),
                      _ProductCard(
                        icon: Icons.bolt,
                        accent: RadarTheme.gold,
                        title: 'Session Boost',
                        description:
                            'Pin your training session, match, trial or '
                            'tournament to the top of the Radar for 48 hours '
                            'and notify matching scouts in your region.',
                        price: 2.0,
                        product: 'session_boost_48h',
                        cta: 'Boost session',
                      ),
                      _ProductCard(
                        icon: Icons.emoji_events_outlined,
                        accent: RadarTheme.radar,
                        title: 'Scouting Bounty',
                        description:
                            'Post a bounty on an event. Verified scouts who '
                        'attend and file a structured report earn the bounty '
                            'automatically via app-to-user payout.',
                        price: 10.0,
                        product: 'scouting_bounty',
                        cta: 'Post bounty',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _StatusTimeline(),
                  if (flow.history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const SectionHeader('This session'),
                    for (final p in flow.history) _HistoryTile(payment: p),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _phaseColor(PiPaymentPhase phase) => switch (phase) {
        PiPaymentPhase.completed => RadarTheme.radar,
        PiPaymentPhase.error => RadarTheme.alert,
        PiPaymentPhase.cancelled => RadarTheme.gold,
        _ => RadarTheme.info,
      };

  IconData _phaseIcon(PiPaymentPhase phase) => switch (phase) {
        PiPaymentPhase.completed => Icons.check_circle_outline,
        PiPaymentPhase.error => Icons.error_outline,
        PiPaymentPhase.cancelled => Icons.cancel_outlined,
        PiPaymentPhase.awaitingUser => Icons.hourglass_top,
        _ => Icons.sync,
      };

  String _phaseLabel(PiPaymentPhase phase) => switch (phase) {
        PiPaymentPhase.idle => '',
        PiPaymentPhase.awaitingUser => 'Awaiting approval',
        PiPaymentPhase.readyForApproval => 'Verifying',
        PiPaymentPhase.readyForCompletion => 'Verifying',
        PiPaymentPhase.completing => 'Finalising',
        PiPaymentPhase.completed => 'Paid',
        PiPaymentPhase.cancelled => 'Cancelled',
        PiPaymentPhase.error => 'Error',
      };
}

class _FlowBanner extends ConsumerWidget {
  const _FlowBanner({required this.flow});

  final PaymentFlowState flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isError = flow.phase == PiPaymentPhase.error;
    final cancelled = flow.phase == PiPaymentPhase.cancelled;
    final color = isError
        ? RadarTheme.alert
        : cancelled
            ? RadarTheme.gold
            : RadarTheme.radar;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : cancelled
                    ? Icons.info_outline
                    : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              flow.message ?? '',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          IconButton(
            onPressed: () => ref.read(paymentFlowProvider.notifier).dismiss(),
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.price,
    required this.product,
    required this.cta,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final double price;
  final String product;
  final String cta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(paymentFlowProvider);
    final busy = flow.phase == PiPaymentPhase.awaitingUser ||
        flow.phase == PiPaymentPhase.readyForApproval ||
        flow.phase == PiPaymentPhase.readyForCompletion ||
        flow.phase == PiPaymentPhase.completing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} π',
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: RadarTheme.textDim),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent.withValues(alpha: 0.9),
                  foregroundColor: RadarTheme.ink,
                ),
                onPressed: busy
                    ? null
                    : () => ref.read(paymentFlowProvider.notifier).pay(
                          amount: price,
                          memo: 'The Radar — $title',
                          product: product,
                          metadata: {'sku': product, 'price_pi': price},
                        ),
                icon: const Icon(Icons.currency_exchange, size: 16),
                label: Text(cta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How a Pi payment flows',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          const _Step(
              n: '1',
              text:
                  'The Radar calls Pi.createPayment() — your Pi wallet opens '
                  'for approval.'),
          const _Step(
              n: '2',
              text:
                  'onReadyForServerApproval → our Supabase edge function '
                  'approves the payment server-side.'),
          const _Step(
              n: '3',
              text:
                  'You submit the transaction on the Pi blockchain; the SDK '
                  'fires onReadyForServerCompletion with the txid.'),
          const _Step(
              n: '4',
              text:
                  'Our completion webhook verifies the txid with the Pi '
                  'Platform API and unlocks your purchase.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RadarTheme.pi.withValues(alpha: 0.16),
            ),
            child: Text(n,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: RadarTheme.pi)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.45, color: RadarTheme.textDim)),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.payment});

  final PiPayment payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: RadarTheme.radar, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.memo,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  payment.txid == null
                      ? 'txid pending'
                      : 'txid ${payment.txid!.substring(0, min(payment.txid!.length, 10))}…',
                  style: const TextStyle(
                      fontSize: 11, color: RadarTheme.textDim),
                ),
              ],
            ),
          ),
          Text('${payment.amount.toStringAsFixed(2)} π',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: RadarTheme.gold)),
        ],
      ),
    );
  }
}
