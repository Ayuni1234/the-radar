import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/bounty_board_screen.dart';
import 'package:the_radar/src/ui/radar_theme.dart';

import 'helpers/mock_path_provider.dart';

/// The phone shell's bottom bar — the mockup's chrome under the reels: a dark
/// bar where the open tab is a violet pill (icon + label) and the rest sit as
/// quiet icon-over-label pairs. The map stays mounted inside the shell's
/// IndexedStack, hence the map-cache path mock.
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

  testWidgets('the phone shell shows the four-tab bar with a violet active pill',
      (tester) async {
    await pumpShell(tester, const Size(412, 892));

    // Every tab is labelled, and the bar is the custom mockup one — not
    // Material's NavigationBar.
    expect(find.text('Reels'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Bounty'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    final reels = tester.getRect(find.text('Reels'));
    final map = tester.getRect(find.text('Map'));
    // One bottom band, active pill first: the mockup puts "Reels" on the left
    // inside the violet pill, with Map / Bounty / Profile beside it.
    expect(reels.top, greaterThan(892 * 0.88));
    expect(map.top, greaterThan(892 * 0.88));
    expect(reels.left, lessThan(map.left));

    await tester.tap(find.text('Bounty'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}

    expect(find.byType(BountyBoardScreen), findsOneWidget,
        reason: 'tapping Bounty swaps the shell body to the gig board');
    expect(find.text('Reels'), findsOneWidget,
        reason: 'the bar stays mounted while the tab changes');
  });

  testWidgets('a wide window keeps the side rail instead of the bottom bar',
      (tester) async {
    await pumpShell(tester, const Size(1200, 900));

    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Bounty'), findsOneWidget);
    // Rail entries sit above the fold; the bottom bar's copies are gone.
    final first = tester.getRect(find.text('Reels').first);
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
