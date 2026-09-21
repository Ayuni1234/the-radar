import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';
import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/live_event_map.dart';
import 'package:the_radar/src/ui/radar_map_screen.dart';

import 'helpers/mock_path_provider.dart';

// Golden-style capture: signs in through the auth controller (bypassing the
// onboarding wizard's phone-width overflows), lands on the Radar tab and
// writes the screen to test/goldens/radar_tab.png.
//
// Run:  flutter test test/golden_radar_screen_test.dart --name capture
//       (add --update-goldens to (re)generate the PNG)
void main() {
  mockPathProviderForMapCache();

  // Tagged `golden-capture`: pixel goldens are OS/renderer-dependent, so this
  // is excluded from CI (ubuntu runner) and runs only on the machine that
  // regenerates the capture: flutter test --name capture --update-goldens.
  testWidgets(
    'capture: radar tab screenshot',
    tags: ['golden-capture'],
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: RadarApp()));
    await tester.pumpAndSettle();

    // Records any buffered layout exceptions as handled (the pre-existing
    // login/onboarding phone-width overflows flash transiently here and
    // would otherwise fail the test after the golden was written).
    void drainExceptions() {
      while (tester.takeException() != null) {}
    }

    drainExceptions();

    // Sign in as the demo user, then finish onboarding headlessly.
    // Note: fake-test time only advances via pumps, and the Radar tab's
    // pulsing markers animate forever — so no pumpAndSettle past onboarding.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadarApp)),
    );
    final auth = container.read(authProvider.notifier);
    unawaited(auth.signInDemo());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    drainExceptions();

    unawaited(auth.finishOnboarding(
      role: UserRole.scout,
      displayName: 'Demo Scout',
      country: 'United Kingdom',
      city: 'London',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Let the map + markers mount and paint a few frames.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    drainExceptions();

    expect(find.text('LIVE RADAR'), findsOneWidget);
    // Feed-first: the app opens on the Feed; switch to the Radar tab for
    // the map capture (its screen stays mounted in the IndexedStack).
    HomeShell.goTo(
      tester.element(find.byType(RadarMapScreen, skipOffstage: false)),
      1,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    drainExceptions();

    // The live map mounts in both branches (OSM tiles, or the painted
    // canvas fallback when tiles can't load in the test binding).
    expect(find.byType(LiveEventMap), findsOneWidget);

    await expectLater(
      find.byType(RadarApp),
      matchesGoldenFile('goldens/radar_tab.png'),
    );
    },
  );
}
