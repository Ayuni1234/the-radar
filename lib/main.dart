import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/state/auth_controller.dart';
import 'src/state/theme_controller.dart';
import 'src/ui/connections_screen.dart';
import 'src/ui/feed_screen.dart';
import 'src/ui/login_screen.dart';
import 'src/ui/market_feed_screen.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/profile_hub_screen.dart';
import 'src/ui/radar_map_screen.dart';
import 'src/ui/radar_theme.dart';
import 'src/ui/settings_screen.dart';
import 'src/ui/shell.dart';

/// Main navigation destinations (shared by the rail and bottom bar).
///
/// Media-first: the Feed is the opening tab. Secondary/management areas
/// (CV, Players directory, Pi Wallet, merchant sales, Safety Center) are
/// consolidated inside the Profile hub instead of crowding the bottom bar.
final List<(String, IconData, Widget)> _destinations = [
  ('Feed', Icons.dynamic_feed, const FeedScreen()),
  ('Radar', Icons.radar, const RadarMapScreen()),
  ('Market', Icons.storefront, const MarketFeedScreen()),
  ('Inbox', Icons.connect_without_contact, const ConnectionsScreen()),
  ('Profile', Icons.person, const ProfileHubScreen()),
];



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the persisted light/dark preference before the first frame so
  // there is no theme flash on boot. Failures keep the dark default.
  final container = ProviderContainer();
  await restoreThemePreference(container);
  runApp(UncontrolledProviderScope(
      container: container, child: const RadarApp()));
}

class RadarApp extends ConsumerWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'The Radar — Global Football Scouting Platform',
      debugShowCheckedModeBanner: false,
      theme: RadarTheme.themeFor(themeMode),
      home: auth.isLoading
          ? const SplashGate()
          : auth.value is AuthSignedIn
              ? (auth.value is AuthSignedIn &&
                      (auth.value as AuthSignedIn).session.needsOnboarding)
                  ? const OnboardingScreen()
                  : const HomeShell()
              : const LoginScreen(),
    );
  }
}

/// Branded splash while Supabase + Pi SDK initialize.
class SplashGate extends StatelessWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const RadarMark(size: 64),
            const SizedBox(height: 18),
            Text(
              'THE RADAR',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 6),
             Text(
              'Global Football Scouting Platform',
              style: TextStyle(color: RadarTheme.textDim),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Responsive navigation shell routing to the four main destinations.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  /// Lets nested screens (e.g. Feed header icons) jump between tabs.
  static void goTo(BuildContext context, int index) {
    context.findAncestorStateOfType<_HomeShellState>()?.goTo(index);
  }

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      body: Row(
        children: [
          if (size == WindowSize.expanded)
            _SideRail(index: _index, onSelect: (i) => setState(() => _index = i)),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [for (final d in _destinations) d.$3],
            ),
          ),
        ],
      ),
      bottomNavigationBar: size == WindowSize.compact
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.$2),
                    selectedIcon: Icon(d.$2, color: RadarTheme.radar),
                    label: d.$1,
                  ),
              ],
            )
          : null,
    );
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        border: Border(right: BorderSide(color: RadarTheme.stroke)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: RadarMark(size: 34),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Text(
              'THE RADAR',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 3),
            ),
          ),
          const SizedBox(height: 22),
          for (final (i, d) in _destinations.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: i == index
                    ? RadarTheme.radar.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => onSelect(i),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    child: Row(
                      children: [
                        Icon(d.$2,
                            size: 20,
                            color: i == index
                                ? RadarTheme.radar
                                : RadarTheme.textDim),
                        const SizedBox(width: 12),
                        Text(
                          d.$1,
                          style: TextStyle(
                            fontWeight: i == index
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == index
                                ? RadarTheme.radar
                                : RadarTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (session != null)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: RadarTheme.panelHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: RadarTheme.pi.withValues(alpha: 0.25),
                    child: Text(
                      session.username.isNotEmpty
                          ? session.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          session.kycVerified ? 'KYC verified' : 'KYC pending',
                          style: TextStyle(
                            fontSize: 11,
                            color: session.kycVerified
                                ? RadarTheme.radar
                                : RadarTheme.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
