import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/models/stream_bounty.dart';
import 'package:the_radar/src/ui/bounty_fulfillment_flow.dart';
import 'package:the_radar/src/ui/radar_theme.dart';

import 'helpers/mock_path_provider.dart';

/// The escrow workflow is the four steps from the spec, in order:
/// GPS Check-In -> Record -> Upload -> Request Payment. Each step unlocks
/// only after the one before it is done.
void main() {
  mockPathProviderForMapCache();

  StreamBounty bounty() => StreamBounty(
        id: 'b1',
        posterProfileId: 'poster',
        posterName: 'Poster',
        title: 'Saturday trial footage',
        brief: 'Film the match',
        areaName: 'Limbe — Omnisport Annex',
        amountPi: 20,
        durationMinutes: 60,
        status: 'open',
        createdAt: DateTime(2026, 10, 1),
      );

  Future<void> pumpFlow(WidgetTester tester, StreamBounty b) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: RadarTheme.dark,
        home: BountyFulfillmentFlow(bounty: b),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows the four spec steps in order', (tester) async {
    await pumpFlow(tester, bounty());

    final titles = ['GPS Check-In', 'Record', 'Upload', 'Request Payment'];
    final rects = [
      for (final t in titles) tester.getRect(find.text(t.toUpperCase()).first)
    ];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].left),
          reason: '${titles[i]} sits after ${titles[i - 1]} in the rail');
    }
  });

  testWidgets('a fresh gig starts on GPS Check-In with later steps locked',
      (tester) async {
    await pumpFlow(tester, bounty());

    expect(find.text('CONFIRM LOCATION'), findsOneWidget);

    // Jumping ahead to Request Payment is blocked: the rail only opens a step
    // once the one before it is done, so the payment step stays unreachable.
    await tester.tap(find.text('REQUEST PAYMENT').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Finish the first three steps'), findsNothing,
        reason: 'payment step does not open before steps 1-3 are done');
    expect(find.text('CONFIRM LOCATION'), findsOneWidget);
  });
}
