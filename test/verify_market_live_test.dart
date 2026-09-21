import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';
import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/market_detail_screen.dart';
import 'package:the_radar/src/ui/merchant_dashboard_screen.dart';
import 'package:the_radar/src/ui/radar_map_screen.dart';

// End-to-end verification of the Market (PitchMarket) tab on the deployed
// build configuration. Two independent pop-free scenarios, each capturing a
// screenshot: feed → listing detail, and feed → merchant dashboard.
//
// Run:  flutter test test/verify_market_live_test.dart --name verify
//       (add --update-goldens to (re)generate the captures)
void main() {
  Future<ProviderContainer> signInAndLandOnRadar(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 892));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: RadarApp()));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadarApp)),
    );
    final auth = container.read(authProvider.notifier);
    unawaited(auth.signInDemo());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    while (tester.takeException() != null) {}

    unawaited(auth.finishOnboarding(
      role: UserRole.scout,
      displayName: 'Demo Scout',
      country: 'United Kingdom',
      city: 'London',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    while (tester.takeException() != null) {}

    expect(find.text('LIVE RADAR'), findsOneWidget);
    return container;
  }

  Future<void> goToMarketTab(WidgetTester tester) async {
    // The shell's jump helper needs a context BELOW the shell (as nested
    // screens use it).
    HomeShell.goTo(tester.element(find.byType(RadarMapScreen)), 2);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'verify: market feed opens a listing detail end-to-end',
    tags: ['golden-capture'],
    (tester) async {
      await signInAndLandOnRadar(tester);
      await expectLater(
        find.byType(RadarApp),
        matchesGoldenFile('goldens/verify_1_radar.png'),
      );

      await goToMarketTab(tester);
      expect(find.text('The PitchMarket'), findsOneWidget);
      await expectLater(
        find.byType(RadarApp),
        matchesGoldenFile('goldens/verify_2_market.png'),
      );

      // Open the first listing's detail screen (pushed route).
      await tester.tap(find.text('DJI Osmo Mobile 6 Gimbal').first);
      await tester.pump(); // start the route transition
      await tester.pump(const Duration(milliseconds: 400)); // finish it
      await tester.pump(const Duration(milliseconds: 300)); // settle providers
      expect(find.byType(MarketDetailScreen), findsOneWidget);
      await expectLater(
        find.byType(RadarApp),
        matchesGoldenFile('goldens/verify_3_detail.png'),
      );
    },
  );

  testWidgets(
    'verify: merchant dashboard is reachable from the market feed',
    tags: ['golden-capture'],
    (tester) async {
      await signInAndLandOnRadar(tester);

      await goToMarketTab(tester);
      expect(find.text('The PitchMarket'), findsOneWidget);

      // The dashboard entry point lives in the feed app bar.
      await tester.tap(find.byIcon(Icons.store_mall_directory_outlined));
      await tester.pump(); // start the route transition
      await tester.pump(const Duration(milliseconds: 400)); // finish it
      await tester.pump(const Duration(milliseconds: 300)); // settle providers
      expect(find.byType(MerchantDashboardScreen), findsOneWidget);
      await expectLater(
        find.byType(RadarApp),
        matchesGoldenFile('goldens/verify_4_merchant.png'),
      );
    },
  );
}
