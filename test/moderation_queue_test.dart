import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/data/demo_seed.dart';
import 'package:the_radar/src/models/content_report.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/moderation_queue_screen.dart';
import 'package:the_radar/src/ui/radar_theme.dart';

/// Moderation queue workflow, against the offline demo store (no Supabase).
/// The seed holds 4 reports: 2 open, 1 reviewing, 1 dismissed.
///
/// The session override is what the RLS read-path stands in for offline:
/// the queue's own gate (session.isAdmin) plus repository behaviour — the
/// database's row filtering itself is asserted by the SQL in migration 0004.
void main() {
  tearDown(DemoSeed.resetDemoStores);

  RadarSession adminSession() => RadarSession(
        piUid: 'pi-admin',
        username: 'ops_admin',
        kycVerified: true,
        isDemo: true,
        profileId: 'demo-admin-1',
        isAdmin: true,
      );

  Widget harness({RadarSession? session}) {
    return ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => session),
      ],
      child: MaterialApp(theme: RadarTheme.dark, home: const ModerationQueueScreen()),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tall test surface: with 3+ cards the lower queue entries would sit
  /// below the default 800×600 viewport and ListView never builds them.
  Future<void> pumpQueue(WidgetTester tester, RadarSession? session) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(session: session));
    await settle(tester);
  }

  testWidgets('non-admin session gets the no-access panel', (tester) async {
    await pumpQueue(tester, null);

    expect(find.text('No moderation access'), findsOneWidget);
  });

  testWidgets('queue bucket shows open + reviewing reports with counts',
      (tester) async {
    await pumpQueue(tester, adminSession());

    expect(find.text('3 awaiting review'), findsOneWidget);
    expect(find.text('Spam or scam'), findsOneWidget);
    expect(find.text('Minor safety concern'), findsOneWidget);
    expect(find.text('Misleading or fake content'), findsOneWidget);
    // Closed reports stay in their own bucket.
    expect(find.text('Something else'), findsNothing);
  });

  testWidgets('start review moves an open report into reviewing',
      (tester) async {
    await pumpQueue(tester, adminSession());

    await tester.tap(find.text('Start review').first);
    await settle(tester);

    // Still in the queue bucket, now reviewing (gold chip) — and the demo
    // store itself was mutated, proving the repository path ran.
    expect(DemoSeed.contentReports
            .firstWhere((r) => r.id == 'demo-report-1')
            .status,
        ContentReportStatus.reviewing);
    expect(find.text('Reviewing'), findsWidgets);
  });

  testWidgets('resolve confirms, then files the report away', (tester) async {
    await pumpQueue(tester, adminSession());

    await tester.tap(find.text('Resolve').first);
    await tester.pump(); // dialog opens
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Resolve report?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Resolved').last);
    await settle(tester);

    expect(DemoSeed.contentReports
            .firstWhere((r) => r.id == 'demo-report-1')
            .status,
        ContentReportStatus.resolved);
    // Queue bucket no longer holds it.
    expect(find.text('Spam or scam'), findsNothing);
    expect(find.text('2 awaiting review'), findsOneWidget);

    // It landed in the Resolved bucket.
    await tester.tap(find.text('Resolved (1)'));
    await settle(tester);
    expect(find.text('Spam or scam'), findsOneWidget);
  });

  testWidgets('dismiss closes the report after confirmation', (tester) async {
    await pumpQueue(tester, adminSession());

    await tester.tap(find.text('Dismiss').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(FilledButton, 'Dismissed').last);
    await settle(tester);

    expect(DemoSeed.contentReports
            .firstWhere((r) => r.id == 'demo-report-1')
            .status,
        ContentReportStatus.dismissed);
    expect(find.text('2 awaiting review'), findsOneWidget);
  });

  testWidgets('resolved reports can be reopened for review', (tester) async {
    await pumpQueue(tester, adminSession());

    await tester.tap(find.text('Dismissed (1)'));
    await settle(tester);
    await tester.tap(find.text('Reopen review'));
    await settle(tester);

    expect(DemoSeed.contentReports
            .firstWhere((r) => r.id == 'demo-report-4')
            .status,
        ContentReportStatus.reviewing);
    // And it returned to the active queue bucket.
    await tester.tap(find.text('Queue (4)'));
    await settle(tester);
    expect(find.text('Something else'), findsOneWidget);
  });
}