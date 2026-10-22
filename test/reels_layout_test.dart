import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/models/user_profile.dart';
import 'package:the_radar/src/state/auth_controller.dart'
    show AuthController, AuthSignedIn, AuthState, RadarSession, authProvider;
import 'package:the_radar/src/state/map_focus.dart';
import 'package:the_radar/src/state/radar_providers.dart'
    show FeedPostsController, ProfilesController, feedPostsProvider, profilesProvider;
import 'package:the_radar/src/ui/feed_screen.dart';
import 'package:the_radar/src/ui/next_training_overlay.dart';
import 'package:the_radar/src/ui/radar_theme.dart';
import 'package:the_radar/src/ui/reel_view.dart';
import 'package:the_radar/src/ui/social_post_card.dart';

/// The Discover tab as drawn in the uploaded Reels spec: one brand top bar,
/// the scout-filter pill rail, then a full-bleed reel per page carrying the
/// player identity block, the LIVE SESSION INVITATION card and the action
/// rail. These are the design's defining elements, so they are pinned against
/// the layout drifting back into a boxed scrolling feed.
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

  testWidgets('the reel is full-bleed under the spec top bar and pill rail',
      (tester) async {
    await pumpReels(tester, withProfile: true);

    final screen = tester.getSize(find.byType(FeedScreen));
    final media = tester.getRect(find.byType(PostMediaSurface).first);

    // Edge to edge, and the media owns everything under the rail.
    expect(media.width, screen.width);
    expect(media.bottom, screen.height);
    expect(media.height, greaterThan(screen.height * 0.7));

    // The one branded bar, above the media: mark, wordmark, Pi balance chip.
    final bar = tester.getRect(find.byKey(const ValueKey('radar-top-bar')));
    expect(bar.top, lessThanOrEqualTo(2));
    expect(bar.bottom, lessThan(screen.height * 0.18));
    expect(find.text('THE RADAR'), findsOneWidget);
    expect(find.byKey(const ValueKey('pi-balance-chip')), findsOneWidget);

    // The scout-filter rail on the spec's five pills.
    for (final label in const ['ALL', 'U-17', 'STRIKERS']) {
      expect(find.text(label), findsOneWidget, reason: '$label pill');
    }
    await tester.drag(
        find.byKey(const ValueKey('discover-filter-0')), const Offset(-220, 0));
    await tester.pump();
    expect(find.textContaining('BOUNTIES'), findsWidgets,
        reason: 'the Bounties pill is the last stop on the rail');

    // Player identity block from the spec: condensed name, verified tick,
    // age / position pill, club line and caption.
    expect(find.text('JOUNG PAME'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsWidgets);
    expect(find.text('24 Y/O • ST / LW'), findsOneWidget);
    expect(find.textContaining('Right foot forward'), findsOneWidget);

    // The live invitation card with its countdown and dual CTAs.
    final invite = find.byType(NextTrainingOverlayCard);
    expect(invite, findsOneWidget);
    expect(find.byKey(const ValueKey('live-invitation-card')), findsOneWidget);
    expect(find.textContaining('LIVE SESSION'), findsOneWidget);
    expect(find.text('SCOUT IN PERSON'), findsOneWidget);
    expect(find.textContaining('BOUNTY'), findsOneWidget);

    // The card sits on the lower half of the frame, clear of the rail.
    final inviteRect = tester.getRect(invite);
    expect(inviteRect.top, greaterThan(screen.height * 0.4));

    // The right-hand action rail from the spec.
    expect(find.text('Scout'), findsWidgets);
    expect(find.byIcon(Icons.share), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('the pager plays the next reel on a swipe', (tester) async {
    await pumpReels(tester);
    expect(find.textContaining('Sprint day.'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}
    expect(find.textContaining('Top bins.'), findsOneWidget);
  });

  testWidgets('the invitation card deep-links to the player pin on the map',
      (tester) async {
    await pumpReels(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FeedScreen)));
    expect(container.read(mapFocusProvider), isNull);

    await tester.tap(find.byKey(const ValueKey('live-invitation-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    while (tester.takeException() != null) {}

    final focus = container.read(mapFocusProvider);
    expect(focus, isNotNull,
        reason: 'the card must hand a focus request to the Radar Map tab');
    expect(focus!.profileId, isNotEmpty,
        reason: 'the request names the hosting player');
    expect(focus.lat, isNotNull,
        reason: 'the request carries the pitch pin coordinates, so the map '
            'selects the exact pitch the invitation names');
    expect(focus.lon, isNotNull);
  });

  testWidgets('the filter rail narrows the reels to its scout filter',
      (tester) async {
    await pumpReels(tester, withProfile: true);
    expect(find.textContaining('Right foot forward'), findsOneWidget);

    // "Strikers" keeps the ST / LW player on screen...
    await tester.tap(find.byKey(const ValueKey('discover-filter-2')));
    await tester.pump();
    expect(find.text('JOUNG PAME'), findsOneWidget);

    // ...and an age bracket the profile falls outside of empties the reel out
    // into the discovery body instead of showing a blank page.
    await tester.tap(find.byKey(const ValueKey('discover-filter-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    while (tester.takeException() != null) {}
    expect(find.textContaining('Right foot forward'), findsNothing);
    expect(find.text('Talent is everywhere.'), findsOneWidget);
  });

  testWidgets('the discovery body keeps the same single top bar',
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

    final bar = tester.getRect(find.byKey(const ValueKey('radar-top-bar')));
    expect(bar.top, lessThanOrEqualTo(2));
    expect(find.text('THE RADAR'), findsOneWidget);
    expect(find.byType(SliverAppBar), findsNothing);
    expect(find.text('Talent is everywhere.'), findsOneWidget);
  });

  testWidgets('the one bar keeps the discovery tools behind its overflow menu',
      (tester) async {
    await pumpReels(tester);

    expect(find.text('THE RADAR'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget,
        reason: 'the overflow menu keeps the discovery tools on the tab');

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    while (tester.takeException() != null) {}
    expect(find.text('New post'), findsOneWidget);
    expect(find.text('Filter feed'), findsOneWidget);
    expect(find.text('Safeguarding centre'), findsOneWidget);
  });

  testWidgets('the single bar is not repainted inside the pager',
      (tester) async {
    await pumpReels(tester);

    await tester.drag(find.byType(PageView), const Offset(0, -200));
    await tester.pump();
    expect(find.text('THE RADAR'), findsOneWidget,
        reason: 'mid-swipe both reels are mounted; the bar must stay single');
  });

  for (final size in const [Size(412, 600), Size(412, 520), Size(412, 460), Size(320, 640), Size(320, 568)]) {
    testWidgets('the reel fits a ${size.width.toInt()}x${size.height.toInt()} viewport',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FixedAuth.new),
          feedPostsProvider.overrideWith(_FixedFeedPosts.new),
          profilesProvider.overrideWith(_FixedProfiles.new),
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

  test('the metric chips are a stable projection of the profile', () {
    final profile = UserProfile(
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
    );
    final chips = reelMetricChips(profile);
    expect(chips, reelMetricChips(profile),
        reason: 'the same player always reads the same scouting index');
    expect(chips.pac, inInclusiveRange(40, 99));
    expect(chips.topPct, inInclusiveRange(1, 25));
  });
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

/// One KYC-verified player profile, so the reel renders the spec's
/// "name / verified / age · position" identity block instead of a bare name.
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
