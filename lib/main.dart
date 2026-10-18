import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app_brand.dart';
import 'src/state/auth_controller.dart';
import 'src/state/theme_controller.dart';
import 'src/ui/design/radar_design.dart';
import 'src/ui/feed_screen.dart';
import 'src/ui/login_screen.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/player_passport_screen.dart';
import 'src/ui/radar_map_screen.dart';
import 'src/ui/radar_theme.dart';
import 'src/ui/review_room_screen.dart';
import 'src/ui/bounty_board_screen.dart';
import 'src/ui/settings_screen.dart';
import 'src/ui/shell.dart';

/// Main navigation destinations — exactly the five tabs drawn in the uploaded
/// design spec: Discover / Radar Map / π Bounties / Passport / Review.
/// Secondary areas (Inbox, PitchMarket, CV, directory, wallet, safety) live
/// behind the header avatar in the account hub.
final List<(String, String, IconData, Widget)> _destinations = [
  ('Discover', 'Talent discovery reels', Icons.movie_outlined, const FeedScreen()),
  ('Radar Map', 'Live pitch radar', Icons.radar, const RadarMapScreen()),
  ('π Bounties', 'Pi escrow gig board', Icons.monetization_on_outlined, const BountyBoardScreen()),
  ('Passport', 'Player passport & schedule', Icons.badge_outlined, const PlayerPassportScreen()),
  ('Review', 'Scout review room', Icons.verified_outlined, const ReviewRoomScreen()),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Release builds swap a failed subtree for a plain black box, which on the
  // live link is indistinguishable from a page that never booted at all.
  // Paint a branded panel that names the failure instead, so a broken screen
  // is visible (and reportable) rather than silently black.
  ErrorWidget.builder = (details) => RadarErrorPanel(
        message: details.exceptionAsString(),
      );

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
      title: AppBrand.fullTitle,
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

/// Fallback painted wherever a widget fails to build. Deliberately free of
/// Material/Theme dependencies: it can be inserted above `MaterialApp`, where
/// none of those exist yet.
class RadarErrorPanel extends StatelessWidget {
  const RadarErrorPanel({super.key, this.message = ''});

  /// The failure text, shown muted under the title so a screenshot of the
  /// live app still says what broke.
  final String message;

  @override
  Widget build(BuildContext context) {
    final detail = message.trim();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0F131D),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RadarMark(size: 46),
                const SizedBox(height: 16),
                const Text(
                  'This screen could not be drawn',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFDFE2F0),
                    fontFamily: RadarFonts.heading,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reopen THE RADAR — the rest of the app keeps working.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB9CBB9), fontSize: 12.5),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    detail.length > 220 ? detail.substring(0, 220) : detail,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF849584),
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
              AppBrand.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 6),
             Text(
              AppBrand.tagline,
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

  /// Walks back through the tabs the viewer has visited — the feed header's
  /// back control calls this before it leaves the shell. Returns false when
  /// there is nothing left to go back to.
  static bool goBack(BuildContext context) =>
      context.findAncestorStateOfType<_HomeShellState>()?.goBack() ?? false;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  /// Tabs visited before the current one, most recent last. Bounded so a long
  /// session cannot grow it without limit.
  final List<int> _trail = <int>[];

  void goTo(int i) {
    if (i == _index) return;
    setState(() {
      _trail.add(_index);
      if (_trail.length > 8) _trail.removeAt(0);
      _index = i;
    });
  }

  bool goBack() {
    if (_trail.isNotEmpty) {
      setState(() => _index = _trail.removeLast());
      return true;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      body: Row(
        children: [
          if (size == WindowSize.expanded)
            _SideRail(index: _index, onSelect: goTo),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [for (final d in _destinations) d.$4],
            ),
          ),
        ],
      ),
      bottomNavigationBar: size == WindowSize.compact
          ? _RadarNavBar(index: _index, onSelect: goTo)
          : null,
    );
  }
}

/// Bottom navigation exactly as drawn in the spec: a fixed 80px bar on the
/// deepest surface, five icon-over-label tabs in Space Grotesk caps, the active
/// tab lit optic green with a lumen drop-shadow, and a pulsing Pi-gold beacon
/// on Bounties.
class _RadarNavBar extends StatelessWidget {
  const _RadarNavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RadarTheme.panelLowest.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: RadarTheme.stroke)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (final (i, d) in _destinations.indexed)
                Expanded(
                  child: _NavBarItem(
                    label: d.$1,
                    tooltip: d.$2,
                    icon: d.$3,
                    selected: i == index,
                    beacon: i == 2,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.beacon = false,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final bool selected;
  final bool beacon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? RadarTheme.radar : RadarTheme.textDim;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: beacon ? 26 : 23,
                  color: color,
                  shadows: selected
                      ? [
                          Shadow(
                            color: RadarTheme.radar.withValues(alpha: 0.55),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                if (beacon)
                  Positioned(
                    top: -1,
                    right: -3,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: RadarTheme.goldBright,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: RadarTheme.gold
                                .withValues(alpha: 0.7),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RadarType.caps.copyWith(
                fontSize: 10,
                letterSpacing: 0.2,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
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
              AppBrand.name,
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
                        Icon(d.$3,
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
