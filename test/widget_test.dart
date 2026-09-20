import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';

void main() {
  testWidgets('RadarApp renders the login screen with demo entry',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RadarApp()));
    await tester.pumpAndSettle();

    expect(find.text('THE RADAR'), findsWidgets);
    expect(find.text('Global Football Scouting Platform'), findsWidgets);
    expect(find.text('Explore demo mode'), findsOneWidget);
    expect(find.text('Continue with Pi'), findsOneWidget);
  });

  testWidgets('Demo sign-in lands on onboarding, which reaches the home shell',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RadarApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Explore demo mode'));
    // Explicit pumps: the radar sweep animates forever, so pumpAndSettle
    // would never settle past the home shell.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // New users land on the guided onboarding wizard first.
    expect(find.text('Join The Radar'), findsOneWidget);

    // Step 1 — pick a role. (Buttons live inside the scroll view; drag them
    // into view before tapping on the small test surface.)
    await tester.tap(find.text('Player'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 250));

    // Step 2 — country is required.
    expect(find.text('Where do you scout for talent?'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('onboarding-country')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
        find.byKey(const ValueKey('onboarding-country')), 'Cameroon');
    await tester.enterText(
        find.byKey(const ValueKey('onboarding-city')), 'Douala');
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 250));

    // Step 3 — display name is required.
    expect(find.text('Set up your profile'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('onboarding-name')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
        find.byKey(const ValueKey('onboarding-name')), 'Demo Scout');
    await tester.enterText(
        find.byKey(const ValueKey('onboarding-bio')), 'Testing onboarding.');
    await tester.scrollUntilVisible(
      find.text('Enter The Radar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enter The Radar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('LIVE RADAR'), findsOneWidget);
    // 800×600 test surface → medium layout → NavigationRail, not bottom bar.
    expect(find.byType(NavigationBar), findsNothing);
  });
}
