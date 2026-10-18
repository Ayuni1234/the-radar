import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_brand.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'design/radar_design.dart';
import 'radar_theme.dart';
import 'shell.dart' show RadarMark;

/// Height of the shipped top bar (the spec's `h-20`), excluding the status
/// bar inset that [SafeArea] adds above it.
const double kRadarTopBarHeight = 80;

/// The single top bar from the uploaded design: radar mark, `RADAR` wordmark
/// with the PRO pill, the live region line, the Pi balance and the avatar.
///
/// It is built once per screen and pinned above the content — never repeated
/// inside a pager or a list.
class RadarTopBar extends ConsumerWidget {
  const RadarTopBar({
    super.key,
    this.onBack,
    this.onAvatarTap,
    this.onBalanceTap,
    this.showPro = true,
    this.locationOverride,
    this.trailing,
  });

  /// Shows a back chevron ahead of the mark on pushed routes.
  final VoidCallback? onBack;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBalanceTap;
  final bool showPro;
  final String? locationOverride;

  /// Extra control rendered before the balance chip (wide layouts).
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final live = ref.watch(filteredEventsProvider).where((e) => e.isLive).length;
    final region = (session?.regionLabel ?? '').trim();
    final place = locationOverride ??
        (region.isEmpty ? (session?.displayName ?? 'Global radar') : region);
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final myId = session?.profileId;
    UserProfile? profile;
    if (myId != null) {
      for (final p in profiles) {
        if (p.id == myId) {
          profile = p;
          break;
        }
      }
    }
    final name = profile?.bestName ?? session?.username ?? '';

    return Container(
      key: const ValueKey('radar-top-bar'),
      color: RadarTheme.panelLowest.withValues(alpha: 0.92),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kRadarTopBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RadarSpace.md),
            child: Row(
              children: [
                if (onBack != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: _BarIcon(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onTap: onBack!,
                    ),
                  ),
                RadarMark(size: onBack == null ? 34 : 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              AppBrand.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RadarType.heading(
                                22,
                                weight: FontWeight.w700,
                                color: const Color(0xFFF0FFEE),
                                tracking: 1.3,
                                height: 1.0,
                              ),
                            ),
                          ),
                          if (showPro) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: RadarTheme.panelHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'PRO',
                                style: RadarType.caps.copyWith(
                                  fontSize: 8.5,
                                  color: RadarTheme.radar,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const LiveDot(size: 6, animate: false),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '$place • $live live ${live == 1 ? 'pitch' : 'pitches'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RadarType.caps.copyWith(
                                fontSize: 9.5,
                                letterSpacing: 0.5,
                                color: RadarTheme.textDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ?trailing,
                _PiBalanceChip(onTap: onBalanceTap),
                const SizedBox(width: 8),
                _AvatarButton(name: name, url: profile?.avatarUrl, onTap: onAvatarTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 21, color: RadarTheme.textDim),
        ),
      ),
    );
  }
}

class _PiBalanceChip extends StatelessWidget {
  const _PiBalanceChip({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: const ValueKey('pi-balance-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: RadarTheme.panelHighest,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: RadarTheme.gold.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: RadarTheme.goldBright,
                shape: BoxShape.circle,
              ),
              child: Text(
                'π',
                style: RadarType.caps.copyWith(
                  fontSize: 10,
                  color: const Color(0xFF442B00),
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '142.50',
              style: RadarType.metricMd.copyWith(
                fontSize: 15,
                color: RadarTheme.goldBright,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({this.name = '', this.url, this.onTap});

  final String name;
  final String? url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RadarAvatar(
        name: name.isEmpty ? 'Radar' : name,
        url: url,
        size: 32,
        ring: RadarTheme.radar.withValues(alpha: 0.30),
      ),
    );
  }
}

/// Height the fixed bar occupies in a screen's body (includes the status inset
/// when it hasn't been applied by [SafeArea] yet).
double radarTopBarExtent(BuildContext context) =>
    kRadarTopBarHeight + MediaQuery.paddingOf(context).top;
