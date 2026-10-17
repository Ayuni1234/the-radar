import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/state/auth_controller.dart'
    show AuthController, AuthSignedIn, AuthState, RadarSession, authProvider;
import 'package:the_radar/src/state/radar_providers.dart'
    show FeedPostsController, feedPostsProvider;
import 'package:the_radar/src/ui/feed_screen.dart';
import 'package:the_radar/src/ui/next_training_overlay.dart';
import 'package:the_radar/src/ui/radar_theme.dart';
import 'package:the_radar/src/ui/social_post_card.dart';

/// The Reels tab is a full-bleed vertical reel: the post's media runs edge to
/// edge behind a floating header (brand + 𝛑 balance) and an overlay card
/// carrying the caption, hashtag pills, the posting player and the live
/// training CTA. These are the mockup's defining elements, so they are pinned
/// against the layout regressing back into a boxed scrolling feed.
void main() {
  Future<void> pumpReels(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuth.new),
        feedPostsProvider.overrideWith(_FixedFeedPosts.new),
      ],
      child: MaterialApp(theme: RadarTheme.dark, home: const FeedScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}
  }

  testWidgets('reels page is a full-bleed reel with the mockup overlay',
      (tester) async {
    await pumpReels(tester);

    final screen = tester.getSize(find.byType(FeedScreen));
    final media = tester.getRect(find.byType(PostMediaSurface).first);

    // Edge to edge: the media covers the whole reels surface.
    expect(media.width, screen.width);
    expect(media.height, screen.height);

    // Header: the brand sits in the top strip, over the media.
    final brand = tester.getRect(find.text('THE RADAR'));
    expect(brand.top, lessThan(screen.height * 0.12),
        reason: 'the brand header floats over the top of the reel');
    expect(brand.left, lessThan(screen.width / 2));

    // Overlay card: caption, hashtags, the posting player and the live
    // training block, all in the lower half of the reel.
    final caption = tester.getRect(find.text('Sprint day.'));
    expect(caption.top, greaterThan(screen.height * 0.5),
        reason: 'the caption belongs to the bottom overlay card');

    final hashtag = find.textContaining('#');
    expect(hashtag, findsWidgets,
        reason: 'hashtag pills are part of the reel overlay');
    final hashtagRect = tester.getRect(hashtag.first);
    expect(hashtagRect.top, greaterThan(caption.top));

    expect(find.text('Scout'), findsWidgets,
        reason: 'the posting player is named on the reel');
    expect(find.byType(NextTrainingOverlayCard), findsOneWidget);
    expect(find.text('GO TO PROFILE'), findsOneWidget);

    // Vertical paging: the second post is one reel below the first.
    await tester.drag(find.byType(PageView), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}
    expect(find.text('Top bins.'), findsOneWidget);
  });

  testWidgets('the reels header keeps the composer and the discovery tools',
      (tester) async {
    await pumpReels(tester);

    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget,
        reason: 'the overflow menu keeps the discovery tools on the reels tab');

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}
    expect(find.text('New post'), findsOneWidget);
  });

  for (final height in const [600.0, 520.0, 460.0]) {
    testWidgets('the reel overlay fits a ${height.toInt()}px-tall viewport',
        (tester) async {
      tester.view.physicalSize = Size(412, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FixedAuth.new),
          feedPostsProvider.overrideWith(_FixedFeedPosts.new),
        ],
        child: MaterialApp(theme: RadarTheme.dark, home: const FeedScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final problems = <String>[];
      while (true) {
        final error = tester.takeException();
        if (error == null) break;
        problems.add(error.toString());
      }
      final overflows =
          problems.where((p) => p.contains('overflowed by')).toList();
      expect(overflows, isEmpty,
          reason: 'short-viewport reel overflow:\n${overflows.join('\n')}');
    });
  }
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

/// A two-post reel: one photo, one device video with a poster frame.
class _FixedFeedPosts extends FeedPostsController {
  @override
  Future<List<FeedPost>> build() => Future.value([
        FeedPost(
          id: 'f1',
          authorProfileId: 'a1',
          authorName: 'Scout',
          authorRole: 'player',
          kind: FeedPostKind.highlight,
          body: 'Sprint day.',
          createdAt: DateTime(2026, 10, 17),
          areaName: 'Camden',
          mediaUrl: 'https://example.supabase.co/storage/v1/object/public/'
              'feed-media/u1/1.jpg',
          mediaPlatform: 'device photo',
          mediaKind: 'device_photo',
        ),
        FeedPost(
          id: 'f2',
          authorProfileId: 'a1',
          authorName: 'Scout',
          authorRole: 'player',
          kind: FeedPostKind.drill,
          body: 'Top bins.',
          createdAt: DateTime(2026, 10, 17),
          mediaUrl: 'https://example.supabase.co/storage/v1/object/public/'
              'feed-media/u1/2.mp4',
          mediaPosterUrl: 'https://example.supabase.co/storage/v1/object/'
              'public/feed-media/u1/2.mp4.jpg',
          mediaPlatform: 'device video · 1:12',
          mediaKind: 'device_video',
          mediaDurationSeconds: 72,
        ),
      ]);
}
