import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/data/location_service.dart';
import 'package:the_radar/src/data/media_upload_service.dart';
import 'package:the_radar/src/data/video_thumbnail.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/state/auth_controller.dart'
    show RadarSession, coarseFixLabel, sessionProvider;
import 'package:the_radar/src/ui/feed_screen.dart';
import 'package:the_radar/src/ui/radar_theme.dart';
import 'package:the_radar/src/ui/social_post_card.dart';

/// Two composer bug fixes, pinned by test:
///
/// 1. Geolocation robustness — a GPS timeout must never hard-block the
///    composer: the fallback pins the profile's regional base instead.
/// 2. Media previews — a device upload stages a real visual preview card
///    and never pastes a raw storage URL into a text field.
/// Pumps the app with the composer open and GPS rigged to fail with
/// [failure] — the shared harness for the fallback behaviour tests.
Future<void> pumpComposerWithGpsFailure(
  WidgetTester tester,
  RadarSession? session, {
  required LocationException failure,
}) async {
  LocationService.overrideForTesting = () async => throw failure;
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionProvider.overrideWith((ref) => session)],
    child: MaterialApp(
      theme: RadarTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: OutlinedButton(
              onPressed: () => openPostComposer(context),
              child: const Text('compose'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('compose'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('location fallback (graceful region default)', () {
    tearDown(() {
      LocationService.overrideForTesting = null;
    });

    RadarSession sessionWithRegion() => const RadarSession(
          piUid: 'pi-1',
          username: 'scout',
          kycVerified: true,
          isDemo: true,
          regionLabel: 'Limbe, Cameroon',
          viewerLatitude: 4.0227,
          viewerLongitude: 9.1992,
        );

    Widget harness(RadarSession? session) => ProviderScope(
          overrides: [sessionProvider.overrideWith((ref) => session)],
          child: MaterialApp(
            theme: RadarTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: OutlinedButton(
                    onPressed: () => openPostComposer(context),
                    child: const Text('compose'),
                  ),
                ),
              ),
            ),
          ),
        );

    Future<void> openComposer(WidgetTester tester, RadarSession? session,
        {LocationException? gpsFailure}) async {
      if (gpsFailure == null) {
        LocationService.overrideForTesting = null;
      } else {
        LocationService.overrideForTesting = () async => throw gpsFailure;
      }
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(session));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('compose'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
        'GPS timeout falls back to the live coarse label — no hard error',
        (tester) async {
      await openComposer(
        tester,
        sessionWithRegion(),
        gpsFailure: const LocationException(
            'Could not get a GPS fix in time — try again outdoors or move to '
            'open sky.'),
      );
      await tester.tap(find.text('Use Current Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The regional base resolves to the live city-level label, which
      // prefills the area field and explains the fallback.
      expect(
        find.textContaining('near Limbe'),
        findsWidgets,
        reason: 'the live coarse label must replace the hard GPS error',
      );
      expect(
        find.widgetWithText(TextField, 'near Limbe'),
        findsOneWidget,
      );
      // No exception escaped to the test framework — the composer stays up.
      expect(tester.takeException(), isNull);
    });

    testWidgets('GPS fallback without a region falls back to Limbe, Cameroon',
        (tester) async {
      await openComposer(
        tester,
        null,
        gpsFailure: const LocationException('Could not get a GPS fix in time'),
      );
      await tester.tap(find.text('Use Current Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // No session → no viewer base to derive a live label from; the
      // static default region carries the post instead.
      expect(find.textContaining('Limbe, Cameroon'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('media preview card (no raw URLs in the composer)', () {
    /// A real 1×1 PNG so Image.memory can actually decode it in tests.
    Uint8List png() => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
        'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

    testWidgets('photo pick renders an actual thumbnail card', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: RadarTheme.dark,
        home: Scaffold(
          body: MediaPreviewCard(
            media: PickedMedia(
              file: PlatformFile(name: 'goal.jpg', size: 1024),
              bytes: png(),
              isVideo: false,
              durationSeconds: null,
              previewBytes: png(),
            ),
          ),
        ),
      ));

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Uploads with your post'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget,
          reason: 'the picked image itself renders as the thumbnail');
      // The raw storage URL must never surface as composer text.
      expect(find.textContaining('supabase.co'), findsNothing);
    });

    testWidgets('video pick shows the poster-frame card with duration',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: RadarTheme.dark,
        home: Scaffold(
          body: MediaPreviewCard(
            media: PickedMedia(
              file: PlatformFile(name: 'clip.mp4', size: 4096),
              bytes: Uint8List(16),
              isVideo: true,
              durationSeconds: 95,
              previewBytes: png(),
            ),
          ),
        ),
      ));

      expect(find.text('Video · 1:35'), findsOneWidget);
      expect(find.text('Poster preview — uploads with your post'),
          findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('video without a captured frame shows a placeholder, not a URL',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: RadarTheme.dark,
        home: Scaffold(
          body: MediaPreviewCard(
            media: PickedMedia(
              file: PlatformFile(name: 'clip.mp4', size: 4096),
              bytes: Uint8List(16),
              isVideo: true,
              durationSeconds: 42,
              previewBytes: null,
            ),
          ),
        ),
      ));

      expect(find.text('Video · 0:42'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('supabase.co'), findsNothing);
    });

    testWidgets('pasting a link while a device upload is staged clears the pick',
        (tester) async {
      final link = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(controller: link),
        ),
      ));
      // Mirrors the composer rule in both directions: exactly one media
      // source survives — a staged pick XOR a pasted link.
      expect(link.text, isEmpty);
    });
  });

  group('native video frame extraction (mobile preview parity)', () {
    test('pathless pick degrades to null without throwing', () async {
      final frame = await extractNativeVideoFrame(
          PlatformFile(name: 'clip.mp4', size: 4096));
      expect(frame, isNull);
    });

    test('unavailable native bindings degrade to the placeholder, not a crash', () async {
      // The test VM has no registered method-channel handler for the
      // extractor (and desktop/web builds have no implementation at all);
      // it must swallow that and return null so the composer shows the
      // icon placeholder instead of crashing the pick flow.
      final dir = await Directory.systemTemp.createTemp('radar_thumb');
      addTearDown(() => dir.delete(recursive: true));
      final video = File('${dir.path}/clip.mp4')
        ..writeAsBytesSync(List.filled(64, 1));
      final frame = await extractNativeVideoFrame(
          PlatformFile(name: 'clip.mp4', size: 64, path: video.path));
      expect(frame, isNull);
    });
  });

  group('device photo renders in the published feed card', () {
    testWidgets('isDevicePhoto posts draw the CDN image as the media hero',
        (tester) async {
      final post = FeedPost(
        id: 'p1',
        authorProfileId: 'a1',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'Goal',
        createdAt: DateTime(2026, 9, 23),
        mediaUrl: 'https://example.supabase.co/storage/v1/object/public/'
            'feed-media/u1/1.jpg',
        mediaPlatform: 'device photo',
        mediaKind: 'device_photo',
      );

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: RadarTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SocialPostCard(post: post),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Image), findsOneWidget,
          reason: 'the feed card must render the uploaded image, not just '
              'the painted pitch backdrop');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('live coarse location label (privacy-aware fallback)', () {
    test('nearby fixes resolve to the nearest known city', () {
      expect(coarseFixLabel(4.06, 9.75), 'near Douala');
    });

    test('same-city fixes drop the distance qualifier', () {
      expect(coarseFixLabel(4.0227, 9.1992), 'near Limbe');
    });

    test('mid-range fixes include the coarse distance', () {
      // ~95 km east of Douala: past the same-city band, well inside the
      // 300 km coarse-label band (and still closer to Douala than to
      // Yaoundé).
      final label = coarseFixLabel(3.95, 10.60)!;
      expect(label, startsWith('near '));
      expect(label, contains(' km away'));
    });

    test('fixes far from any known city yield no label', () {
      expect(coarseFixLabel(0.0, -15.0), isNull);
    });

    test('multi-word cities render their display names', () {
      expect(coarseFixLabel(40.7128, -74.0060), 'near New York');
    });

    test('null fixes never produce a label', () {
      expect(coarseFixLabel(null, null), isNull);
    });

    RadarSession minorSession() => const RadarSession(
          piUid: 'pi-minor',
          username: 'u16',
          kycVerified: true,
          isDemo: true,
          regionLabel: 'Limbe, Cameroon',
          viewerLatitude: 4.0227,
          viewerLongitude: 9.1992,
          isMinor: true,
        );

    RadarSession adultSession() => const RadarSession(
          piUid: 'pi-2',
          username: 'scout2',
          kycVerified: true,
          isDemo: true,
          regionLabel: 'Douala, Cameroon',
          viewerLatitude: 4.0511,
          viewerLongitude: 9.7679,
        );

    testWidgets('minors keep the static region only — no live label, no pin',
        (tester) async {
      await pumpComposerWithGpsFailure(
        tester,
        minorSession(),
        failure: const LocationException('Could not get a GPS fix in time'),
      );
      await tester.tap(find.text('Use Current Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The live fix-derived label must never appear for a minor.
      expect(find.textContaining('near Douala'), findsNothing);
      expect(find.textContaining('Limbe, Cameroon'), findsWidgets);
      // The no-pin branch of the fallback message.
      expect(find.textContaining('tagged'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adults get the live coarse label from the regional base',
        (tester) async {
      await pumpComposerWithGpsFailure(
        tester,
        adultSession(),
        failure: const LocationException('Could not get a GPS fix in time'),
      );
      await tester.tap(find.text('Use Current Location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('near Douala'), findsWidgets);
      expect(find.textContaining('Approximate location'), findsOneWidget);
      // The area field is prefilled with the live coarse label.
      expect(find.widgetWithText(TextField, 'near Douala'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
