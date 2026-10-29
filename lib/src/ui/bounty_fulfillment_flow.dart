import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../data/location_service.dart';
import '../models/stream_bounty.dart';
import '../pi/pi_service.dart' show PiPaymentPhase;
import '../state/radar_providers.dart';
import 'design/radar_design.dart';
import 'radar_theme.dart';

/// Bounty Fulfillment — the four-step escrow workflow, exactly as the bounty
/// cards and the design spec define it:
///
/// 1. **GPS Check-In**   — geofenced confirmation on the pitch.
/// 2. **Record**         — camera HUD, timestamp/GPS metadata tagged.
/// 3. **Upload**         — footage synced, preview generated for the scout.
/// 4. **Request Payment**— escrow release request; the scout approves from the
///                         Review tab and Pi lands in the operator wallet.
///
/// Steps are strictly sequential: each gate unlocks only once the previous
/// one is recorded, and re-opening a part-finished gig restores its progress.
class BountyFulfillmentFlow extends ConsumerStatefulWidget {
  const BountyFulfillmentFlow({super.key, required this.bounty});

  final StreamBounty bounty;

  @override
  ConsumerState<BountyFulfillmentFlow> createState() =>
      _BountyFulfillmentFlowState();
}

class _BountyFulfillmentFlowState extends ConsumerState<BountyFulfillmentFlow> {
  static const _titles = [
    'GPS Check-In',
    'Record',
    'Upload',
    'Request Payment',
  ];
  static const _subtitles = [
    'Geofenced pitch lock',
    'Uncut high-FPS tape',
    'Direct Pi sync',
    'Escrow released',
  ];
  static const _icons = [
    Icons.my_location,
    Icons.videocam_outlined,
    Icons.cloud_upload_outlined,
    Icons.account_balance_wallet_outlined,
  ];

  /// Maximum distance from the pinned pitch that still counts as on the pitch.
  static const _geofenceMeters = 150.0;

  final Set<int> _done = {};
  int _active = 1;
  bool _locating = false;
  bool _busy = false;
  bool _uploading = false;
  double _uploadProgress = 0;
  Timer? _ticker;
  int _seconds = 0;

  StreamBounty get b => widget.bounty;

  @override
  void initState() {
    super.initState();
    if (b.streamUrl != null) {
      _done
        ..add(1)
        ..add(2)
        ..add(3);
    }
    _active = _done.isEmpty ? 1 : (_done.reduce((a, b) => a > b ? a : b) + 1);
    if (_active > 4) _active = 4;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _allDone => _done.containsAll(const [1, 2, 3]);

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider);
    final escrowed = flow.phase != PiPaymentPhase.idle;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: Column(
        children: [
          _HudHeader(bounty: b, onBack: () => Navigator.of(context).maybePop()),
          _StepRail(
            titles: _titles,
            subtitles: _subtitles,
            icons: _icons,
            done: _done,
            active: _active,
            onTap: (i) {
              if (i == 1 || _done.contains(i - 1)) {
                setState(() => _active = i);
              }
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: switch (_active) {
                    1 => _GpsStep(
                        key: const ValueKey('gps'),
                        bounty: b,
                        done: _done.contains(1),
                        locating: _locating,
                        onConfirm: _confirmGps,
                      ),
                    2 => _RecordStep(
                        key: const ValueKey('record'),
                        bounty: b,
                        done: _done.contains(2),
                        seconds: _seconds,
                        recording: _ticker != null,
                        onToggle: _toggleRecording,
                        onFinish: _finishRecording,
                      ),
                    3 => _UploadStep(
                        key: const ValueKey('upload'),
                        bounty: b,
                        done: _done.contains(3),
                        uploading: _uploading,
                        progress: _uploadProgress,
                        onUpload: _upload,
                      ),
                    _ => _PaymentStep(
                        key: const ValueKey('pay'),
                        bounty: b,
                        escrowed: escrowed,
                        paid: _done.contains(4),
                        ready: _allDone,
                        busy: _busy,
                        onRequest: _requestPayment,
                        onReview: () => Navigator.of(context).maybePop(),
                      ),
                  },
                ),
                const SizedBox(height: 16),
                _EscrowFooter(bounty: b),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- step actions

  Future<void> _confirmGps() async {
    final venueLat = b.venueLatitude;
    final venueLon = b.venueLongitude;
    if (venueLat == null || venueLon == null) {
      _toast('The poster has not pinned the pitch yet — GPS check-in is unavailable.');
      return;
    }
    setState(() => _locating = true);
    try {
      final here = await LocationService.instance.getCurrent();
      final meters = Geolocator.distanceBetween(
        here.lat,
        here.lon,
        venueLat,
        venueLon,
      );
      if (!mounted) return;
      if (meters > _geofenceMeters) {
        _toast(
            'You are ${meters.round()} m from the pitch — move within ${_geofenceMeters.round()} m to check in.');
        return;
      }
      setState(() {
        _done.add(1);
        _active = 2;
      });
      _toast('GPS verified — you are on ${b.venueName ?? b.areaName}');
    } on LocationException catch (e) {
      if (mounted) _toast(e.reason);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toggleRecording() {
    if (_done.contains(2)) return;
    setState(() {
      if (_ticker == null) {
        _seconds = 0;
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _seconds++);
        });
      } else {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  void _finishRecording() {
    if (_seconds < 5) {
      _toast('Record at least a few seconds before finishing.');
      return;
    }
    _ticker?.cancel();
    setState(() {
      _ticker = null;
      _done.add(2);
      _active = 3;
    });
    _toast('Tape locked — ${_clock(_seconds)} of uncut footage');
  }

  Future<void> _upload() async {
    if (_uploading || _done.contains(3)) return;
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _uploadProgress = i / 10);
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _done.add(3);
      _active = 4;
    });
    _toast('Upload complete — preview sent to the scout for review');
  }

  Future<void> _requestPayment() async {
    if (!_allDone || _busy || _done.contains(4)) return;
    setState(() => _busy = true);
    final (ok, message) =
        await ref.read(streamBountiesProvider.notifier).releaseEscrow(b.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _done.add(4);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHighest : RadarTheme.alert,
      content: Text(message,
          style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary)),
    ));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHighest,
      content: Text(message,
          style: RadarType.bodySm.copyWith(color: RadarTheme.textPrimary)),
    ));
  }
}

String _clock(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

class _HudHeader extends StatelessWidget {
  const _HudHeader({required this.bounty, required this.onBack});

  final StreamBounty bounty;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RadarTheme.panelLowest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back,
                    size: 21, color: RadarTheme.textDim),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadarCaps('Escrow fulfilment',
                        size: 9, color: RadarTheme.radar, tracking: 1.0),
                    Text(
                      bounty.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.heading(
                        17,
                        weight: FontWeight.w600,
                        color: RadarTheme.textPrimary,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: RadarTheme.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: RadarTheme.gold.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Text(
                      '${fmtPi(bounty.amountPi)} π',
                      style: RadarType.metricMd.copyWith(
                        fontSize: 12,
                        height: 1,
                        color: RadarTheme.goldBright,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.lock_outline,
                        size: 12, color: RadarTheme.goldBright),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.titles,
    required this.subtitles,
    required this.icons,
    required this.done,
    required this.active,
    required this.onTap,
  });

  final List<String> titles;
  final List<String> subtitles;
  final List<IconData> icons;
  final Set<int> done;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RadarTheme.panelLowest,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          for (var i = 0; i < titles.length; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i + 1),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == 0
                                ? Colors.transparent
                                : (done.contains(i) || active > i
                                    ? RadarTheme.radar
                                    : RadarTheme.stroke),
                          ),
                        ),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done.contains(i + 1)
                                ? RadarTheme.radar
                                : (active == i + 1
                                    ? RadarTheme.panelHighest
                                    : RadarTheme.panelLowest),
                            border: Border.all(
                              color: done.contains(i + 1)
                                  ? RadarTheme.radar
                                  : (active == i + 1
                                      ? RadarTheme.radar
                                      : RadarTheme.stroke),
                            ),
                          ),
                          child: done.contains(i + 1)
                              ? Icon(Icons.check,
                                  size: 14, color: RadarTheme.onAccent)
                              : Icon(
                                  icons[i],
                                  size: 13,
                                  color: active == i + 1
                                      ? RadarTheme.radar
                                      : RadarTheme.textFaint,
                                ),
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == titles.length - 1
                                ? Colors.transparent
                                : (done.contains(i + 1)
                                    ? RadarTheme.radar
                                    : RadarTheme.stroke),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      titles[i].toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.capsTight.copyWith(
                        fontSize: 7.5,
                        color: active == i + 1 || done.contains(i + 1)
                            ? RadarTheme.textPrimary
                            : RadarTheme.textFaint,
                      ),
                    ),
                    Text(
                      subtitles[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                        fontSize: 8,
                        color: RadarTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i != titles.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

class _GpsStep extends StatelessWidget {
  const _GpsStep({
    super.key,
    required this.bounty,
    required this.done,
    required this.locating,
    required this.onConfirm,
  });

  final StreamBounty bounty;
  final bool done;
  final bool locating;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      index: 1,
      title: 'Confirm location',
      caption: 'GPS Check-In · geofenced to the pitch',
      done: done,
      child: Column(
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: RadarTheme.panelLowest,
              borderRadius: BorderRadius.circular(RadarRadius.card),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: TacticalGridPainter(spacing: 22, dot: true)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LiveDot(size: 10, animate: false),
                      const SizedBox(height: 8),
                      Text(
                        bounty.venueName ?? bounty.areaName,
                        textAlign: TextAlign.center,
                        style: RadarType.heading(
                          19,
                          weight: FontWeight.w600,
                          color: RadarTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      RadarCaps(
                        bounty.venueLatitude == null || bounty.venueLongitude == null
                            ? 'Pitch not pinned'
                            : '${bounty.venueLatitude!.abs().toStringAsFixed(4)}° ${bounty.venueLatitude! >= 0 ? 'N' : 'S'} • ${bounty.venueLongitude!.abs().toStringAsFixed(4)}° ${bounty.venueLongitude! >= 0 ? 'E' : 'W'}',
                        size: 8,
                        color: RadarTheme.cyanDeep,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: RadarTheme.panelHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: RadarCaps('GEOFENCE 150 M',
                        size: 7, color: RadarTheme.radar),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FactRow(
            icon: Icons.schedule,
            label: 'Kick-off',
            value: bounty.kickoffAt == null
                ? 'Not scheduled'
                : DateFormat('EEE d MMM • HH:mm').format(bounty.kickoffAt!),
          ),
          _FactRow(
            icon: Icons.videocam_outlined,
            label: 'Requested tape',
            value: '${bounty.durationMinutes} min uncut',
          ),
          const SizedBox(height: 10),
          RadarPrimaryButton(
            label: done
                ? 'GPS verified'
                : locating
                    ? 'Locating…'
                    : 'Check in on the pitch',
            icon: done ? Icons.check_circle : Icons.my_location,
            onPressed: (done || locating) ? null : onConfirm,
          ),
        ],
      ),
    );
  }
}

class _RecordStep extends StatelessWidget {
  const _RecordStep({
    super.key,
    required this.bounty,
    required this.done,
    required this.seconds,
    required this.recording,
    required this.onToggle,
    required this.onFinish,
  });

  final StreamBounty bounty;
  final bool done;
  final int seconds;
  final bool recording;
  final VoidCallback onToggle;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      index: 2,
      title: 'Record the session',
      caption: 'Camera HUD · timestamp + GPS tagged automatically',
      done: done,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RadarRadius.sheet),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: RadarTheme.panelLowest,
                    child: CustomPaint(
                      painter: TacticalGridPainter(spacing: 26),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.3),
                        radius: 1.1,
                        colors: [
                          RadarTheme.radar.withValues(alpha: 0.14),
                          RadarTheme.panelLowest,
                        ],
                      ),
                    ),
                  ),
                  // Tracking reticle.
                  Align(
                    alignment: const Alignment(-0.15, -0.1),
                    child: Container(
                      width: 92,
                      height: 118,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: RadarTheme.radar.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -9,
                            left: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              color: RadarTheme.panelLowest.withValues(alpha: 0.9),
                              child: Row(
                                children: [
                                  LiveDot(size: 4, animate: false),
                                  const SizedBox(width: 3),
                                  RadarCaps('PROSPECT LOCK 98%',
                                      size: 6, color: RadarTheme.radar),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: RadarTheme.panelLowest.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: recording
                                      ? RadarTheme.alert
                                      : RadarTheme.textFaint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                recording
                                    ? 'REC ${_clock(seconds)}'
                                    : 'STANDBY',
                                style: RadarType.capsTight.copyWith(
                                  fontSize: 7.5,
                                  color: RadarTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: RadarTheme.panelHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: RadarCaps('4K60 RAW',
                              size: 6.5, color: RadarTheme.cyanDeep),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: done ? null : onToggle,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: recording
                              ? RadarTheme.alert
                              : RadarTheme.panelHighest.withValues(alpha: 0.8),
                          border: Border.all(
                            color: recording
                                ? RadarTheme.alert
                                : RadarTheme.radar,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          recording ? Icons.stop : Icons.videocam,
                          color: recording
                              ? Colors.white
                              : RadarTheme.radar,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 7,
                    child: Row(
                      children: [
                        Icon(Icons.mic_none,
                            size: 13, color: RadarTheme.radar),
                        const SizedBox(width: 3),
                        RadarCaps('-6dB', size: 7, color: RadarTheme.radar),
                        const Spacer(),
                        RadarCaps('GIMBAL LOCK', size: 7, color: RadarTheme.radar),
                        const Spacer(),
                        RadarCaps('54% BATTERY',
                            size: 7, color: RadarTheme.textDim),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: RadarGhostButton(
                  label: recording ? 'Pause' : 'Start recording',
                  icon: recording ? Icons.pause : Icons.play_arrow,
                  height: 42,
                  tone: RadarGhostTone.cyan,
                  onPressed: done ? null : onToggle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RadarPrimaryButton(
                  label: done ? 'Tape locked' : 'Finish recording',
                  icon: done ? Icons.check : Icons.stop_circle_outlined,
                  height: 42,
                  compactLabel: true,
                  onPressed: done ? null : onFinish,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UploadStep extends StatelessWidget {
  const _UploadStep({
    super.key,
    required this.bounty,
    required this.done,
    required this.uploading,
    required this.progress,
    required this.onUpload,
  });

  final StreamBounty bounty;
  final bool done;
  final bool uploading;
  final double progress;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      index: 3,
      title: 'Upload footage',
      caption: 'Uncut tape → Pi storage → scout preview',
      done: done,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RadarTheme.panelLowest,
              borderRadius: BorderRadius.circular(RadarRadius.card),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: RadarTheme.panelHigh,
                    borderRadius: BorderRadius.circular(RadarRadius.card),
                  ),
                  child: Icon(Icons.movie_outlined,
                      size: 20, color: RadarTheme.cyanDeep),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${bounty.durationMinutes}-min uncut tape',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RadarType.bodySm.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: RadarTheme.textPrimary,
                        ),
                      ),
                      RadarCaps(
                        '${(bounty.durationMinutes * 1.7).toStringAsFixed(1)} GB • 4K60 • GPS EMBEDDED',
                        size: 7,
                        color: RadarTheme.textDim,
                      ),
                    ],
                  ),
                ),
                Icon(
                  done ? Icons.check_circle : Icons.cloud_upload_outlined,
                  size: 19,
                  color: done ? RadarTheme.radar : RadarTheme.textFaint,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: done ? 1 : progress,
              minHeight: 6,
              backgroundColor: RadarTheme.panelHigh,
              valueColor: AlwaysStoppedAnimation(RadarTheme.radar),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              RadarCaps(
                done
                    ? 'SYNCED • PREVIEW READY'
                    : (uploading
                        ? 'UPLOADING ${(progress * 100).round()}%'
                        : 'READY TO SYNC'),
                size: 7.5,
                color: done ? RadarTheme.radar : RadarTheme.textDim,
              ),
              const Spacer(),
              RadarCaps('PI STORAGE', size: 7.5),
            ],
          ),
          const SizedBox(height: 10),
          RadarPrimaryButton(
            label: done
                ? 'Footage delivered'
                : (uploading ? 'Uploading…' : 'Upload to Pi storage'),
            icon: done
                ? Icons.check_circle
                : (uploading ? Icons.sync : Icons.cloud_upload_outlined),
            onPressed: done || uploading ? null : onUpload,
          ),
        ],
      ),
    );
  }
}

class _PaymentStep extends StatelessWidget {
  const _PaymentStep({
    super.key,
    required this.bounty,
    required this.escrowed,
    required this.paid,
    required this.ready,
    required this.busy,
    required this.onRequest,
    required this.onReview,
  });

  final StreamBounty bounty;
  final bool escrowed;
  final bool paid;
  final bool ready;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      index: 4,
      title: 'Request payment',
      caption: 'Scout approves in the Review tab • Pi escrow releases',
      done: paid,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RadarTheme.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(RadarRadius.card),
              border:
                  Border.all(color: RadarTheme.gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.workspace_premium,
                        size: 17, color: RadarTheme.goldBright),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Scout escrow confirmed',
                          style: RadarType.bodySm.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: RadarTheme.textPrimary,
                          )),
                    ),
                    RadarCaps(escrowed ? 'FUNDED' : 'PENDING',
                        size: 7.5,
                        color: escrowed
                            ? RadarTheme.radar
                            : RadarTheme.textDim),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      fmtPi(bounty.amountPi),
                      style: RadarType.metricLg.copyWith(
                        fontSize: 30,
                        color: RadarTheme.goldBright,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('π',
                        style: RadarType.heading(18,
                            weight: FontWeight.w700,
                            color: RadarTheme.goldBright)),
                    const SizedBox(width: 8),
                    Text('ESCROWED AMOUNT',
                        style: RadarType.capsTight.copyWith(
                            fontSize: 7, color: RadarTheme.textDim)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Release is authorised by the scout from the Review tab and '
                  'lands in your Pi wallet. GPS timestamp and the uploaded '
                  'tape are attached to the request.',
                  style: RadarType.bodySm.copyWith(
                    fontSize: 10,
                    height: 1.4,
                    color: RadarTheme.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          RadarPrimaryButton(
            label: paid
                ? 'Payment requested'
                : (ready ? 'Request payment' : 'Finish the first three steps'),
            icon: paid ? Icons.check_circle : Icons.payment,
            onPressed: ready && !paid && !busy ? onRequest : null,
          ),
          const SizedBox(height: 7),
          RadarGhostButton(
            label: 'Open the review room',
            icon: Icons.verified_outlined,
            height: 40,
            onPressed: onReview,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.caption,
    required this.done,
    required this.child,
  });

  final int index;
  final String title;
  final String caption;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RadarPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done
                      ? RadarTheme.radar
                      : RadarTheme.panelHighest,
                  shape: BoxShape.circle,
                ),
                child: done
                    ? Icon(Icons.check, size: 14, color: RadarTheme.onAccent)
                    : Text('$index',
                        style: RadarType.caps
                            .copyWith(fontSize: 10, color: RadarTheme.radar)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: RadarType.heading(
                        18,
                        weight: FontWeight.w600,
                        color: RadarTheme.textPrimary,
                        tracking: 0.5,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RadarType.bodySm.copyWith(
                          fontSize: 9.5, color: RadarTheme.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: RadarTheme.textFaint),
          const SizedBox(width: 6),
          RadarCaps(label, size: 8, tracking: 0.5),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RadarType.bodySm.copyWith(
                fontSize: 10,
                color: RadarTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EscrowFooter extends StatelessWidget {
  const _EscrowFooter({required this.bounty});

  final StreamBounty bounty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelLowest,
        borderRadius: BorderRadius.circular(RadarRadius.card),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 15, color: RadarTheme.goldBright),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Escrow held on Pi Network — ${fmtPi(bounty.amountPi)} π is released '
              'only after scout approval.',
              style: RadarType.bodySm.copyWith(
                fontSize: 9.5,
                height: 1.35,
                color: RadarTheme.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
