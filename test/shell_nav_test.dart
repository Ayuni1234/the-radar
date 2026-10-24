import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/bounty_board_screen.dart';
import 'package:the_radar/src/ui/radar_theme.dart';

import 'helpers/mock_path_provider.dart';

/// The phone shell's bottom bar: a fixed bar on the deepest surface with
/// four icon-over-label tabs, the open one lit in the
/// optic pitch green. The map stays mounted inside the shell's IndexedStack,
/// hence the map-cache path mock.
void main() {
  mockPathProviderForMapCache();

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    // Both the view (what MediaQuery reports, and so the layout breakpoints)
    // and the surface (what actually gets painted) need to match.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.binding.setSurfaceSize(size);
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [authProvider.overrideWith(_FixedAuth.new)],
      child: MaterialApp(theme: RadarTheme.dark, home: const HomeShell()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}
  }

  testWidgets('the phone shell shows the five-tab bar', (tester) async {
    await pumpShell(tester, const Size(412, 892));

    // Every tab of the bar is labelled, and the bar is the custom
    // design's — not Material's NavigationBar.
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Radar Map'), findsOneWidget);
    expect(find.text('π Bounties'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    final discover = tester.getRect(find.text('Discover'));
    final map = tester.getRect(find.text('Radar Map'));
    // One bottom band, rail order left to right.
    expect(discover.top, greaterThan(892 * 0.88));
    expect(map.top, greaterThan(892 * 0.88));
    expect(discover.left, lessThan(map.left));

    await tester.tap(find.text('π Bounties'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}

    expect(find.byType(BountyBoardScreen), findsOneWidget,
        reason: 'tapping the π Bounties tab swaps the shell body to the board');
    expect(find.text('Discover'), findsOneWidget,
        reason: 'the bar stays mounted while the tab changes');
  });

  testWidgets('a wide window keeps the side rail instead of the bottom bar',
      (tester) async {
    await pumpShell(tester, const Size(1200, 900));

    expect(find.text('Radar Map'), findsOneWidget);
    expect(find.text('π Bounties'), findsOneWidget);
    // Rail entries sit above the fold; the bottom bar's copies are gone.
    final first = tester.getRect(find.text('Discover').first);
    expect(first.top, lessThan(900 * 0.5));
  });
}

/// Fixed signed-in session (no Pi SDK in widget tests).
class _FixedAuth extends AuthController {
  @override
  Future<AuthState> build() => Future.value(AuthSignedIn(const RadarSession(
        piUid: 'test-uid',
        username: 'tester',
        kycVerified: true,
        isDemo: true,
      )));
}
