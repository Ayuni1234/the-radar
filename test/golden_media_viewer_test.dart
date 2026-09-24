import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/ui/media_viewer.dart';
import 'package:the_radar/src/ui/radar_theme.dart';
import 'package:the_radar/src/ui/social_post_card.dart';

// Golden-style captures for the full-screen media gallery and the
// refreshed device-video hero chrome:
//
//   1. media_video_hero.png    — video post card (poster hero + duration chip)
//   2. media_viewer_open.png   — viewer opened on a two-item gallery
//   3. media_viewer_midswipe.png — mid-drag frame with the neighbor preview
//
// Run:  flutter test test/golden_media_viewer_test.dart --name media
//       (add --update-goldens to (re)generate the PNGs)
//
// Tagged `golden-capture`: pixel goldens are OS/renderer-dependent, so
// these are excluded from CI and run only on the machine that
// regenerates the captures.
void main() {
  FeedPost photoPost() => FeedPost(
        id: 'g-photo',
        authorProfileId: 'a1',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'Match-winner from distance.',
        createdAt: DateTime(2026, 9, 24),
        mediaUrl: 'https://example.supabase.co/storage/v1/object/public/'
            'feed-media/u1/hero.jpg',
        mediaPlatform: 'device photo',
        mediaKind: 'device_photo',
      );

  FeedPost videoPost() => FeedPost(
        id: 'g-video',
        authorProfileId: 'a1',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'Top bins from the edge of the box.',
        createdAt: DateTime(2026, 9, 24),
        mediaUrl: 'https://example.supabase.co/storage/v1/object/public/'
            'feed-media/u1/clip.mp4',
        mediaPosterUrl: 'https://example.supabase.co/storage/v1/object/'
            'public/feed-media/u1/clip.mp4.jpg',
        mediaPlatform: 'device video · 1:12',
        mediaKind: 'device_video',
        mediaDurationSeconds: 72,
      );

  Future<void> pumpHarness(
    WidgetTester tester,
    FeedPost post, {
    bool withGallery = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(412, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: RadarTheme.dark,
        home: Scaffold(
          backgroundColor: RadarTheme.ink,
          body: SingleChildScrollView(
            child: SocialPostCard(
              post: post,
              galleryPosts: withGallery ? [post, photoPost()] : null,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'capture: device-video hero chrome',
    tags: ['golden-capture'],
    (tester) async {
      await pumpHarness(tester, videoPost());

      expect(find.text('Device video · 1:12'), findsOneWidget);
      await expectLater(
        find.byType(SocialPostCard),
        matchesGoldenFile('goldens/media_video_hero.png'),
      );
    },
  );

  testWidgets(
    'capture: media viewer opened on the gallery',
    tags: ['golden-capture'],
    (tester) async {
      await pumpHarness(tester, videoPost(), withGallery: true);

      await tester.tap(find.byType(Hero).first);
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);
      // Flush any pending paint so the capture reflects the settled tree.
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/media_viewer_open.png'),
      );
    },
  );

  testWidgets(
    'capture: media viewer mid-swipe shows the neighbor preview',
    tags: ['golden-capture'],
    (tester) async {
      await pumpHarness(tester, videoPost(), withGallery: true);

      await tester.tap(find.byType(Hero).first);
      await tester.pumpAndSettle();

      // Hold a horizontal drag half-way: the current item slides left
      // while the neighbor preview enters from the right. A single pump
      // renders the held frame — no settle, no snap-back.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(MediaViewer)));
      await gesture.moveBy(const Offset(-206, 0));
      await tester.pump();
      expect(find.text('1 / 2'), findsOneWidget,
          reason: 'the drag has not committed to the second item yet');

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/media_viewer_midswipe.png'),
      );
      // Release and let the page-settle animation finish so the test ends
      // with no pending timers.
      await gesture.up();
      await gesture.removePointer();
      await tester.pumpAndSettle();
    },
  );
}
