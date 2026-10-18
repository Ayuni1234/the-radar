import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/models/user_profile.dart';
import 'package:the_radar/src/state/auth_controller.dart'
    show AuthController, AuthSignedIn, AuthState, RadarSession, authProvider;
import 'package:the_radar/src/state/radar_providers.dart'
    show FeedPostsController, ProfilesController, feedPostsProvider, profilesProvider;
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
  Future<void> pumpReels(WidgetTester tester, {bool withProfile = false}) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuth.new),
        feedPostsProvider.overrideWith(_FixedFeedPosts.new),
        if (withProfile) profilesProvider.overrideWith(_FixedProfiles.new),
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

  testWidgets('the overlay is a compact strip over the lower edge of the reel',
      (tester) async {
    await pumpReels(tester, withProfile: true);

    final screen = tester.getSize(find.byType(FeedScreen));
    final caption = tester.getRect(find.text('Sprint day.'));
    final tags = tester.getRect(find.text('#TheRadar #Highlight'));
    final name = tester.getRect(find.text('Joung Pame'));
    final training = tester.getRect(find.byType(NextTrainingOverlayCard));
    final cta = tester.getRect(find.text('GO TO PROFILE'));
    final overlay = tester.getRect(find.byKey(const ValueKey('reel-overlay')));

    expect(tags.top, greaterThan(caption.bottom - 1),
        reason: 'the hashtag line sits under the caption');
    expect(name.top, greaterThan(tags.bottom),
        reason: 'the player row starts below the caption block');
    expect(cta.top, lessThan(name.bottom),
        reason: 'the CTA shares the player row instead of adding a line');
    expect(cta.bottom, greaterThan(name.top));
    expect(training.top, greaterThan(cta.bottom - 1),
        reason: 'the training strip sits under the player row');

    // The requirement this pins: the translucent info card (with the caption
    // line above it) must not eat the photo — it stays inside the bottom
    // fifth of the reel and hugs the lower edge.
    expect(overlay.height, lessThanOrEqualTo(screen.height * 0.20),
        reason: 'the overlay must cover no more than 20% of the media');
    expect(overlay.bottom, greaterThan(screen.height * 0.94));

    // The player is still identified, compactly: one meta line, KYC tick.
    expect(find.text('Age 24 · ST · LW'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget,
        reason: 'KYC players wear the verified tick next to their name');

    // The media still runs edge to edge behind it all.
    expect(tester.getRect(find.byType(PostMediaSurface).first).width,
        screen.width);
  });

  testWidgets('one header bar, pinned at the top, with a back control',
      (tester) async {
    await pumpReels(tester);

    final screen = tester.getSize(find.byType(FeedScreen));
    final bar = tester.getRect(find.byKey(const ValueKey('feed-top-bar')));
    expect(bar.top, lessThanOrEqualTo(2),
        reason: 'the header is the very top strip, under the status bar');
    expect(bar.bottom, lessThan(screen.height * 0.12));

    // Back, brand, bell, brightness, composer and the overflow menu.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('THE RADAR'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);

    // The header belongs to the screen, not to a post: paging the reel cannot
    // paint a second copy.
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.text('THE RADAR'),
      ),
      findsNothing,
    );
    await tester.drag(find.byType(PageView), const Offset(0, -400));
    await tester.pump();
    expect(find.text('THE RADAR'), findsOneWidget,
        reason: 'mid-swipe both reels are mounted; the bar must stay single');
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('back walks up the reel, then reports the start of the feed',
      (tester) async {
    await pumpReels(tester);

    await tester.fling(find.byType(PageView), const Offset(0, -700), 1200);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Top bins.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Sprint day.'), findsOneWidget,
        reason: 'back steps up to the previous reel');
    expect(find.text('Top bins.'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Already at the start of the feed.'), findsOneWidget,
        reason: 'at the top of the reel the back control says so instead of '
            'doing nothing');
  });

  testWidgets('the discovery body keeps the same single header bar',
      (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuth.new),
        feedPostsProvider.overrideWith(_EmptyFeedPosts.new),
      ],
      child: MaterialApp(theme: RadarTheme.dark, home: const FeedScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}

    // With nothing to page through, the tab falls back to the discovery body
    // — still under one top bar, not a second app bar of its own.
    final bar = tester.getRect(find.byKey(const ValueKey('feed-top-bar')));
    expect(bar.top, lessThanOrEqualTo(2));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('THE RADAR'), findsOneWidget);
    expect(find.byType(SliverAppBar), findsNothing);
    expect(find.text('Talent is everywhere.'), findsOneWidget);
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

/// One KYC-verified player profile, so the reel card renders the mockup's
/// "Age / Position / Bio" block instead of the bare author name.
class _FixedProfiles extends ProfilesController {
  @override
  Future<List<UserProfile>> build() async => [
        UserProfile(
          id: 'a1',
          piUid: 'pi-a1',
          username: 'jpame',
          displayName: 'Joung Pame',
          role: UserRole.player,
          credibilityScore: 62,
          kycVerified: true,
          createdAt: DateTime(2026, 1, 1),
          positions: const ['ST', 'LW'],
          birthYear: 2002,
          bio: 'Right foot forward, always on the shoulder of the last man.',
        ),
      ];
}

/// No posts at all — the tab's discovery body.
class _EmptyFeedPosts extends FeedPostsController {
  @override
  Future<List<FeedPost>> build() => Future.value(const <FeedPost>[]);
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
