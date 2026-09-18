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

  testWidgets('Demo sign-in reaches the home shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RadarApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Explore demo mode'));
    // Explicit pumps: the radar sweep animates forever, so pumpAndSettle
    // would never settle past the home shell.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('LIVE RADAR'), findsOneWidget);
    // 800×600 test surface → medium layout → NavigationRail, not bottom bar.
    expect(find.byType(NavigationBar), findsNothing);
  });
}
