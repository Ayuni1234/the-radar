import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_controller.dart'
    show RadarSession, sessionProvider, authProvider;
import 'radar_theme.dart';
import 'shell.dart' show SectionHeader;
import 'cv_editor_screen.dart';
import 'merchant_dashboard_screen.dart';
import 'payments_screen.dart';
import 'profiles_screen.dart';
import 'safeguarding_screen.dart';
import 'settings_screen.dart';

/// The master Profile / Hub — the fifth bottom-navigation destination.
///
/// Consolidates everything that used to crowd the old 8-item bottom bar:
/// My CV, the Players directory, the Pi Wallet (with order history), the
/// merchant dashboard (sales summary) and the Safety Center live here as a
/// tidy, high-end hub instead of competing for bar slots.
class ProfileHubScreen extends ConsumerWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _HubHeader(session: session),
            const SizedBox(height: 24),
            _HubTile(
              icon: Icons.badge_outlined,
              accent: RadarTheme.pi,
              title: 'My Football CV',
              subtitle:
                  'Stats, highlights and video reels — your scouting résumé.',
              onTap: () => _push(context, const CvEditorScreen()),
            ),
            const SizedBox(height: 10),
            SectionHeader('Manage'),
            _HubTile(
              icon: Icons.groups,
              accent: RadarTheme.radar,
              title: 'Players Directory',
              subtitle: 'Browse and scout player profiles across the network.',
              onTap: () => _push(context, const ProfilesScreen()),
            ),
            _HubTile(
              icon: Icons.account_balance_wallet,
              accent: RadarTheme.gold,
              title: 'Pi Wallet & Orders',
              subtitle:
                  'Balance, boosts, transaction ledger and PitchMarket orders.',
              onTap: () => _push(context, const PaymentsScreen()),
            ),
            _HubTile(
              icon: Icons.store_mall_directory_outlined,
              accent: RadarTheme.pi,
              title: 'My Shop & Sales',
              subtitle:
                  'Merchant dashboard — inventory, units sold and Pi earned.',
              onTap: () => _push(context, const MerchantDashboardScreen()),
            ),
            _HubTile(
              icon: Icons.shield_outlined,
              accent: RadarTheme.radar,
              title: 'Safety Center',
              subtitle:
                  'Consents, guardian controls, blocked accounts and reports.',
              onTap: () => _push(context, const SafeguardingScreen()),
            ),
            _HubTile(
              icon: Icons.manage_accounts,
              accent: RadarTheme.gold,
              title: 'Account & Roles',
              subtitle:
                  'Sign-in settings, role management and app preferences.',
              onTap: () => _push(context, const SettingsScreen()),
            ),
            const SizedBox(height: 28),
            _SignOutTile(),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _HubHeader extends ConsumerWidget {
  const _HubHeader({required this.session});

  final RadarSession? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final name = s?.username ?? 'Guest scout';
    final roleLabel = s?.role.label ?? 'Scout';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RadarTheme.panelHigh.withValues(alpha: 0.85),
            RadarTheme.panel.withValues(alpha: 0.65),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:  LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [RadarTheme.radar, RadarTheme.pi],
              ),
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration:  BoxDecoration(
                shape: BoxShape.circle,
                color: RadarTheme.ink,
              ),
              alignment: Alignment.center,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style:  TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: RadarTheme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: RadarTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _pill(roleLabel, RadarTheme.pi),
                    if (s != null && s.kycVerified)
                      _pill('KYC verified', RadarTheme.radar),
                    if (s?.isDemo ?? false) _pill('Demo', RadarTheme.gold),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RadarTheme.stroke),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: accent.withValues(alpha: 0.45)),
                  ),
                  child: Icon(icon, size: 22, color: accent),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:  TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: RadarTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:  TextStyle(
                          fontSize: 12,
                          color: RadarTheme.textDim,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                 Icon(Icons.chevron_right,
                    size: 20, color: RadarTheme.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: RadarTheme.panel,
              title: const Text('Sign out?'),
              content: const Text(
                  'Your session on this device will be cleared. Demo '
                  'progress is stored locally and may be lost.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: RadarTheme.alert,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          );
          if (confirmed ?? false) {
            await ref.read(authProvider.notifier).signOut();
          }
        },
        icon:  Icon(Icons.logout, size: 17, color: RadarTheme.textDim),
        label:  Text('Sign out',
            style: TextStyle(color: RadarTheme.textDim)),
      ),
    );
  }
}
