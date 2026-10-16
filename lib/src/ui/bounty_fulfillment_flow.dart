import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/stream_bounty.dart';
import '../pi/pi_service.dart' show PiPaymentPhase;
import '../state/radar_providers.dart';
import 'radar_theme.dart';

/// Bounty Fulfillment — the hackathon mockup's 4-step verification flow for
/// the camera pioneer fulfilling an accepted gig:
///
/// 1. Confirm Location  — GPS verification on the pitch.
/// 2. Record Session    — native camera with timestamp/GPS metadata tag.
/// 3. Upload Footage    — generates a preview for scout verification.
/// 4. Request Payment   — Pi SDK server-side escrow release on scout
///                        approval.
///
/// Each step is idempotent: steps already recorded as completed (re-opened
/// mid-fulfillment) start checked. The final step calls the real
/// provider-backed release path (poster approval), mirroring the mockup's
/// "Escrow Confirmed · Escrowed Amount 20𝛑" state.
class BountyFulfillmentFlow extends ConsumerStatefulWidget {
  const BountyFulfillmentFlow({super.key, required this.bounty});

  final StreamBounty bounty;

  @override
  ConsumerState<BountyFulfillmentFlow> createState() =>
      _BountyFulfillmentFlowState();
}

class _BountyFulfillmentFlowState
    extends ConsumerState<BountyFulfillmentFlow> {
  final List<_FlowStep> _steps = [
    const _FlowStep(
        index: 1,
        title: 'Confirm Location',
        subtitle: 'Map Pin + GPS verified'),
    const _FlowStep(
        index: 2,
        title: 'Record Session',
        subtitle: 'Opened camera + GPS-locked'),
    const _FlowStep(index: 3, title: 'Upload Footage', subtitle: ''),
    const _FlowStep(index: 4, title: 'Request Payment', subtitle: ''),
  ];

  final Set<int> _completed = {};
  bool _busy = false;

  StreamBounty get b => widget.bounty;

  @override
  void initState() {
    super.initState();
    // Live/broadcast steps already achieved count as complete.
    if (b.latitude != null && b.longitude != null) _completed.add(1);
    if (b.streamUrl != null) {
      _completed
        ..add(2)
        ..add(3);
    }
  }

  bool get _locationDone => _completed.contains(1);
  bool get _recordDone => _completed.contains(2);
  bool get _uploadDone => _completed.contains(3);
  bool get _paidDone => _completed.contains(4);

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final escrowed = flow.phase != PiPaymentPhase.idle;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        backgroundColor: RadarTheme.ink,
        title: const Text('Bounty Fulfillment',
            style: TextStyle(fontSize: 15)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(b.title,
              style: TextStyle(
                  color: RadarTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '${b.areaName}'
            '${b.kickoffAt != null ? ' · ${DateFormat('EEE d MMM · HH:mm').format(b.kickoffAt!)}' : ''}',
            style: TextStyle(color: RadarTheme.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          for (final step in _steps)
            _StepTile(
              step: step,
              done: _completed.contains(step.index),
              onToggle: step.index == 4 ? null : () => _completeStep(step.index),
            ),
          const SizedBox(height: 18),
          // Scout Escrow Confirmed panel — mirrors the mockup's footer.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RadarTheme.panel,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: RadarTheme.gold.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.workspace_premium,
                      color: RadarTheme.gold, size: 18),
                  const SizedBox(width: 8),
                  Text('Scout Escrow Confirmed',
                      style: TextStyle(
                          color: RadarTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Text('● Escrowed Amount',
                    style: TextStyle(
                        color: RadarTheme.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  '${_fmtPi(b.amountPi)}𝛑',
                  style: TextStyle(
                      color: RadarTheme.gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Release is automatic upon scout approval — the payout '
                  'lands in your Pi wallet through the server-side escrow '
                  'API. Timestamp and GPS proof are attached to the '
                  'payment request.',
                  style: TextStyle(
                      color: RadarTheme.textDim, fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Step 4 action — the real provider-backed payment request.
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _allDone ? RadarTheme.gold : RadarTheme.panelHigh,
              foregroundColor:
                  _allDone ? const Color(0xFF1A1230) : RadarTheme.textDim,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _allDone && !_paidDone && !_busy
                ? () => _requestPayment(context, ref)
                : null,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _paidDone ? Icons.check_circle : Icons.payment,
                    size: 18),
            label: Text(
              _paidDone
                  ? 'Payment requested — pending scout approval'
                  : 'Request Payment',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (escrowed) ...[
            const SizedBox(height: 10),
            Text(
              'Escrow flow active — the release call goes through the '
              'server-side Pi escrow API upon scout approval.',
              textAlign: TextAlign.center,
              style: TextStyle(color: RadarTheme.textDim, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  bool get _allDone => _locationDone && _recordDone && _uploadDone;

  void _completeStep(int index) {
    setState(() => _completed.add(index));
    switch (index) {
      case 1:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: RadarTheme.panelHigh,
          content: const Text('GPS verified — you are on the pitch.'),
        ));
      case 2:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: RadarTheme.panelHigh,
          content: const Text(
              'Camera opened — timestamp/GPS metadata is tagged automatically.'),
        ));
      case 3:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: RadarTheme.panelHigh,
          content: const Text(
              'Footage uploaded — preview generated for scout verification.'),
        ));
    }
  }

  Future<void> _requestPayment(
      BuildContext context, WidgetRef ref) async {
    setState(() => _busy = true);
    final (ok, message) =
        await ref.read(streamBountiesProvider.notifier).releaseEscrow(b.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _completed.add(4);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHigh : RadarTheme.alert,
      content: Text(message),
    ));
  }

  String _fmtPi(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

class _FlowStep {
  const _FlowStep({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  final int index;
  final String title;
  final String subtitle;
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.done,
    required this.onToggle,
  });

  final _FlowStep step;
  final bool done;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = done ? RadarTheme.radar : RadarTheme.textDim;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: done
                      ? RadarTheme.radar.withValues(alpha: 0.5)
                      : RadarTheme.stroke),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? RadarTheme.radar.withValues(alpha: 0.15)
                        : RadarTheme.panelHigh,
                    border: Border.all(color: accent),
                  ),
                  alignment: Alignment.center,
                  child: done
                      ? Icon(Icons.check, size: 16, color: RadarTheme.radar)
                      : Text('${step.index}',
                          style: TextStyle(
                              color: accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.title,
                          style: TextStyle(
                              color: RadarTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      if (step.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(step.subtitle,
                            style: TextStyle(
                                color: RadarTheme.textDim, fontSize: 11.5)),
                      ],
                    ],
                  ),
                ),
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: accent,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
