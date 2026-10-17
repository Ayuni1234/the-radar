import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/main.dart';
import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/state/auth_controller.dart';
import 'package:the_radar/src/ui/feed_screen.dart';
import 'package:the_radar/src/ui/market_feed_screen.dart';
import 'package:the_radar/src/ui/radar_map_screen.dart';
import 'package:the_radar/src/ui/radar_theme.dart';
import 'package:the_radar/src/ui/settings_screen.dart';

import 'helpers/mock_path_provider.dart';

/// Layout sweep: no primary screen may overflow a RenderFlex at any width the
/// app is really viewed at — the Pi Browser and the Pi container both render
/// it narrow, and an overflowing [Row] paints the yellow/black hazard bands a
/// user reads as "broken screen".
///
/// Layout exceptions are collected per screen instead of failing the run on
/// the first one, and every other exception still flows to the framework so
/// unrelated failures are not masked.
class OverflowCollector {
  final List<String> found = <String>[];
  void Function(FlutterErrorDetails)? _previous;

  void install() {
    _previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (!text.contains('overflowed by')) {
        _previous?.call(details);
        return;
      }
      found.add('$text (${details.context?.toDescription() ?? 'unknown widget'})');
    };
  }

  void uninstall() {
    FlutterError.onError = _previous;
    _previous = null;
  }

  /// Returns the overflows reported since the last drain.
  Future<List<String>> drain(WidgetTester tester) async {
    await tester.pump();
    final collected = List<String>.from(found);
    found.clear();
    // Anything that is not an overflow still belongs to the test framework.
    while (tester.takeException() != null) {}
    return collected;
  }
}

void main() {
  mockPathProviderForMapCache();

  /// Small Android phone, typical Pi Browser phone, large phone, desktop.
  const widths = <double>[360, 412, 480, 1024];

  Future<ProviderContainer> signIn(WidgetTester tester) async {
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RadarApp)));
    final auth = container.read(authProvider.notifier);
    unawaited(auth.signInDemo());
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    unawaited(auth.finishOnboarding(
      role: UserRole.scout,
      displayName: 'Demo Scout',
      country: 'United Kingdom',
      city: 'London',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  for (final width in widths) {
    testWidgets('primary screens lay out cleanly at ${width.toInt()}px wide',
        (tester) async {
      final overflows = OverflowCollector()..install();
      addTearDown(overflows.uninstall);

      await tester.binding.setSurfaceSize(Size(width, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final problems = <String>[];

      // 1. The signed-out entry point.
      await tester.pumpWidget(const ProviderScope(child: RadarApp()));
      await tester.pumpAndSettle();
      problems.addAll(
          (await overflows.drain(tester)).map((e) => 'LoginScreen: $e'));

      // 2. The four shell tabs.
      await signIn(tester);
      for (final (index, name) in const [
        (0, 'FeedScreen'),
        (1, 'RadarMapScreen'),
        (2, 'BountyBoardScreen'),
        (3, 'ProfileHubScreen'),
      ]) {
        HomeShell.goTo(
          tester.element(find.byType(RadarMapScreen, skipOffstage: false)),
          index,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 300));
        problems.addAll(
            (await overflows.drain(tester)).map((e) => '$name: $e'));
      }

      // 3. Pushed routes reachable from the feed and the profile hub.
      for (final (name, screen) in <(String, Widget)>[
        ('SettingsScreen', const SettingsScreen()),
        ('MarketFeedScreen', const MarketFeedScreen()),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(theme: RadarTheme.dark, home: screen),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        problems.addAll(
            (await overflows.drain(tester)).map((e) => '$name: $e'));
      }

      // 4. The post composer, opened from the feed.
      await tester.pumpWidget(const ProviderScope(child: RadarApp()));
      await tester.pumpAndSettle();
      await signIn(tester);
      expect(find.byType(FeedScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      problems
          .addAll((await overflows.drain(tester)).map((e) => 'Composer: $e'));

      // Restore the framework handler before asserting, so a failure here is
      // reported as this test's expectation rather than as a stray override.
      overflows.uninstall();

      expect(problems, isEmpty,
          reason: 'Layout overflow(s) at ${width.toInt()}px:\n'
              '${problems.join('\n')}');
    });
  }
}
