import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import '../supabase/supabase_config.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Account Settings & Role Management — centralized control over roles,
/// regional preferences, Pi session state, privacy and account actions.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _countryCtrl;
  late final TextEditingController _cityCtrl;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    final profiles = ref.read(profilesProvider).value ?? const [];
    UserProfile? mine;
    final pid = session?.profileId;
    if (pid != null) {
      for (final p in profiles) {
        if (p.id == pid) mine = p;
      }
    }
    _countryCtrl = TextEditingController(text: mine?.country ?? '');
    _cityCtrl = TextEditingController(text: mine?.city ?? '');
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final profiles = ref.watch(profilesProvider).value ?? const [];
    final pid = session?.profileId;
    UserProfile? mine;
    if (pid != null) {
      for (final p in profiles) {
        if (p.id == pid) mine = p;
      }
    }
    final live = SupabaseConfig.available;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(title: const Text('Account settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          _IdentityCard(session: session, profile: mine, live: live),
          const SizedBox(height: 14),
          _RoleSection(
            session: session,
            currentRole: mine?.role ?? session?.role ?? UserRole.player,
          ),
          const SizedBox(height: 14),
          _RegionSection(
            countryCtrl: _countryCtrl,
            cityCtrl: _cityCtrl,
            isPublic: mine?.isPublic ?? true,
            onPublicChanged: (v) => _setPublic(v),
            onSaveRegion: () => _saveRegion(),
          ),
          const SizedBox(height: 14),
          _SessionSection(
            session: session,
            live: live,
            tokenPreview: _tokenPreview(session),
            onRefresh: _refreshToken,
            onSignOut: () async {
              await ref.read(authProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: 14),
          _DataSection(
            onExport: _exportData,
            onDelete: _deleteAccount,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  String _tokenPreview(RadarSession? session) {
    final t = session?.accessToken ?? '';
    if (t.isEmpty) return '—';
    return '${t.substring(0, t.length > 12 ? 12 : t.length)}…'
        '${t.substring(t.length - 4 > 0 ? t.length - 4 : 0)}';
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? RadarTheme.alert : RadarTheme.panelHigh,
      content: Text(msg,
          style: const TextStyle(color: RadarTheme.textPrimary)),
    ));
  }

  Future<void> _setPublic(bool v) async {
    final err = await ref
        .read(authProvider.notifier)
        .updateAccount(isPublic: v);
    if (!mounted) return;
    err == null
        ? _toast(v ? 'Profile is public.' : 'Profile hidden from the directory.')
        : _toast(err, error: true);
  }

  Future<void> _saveRegion() async {
    final err = await ref.read(authProvider.notifier).updateAccount(
          country: _countryCtrl.text,
          city: _cityCtrl.text,
        );
    if (!mounted) return;
    err == null
        ? _toast('Region updated.')
        : _toast(err, error: true);
  }

  Future<void> _refreshToken() async {
    final err =
        await ref.read(authProvider.notifier).refreshSessionToken();
    if (!mounted) return;
    err == null
        ? _toast('Session token refreshed.')
        : _toast(err, error: true);
  }

  Future<void> _exportData() async {
    final json = await ref.read(authProvider.notifier).exportAccountData();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RadarTheme.panel,
        title: const Text('Your data export'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'A JSON copy is on your clipboard. The full export is below — '
              'select and copy it anywhere.',
              style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim),
            ),
            const SizedBox(height: 10),
            Container(
              height: 200,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RadarTheme.ink,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: RadarTheme.stroke),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: const TextStyle(
                      fontSize: 10.5, fontFamily: 'monospace'),
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: RadarTheme.panel,
          title: const Text('Delete account'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'This permanently removes your profile, hosted events and '
              'connection requests. Guardian consent records are retained '
              'for safeguarding compliance. Type DELETE to confirm.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'DELETE',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: RadarTheme.alert),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );
    if (confirmed == null || !mounted) return;
    final err = await ref
        .read(authProvider.notifier)
        .deleteAccount(confirmed);
    if (!mounted) return;
    if (err != null) _toast(err, error: true);
    // On success the auth state flips to signed-out and the app routes
    // back to the login screen automatically.
  }
}

// ---------------------------------------------------------------------------
// Identity header
// ---------------------------------------------------------------------------

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.session,
    required this.profile,
    required this.live,
  });

  final RadarSession? session;
  final UserProfile? profile;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: RadarTheme.pi.withValues(alpha: 0.22),
          child: Text(
            (s?.username.isNotEmpty ?? false)
                ? s!.username[0].toUpperCase()
                : '?',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s?.username ?? '—',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                InfoPill(
                  icon: live ? Icons.cloud_done : Icons.offline_bolt,
                  label: live ? 'Supabase connected' : 'Demo mode',
                  color: live ? RadarTheme.radar : RadarTheme.gold,
                ),
                InfoPill(
                  icon: (s?.kycVerified ?? false)
                      ? Icons.verified_user_outlined
                      : Icons.gpp_maybe_outlined,
                  label: (s?.kycVerified ?? false)
                      ? 'KYC verified'
                      : 'KYC pending',
                  color: (s?.kycVerified ?? false)
                      ? RadarTheme.radar
                      : RadarTheme.gold,
                ),
                if (profile != null)
                  InfoPill(
                      icon: Icons.insights,
                      label:
                          'Credibility ${profile!.credibilityScore.round()}',
                      color: RadarTheme.gold),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Role management
// ---------------------------------------------------------------------------

class _RoleSection extends ConsumerWidget {
  const _RoleSection({required this.session, required this.currentRole});

  final RadarSession? session;
  final UserRole currentRole;

  Future<void> _pick(BuildContext context, WidgetRef ref, UserRole role) async {
    if (role == currentRole) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RadarTheme.panel,
        title: Text('Switch to ${role.label}?'),
        content: Text(
          'Your primary role shapes your onboarding prompts, permissions '
          'and how others see you on the platform. You can switch back '
          'any time.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch role')),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await ref.read(authProvider.notifier).updateAccount(
          role: role,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            err == null ? RadarTheme.panelHigh : RadarTheme.alert,
        content: Text(err ?? 'Primary role is now ${role.label}.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.switch_account_outlined, size: 17,
              color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Role management',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Your current primary role is ${currentRole.label}. Tap another '
          'role to switch — permissions and visibility follow instantly.',
          style: const TextStyle(
              fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in UserRole.values)
              InkWell(
                onTap: () => _pick(context, ref, r),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: r == currentRole
                        ? RadarTheme.radar.withValues(alpha: 0.14)
                        : RadarTheme.panelHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: r == currentRole
                          ? RadarTheme.radar
                          : RadarTheme.stroke,
                      width: r == currentRole ? 1.4 : 1,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(r.icon,
                        size: 15,
                        color: r == currentRole
                            ? RadarTheme.radar
                            : RadarTheme.textDim),
                    const SizedBox(width: 7),
                    Text(r.label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: r == currentRole
                                ? RadarTheme.radar
                                : RadarTheme.textPrimary)),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Region & preferences
// ---------------------------------------------------------------------------

class _RegionSection extends StatelessWidget {
  const _RegionSection({
    required this.countryCtrl,
    required this.cityCtrl,
    required this.isPublic,
    required this.onPublicChanged,
    required this.onSaveRegion,
  });

  final TextEditingController countryCtrl;
  final TextEditingController cityCtrl;
  final bool isPublic;
  final ValueChanged<bool> onPublicChanged;
  final VoidCallback onSaveRegion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.tune_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Preferences & region',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: countryCtrl,
              decoration: const InputDecoration(
                labelText: 'Country',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: cityCtrl,
              decoration: const InputDecoration(
                labelText: 'City / regional base',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: onSaveRegion,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save region'),
          ),
        ),
        const Divider(height: 24, color: RadarTheme.stroke),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: isPublic,
          onChanged: onPublicChanged,
          title: const Text('Public profile visibility',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'When off, your profile is hidden from the directory and search. '
            'Enforced by the database, not just the app.',
            style: TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Pi wallet & session
// ---------------------------------------------------------------------------

class _SessionSection extends StatelessWidget {
  const _SessionSection({
    required this.session,
    required this.live,
    required this.tokenPreview,
    required this.onRefresh,
    required this.onSignOut,
  });

  final RadarSession? session;
  final bool live;
  final String tokenPreview;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 17,
              color: RadarTheme.pi),
          SizedBox(width: 8),
          Expanded(
            child: Text('Pi Network & session',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        _kv('Wallet identity',
            s == null ? '—' : 'Pi user · ${s.username}'),
        _kv('Wallet address',
            s?.piUid.isEmpty ?? true ? '—' : 'pi:${s!.piUid}'),
        _kv('Session state', live ? 'Active (live Supabase session)' : 'Demo (offline)'),
        _kv('Access token', tokenPreview),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh token'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              style: OutlinedButton.styleFrom(
                  foregroundColor: RadarTheme.alert),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Sign out'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          SizedBox(
              width: 128,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12, color: RadarTheme.textDim))),
          Expanded(
            child: Text(v,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Data & account actions
// ---------------------------------------------------------------------------

class _DataSection extends StatelessWidget {
  const _DataSection({required this.onExport, required this.onDelete});

  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.alert.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.download_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Data & account actions',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text('Export my data (JSON)'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Danger zone',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: RadarTheme.alert,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
                foregroundColor: RadarTheme.alert),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Terminate account'),
          ),
        ),
      ]),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
      color: RadarTheme.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: RadarTheme.stroke),
    );
