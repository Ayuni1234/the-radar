import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';
import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/market_detail_screen.dart';
import 'package:the_radar/src/ui/merchant_dashboard_screen.dart';
import 'package:the_radar/src/ui/profile_hub_screen.dart';
import 'package:the_radar/src/ui/radar_map_screen.dart';

import 'helpers/mock_path_provider.dart';

// End-to-end verification of the Market (PitchMarket) tab on the deployed
// build configuration. Two independent pop-free scenarios, each capturing a
// screenshot: feed → listing detail, and feed → merchant dashboard.
//
// Run:  flutter test test/verify_market_live_test.dart --name verify
//       (add --update-goldens to (re)generate the captures)
void main() {
  mockPathProviderForMapCache();

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
      birthYear: 1990,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    while (tester.takeException() != null) {}

    // The branded feed header renders the official app name.
    expect(find.text('THE RADAR'), findsOneWidget);
    return container;
  }

  Future<void> goToMarketTab(WidgetTester tester) async {
    // Market moved off the bottom bar: it is now a Profile hub tile that
    // pushes MarketFeedScreen. Jump to the Profile tab (4-tab nav:
    // Reels / Map / Bounty / Profile), then open the PitchMarket tile.
    // The shell's jump helper needs a context BELOW the shell (as nested
    // screens use it). Offstage tabs stay mounted in the IndexedStack, so
    // the radar screen is found with skipOffstage: false.
    HomeShell.goTo(
      tester.element(find.byType(RadarMapScreen, skipOffstage: false)),
      3,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('The PitchMarket'));
    await tester.pump(); // start the route transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets(
    'verify: profile hub consolidates secondary features',
    tags: ['golden-capture'],
    (tester) async {
      await signInAndLandOnRadar(tester);

      // Media-first: the app must open on the Feed — now a full-bleed
      // vertical reel (PageView), not a scrolling card list.
      expect(find.byType(PageView), findsOneWidget);

      // Profile is now the 4th tab in the hackathon 4-tab nav
      // (Reels / Map / Bounty / Profile).
      HomeShell.goTo(
        tester.element(find.byType(RadarMapScreen, skipOffstage: false)),
        3,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProfileHubScreen), findsOneWidget);
      expect(find.text('My Football CV'), findsOneWidget);
      expect(find.text('Players Directory'), findsOneWidget);
      expect(find.text('Pi Wallet & Orders'), findsOneWidget);
      expect(find.text('My Shop & Sales'), findsOneWidget);
      expect(find.text('Safety Center'), findsOneWidget);
      // The old Market and Inbox tabs consolidated here as hub tiles.
      expect(find.text('The PitchMarket'), findsOneWidget);
      expect(find.text('Inbox & Connections'), findsOneWidget);
      await expectLater(
        find.byType(RadarApp),
        matchesGoldenFile('goldens/verify_5_hub.png'),
      );
    },
  );

  testWidgets(
    'verify: composer location quick actions pin and deep-link a post',
    tags: ['golden-capture'],
    (tester) async {
      await signInAndLandOnRadar(tester);

      // Open the New Post composer.
      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.pump(); // sheet transition
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('New post'), findsOneWidget);

      // Both quick actions are present beneath the location field.
      expect(find.text('Use Current Location'), findsOneWidget);
      expect(find.text('Tag Training Venue'), findsOneWidget);

      // Tag Training Venue picks a seeded slot and pins the post to it.
      await tester.tap(find.text('Tag Training Venue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Tag a training venue or time slot'), findsOneWidget);

      // Pick a seeded venue tile by its title (real coordinates behind it).
      await tester.tap(find.text('Morning technical session (invite)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The pin applied: label + area populated.
      expect(find.textContaining('Venue · '), findsOneWidget);

      await expectLater(
        find.byType(RadarApp),
        matchesGoldenFile('goldens/verify_6_composer_location.png'),
      );
    },
  );
}
