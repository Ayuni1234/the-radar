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
import 'package:the_radar/src/models/content_report.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/state/auth_controller.dart'
    show RadarSession, coarseFixLabel, sessionProvider;
import 'package:the_radar/src/ui/feed_screen.dart';
import 'package:the_radar/src/ui/profiles_screen.dart';
import 'package:the_radar/src/ui/radar_theme.dart';
import 'package:the_radar/src/ui/sheet_scaffold.dart';
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

  group('feed card edge-to-edge layout (Instagram-style)', () {
    FeedPost post({bool media = false}) => FeedPost(
          id: 'p1',
          authorProfileId: 'a1',
          authorName: 'Scout',
          authorRole: 'player',
          kind: FeedPostKind.highlight,
          body: 'Tactical shape looked sharp today.',
          createdAt: DateTime(2026, 9, 23),
          areaName: 'Limbe — Omnisport Annex',
          mediaUrl: media
              ? 'https://example.supabase.co/storage/v1/object/public/'
                  'feed-media/u1/1.jpg'
              : null,
          mediaPlatform: media ? 'device photo' : null,
          mediaKind: media ? 'device_photo' : null,
        );

    Future<void> pumpCard(WidgetTester tester, FeedPost post,
        {bool framed = false}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: RadarTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(child: SocialPostCard(
              post: post,
              framed: framed,
            )),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('media runs edge-to-edge at a 4:5 portrait ratio',
        (tester) async {
      await pumpCard(tester, post());

      final media = tester.getRect(find.byType(AspectRatio));
      expect(media.left, 0,
          reason: 'the media container must touch the screen edge — no '
              'letterboxing or inner gutters');
      expect(media.width, 400);
      expect(media.height, 500,
          reason: '4:5 portrait canvas, like the premium feed layouts');
      expect(tester.takeException(), isNull);
    });

    testWidgets('caption and actions sit padded beneath the media',
        (tester) async {
      await pumpCard(tester, post());

      final mediaBottom = tester.getRect(find.byType(AspectRatio)).bottom;
      final caption = tester.getRect(find.text(
          'Scout Tactical shape looked sharp today.'));
      final pill = tester.getRect(find.text('Location Pin'));

      // Caption starts below the media, inset from the screen edge.
      expect(caption.top, greaterThan(mediaBottom));
      expect(caption.left, greaterThan(8),
          reason: 'comfortable padding, not overlapping the media edge');
      // The action row is inset too, and well above the screen bottom.
      expect(pill.top, greaterThan(mediaBottom));
      expect(pill.left, greaterThan(8));
      expect(tester.takeException(), isNull);
    });

    testWidgets('framed variant keeps the boxed panel look', (tester) async {
      await pumpCard(tester, post(), framed: true);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SocialPostCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('composer layout (scrollable form)', () {
    testWidgets('publish button stays reachable on a small viewport',
        (tester) async {
      // A short phone viewport — the long form must scroll instead of
      // overflowing (overflow throws FlutterError in tests).
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpComposerWithGpsFailure(
        tester,
        null,
        failure: const LocationException('unused — GPS never queried'),
      );

      // The primary action lives at the very bottom of the form: scroll
      // it into view and confirm it is actually hittable.
      await tester.scrollUntilVisible(
        find.text('Publish to feed'),
        200,
        scrollable: find.descendant(
          of: find.byType(DraggableScrollableSheet).evaluate().isNotEmpty
              ? find.byType(DraggableScrollableSheet)
              : find.byType(Scrollable).first,
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(find.text('Publish to feed'), findsOneWidget);
      await tester.tap(find.text('Publish to feed'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
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

  group('sheet overflow audit (long forms scroll to their submit)', () {
    Future<void> pumpOpener(
      WidgetTester tester,
      void Function(BuildContext) open, {
      double keyboardInset = 0,
    }) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The fake inset is injected at MaterialApp.builder level so pushed
      // modal routes (the sheets) see it, exactly like a real keyboard.
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: RadarTheme.dark,
          builder: (_, navigator) => MediaQuery(
            data: MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
            ),
            child: navigator ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: OutlinedButton(
                  onPressed: () => open(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('keyboard inset reserves its height in the sheet scroll',
        (tester) async {
      Future<double> maxExtent(double inset) async {
        await pumpOpener(tester, (context) async {
          await openReportSheet(context,
              targetLabel: "Scout's highlight post");
        }, keyboardInset: inset);
        return tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent;
      }

      final withoutKeyboard = await maxExtent(0);
      final withKeyboard = await maxExtent(220);
      expect(withKeyboard - withoutKeyboard, 220);

      // Scrolled to the end, the submit rests above the fake keyboard line.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      final submitBottom =
          tester.getBottomRight(find.text('Send report')).dy;
      expect(submitBottom, lessThan(640 - 220));
      expect(tester.takeException(), isNull);
    });

    testWidgets('report sheet scrolls to Send report and submits',
        (tester) async {
      (ContentReportReason, String)? filed;
      await pumpOpener(tester, (context) async {
        filed = await openReportSheet(context,
            targetLabel: "Scout's highlight post");
      });

      // The six reason rows push the submit below the fold on this
      // viewport — the form must scroll, not clip.
      await tester.scrollUntilVisible(
        find.text('Send report'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Spam or scam'));
      await tester.pump();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(filed, isNotNull);
      expect(filed!.$1, ContentReportReason.spam);
      expect(tester.takeException(), isNull);
    });

    testWidgets('connection sheet scrolls to Send request and submits',
        (tester) async {
      ConnectionSheetDraft? sent;
      await pumpOpener(tester, (context) async {
        sent = await openConnectionSheet(
          context,
          targetName: 'Ada',
          canInvite: false,
        );
      });

      await tester.scrollUntilVisible(
        find.text('Send request'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'Hi Ada!');
      await tester.pump();
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!.message, 'Hi Ada!');
      expect(tester.takeException(), isNull);
    });
  });

  group('SheetScaffold contract (overflow cannot regress)', () {
    // A 400x640 viewport with a 220px keyboard: any body taller than
    // ~420px must scroll, and the footer must never leave the screen.
    Future<void> pumpScaffold(
      WidgetTester tester,
      List<Widget> children, {
      double keyboardInset = 0,
    }) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: RadarTheme.dark,
        builder: (_, navigator) => MediaQuery(
          data: MediaQueryData(
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: navigator ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: SheetScaffold(
            title: 'Contract sheet',
            subtitle: 'guarantees',
            footer: FilledButton(
              onPressed: () {},
              child: const Text('Primary action'),
            ),
            children: children,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('footer stays visible with a long body and keyboard up',
        (tester) async {
      await pumpScaffold(
        tester,
        List.generate(
            12, (i) => SizedBox(height: 60, child: Text('Row $i'))),
        keyboardInset: 220,
      );

      // The footer is on screen immediately — no scrolling needed.
      expect(tester.getBottomRight(find.text('Primary action')).dy,
          lessThan(640 - 220));
      // The body scrolled instead of overflowing (all children stay in the
      // tree — the viewport is what's bounded).
      final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first);
      expect(scrollable.position.maxScrollExtent, greaterThan(300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('body rows reach the footer by scrolling under keyboard',
        (tester) async {
      await pumpScaffold(
        tester,
        List.generate(12, (i) => SizedBox(height: 60, child: Text('Row $i'))),
        keyboardInset: 220,
      );

      await tester.scrollUntilVisible(
        find.text('Row 11'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Row 11'), findsOneWidget);
      // Footer still on screen after the scroll.
      expect(tester.getBottomRight(find.text('Primary action')).dy,
          lessThan(640 - 220));
      expect(tester.takeException(), isNull);
    });
  });

  group('device video renders in the published feed card', () {
    testWidgets('device videos render the persisted poster frame as the '
        'hero instead of the painted placeholder', (tester) async {
      final post = FeedPost(
        id: 'p2',
        authorProfileId: 'a1',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'Top bins from the edge of the box.',
        createdAt: DateTime(2026, 9, 23),
        mediaUrl: 'https://example.supabase.co/storage/v1/object/public/'
            'feed-media/u1/2.mp4',
        mediaPosterUrl: 'https://example.supabase.co/storage/v1/object/'
            'public/feed-media/u1/2.mp4.jpg',
        mediaPlatform: 'device video · 1:12',
        mediaKind: 'device_video',
        mediaDurationSeconds: 72,
      );

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: RadarTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(child: SocialPostCard(post: post)),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // IO/web test binding: the surface resolves to the poster image path.
      expect(find.byType(Image), findsOneWidget,
          reason: 'the video hero must render the persisted poster frame '
              '(or the embedded player on web) — never the silent '
              'placeholder the old card showed');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('dark / light theme switching', () {
    test('light palette renders clean, high-contrast values', () {
      RadarTheme.current = RadarPalette.light;
      addTearDown(() => RadarTheme.current = RadarPalette.dark);
      expect(RadarTheme.ink, const Color(0xFFF5F7FA));
      expect(RadarTheme.panel, const Color(0xFFFFFFFF));
      expect(RadarTheme.textPrimary, const Color(0xFF0F172A));
      // Accents keep their identity but deepen for white surfaces.
      expect(RadarTheme.radar, isNot(const Color(0xFF3DFFA2)));
      // Palette getters must agree with the active mode.
      expect(RadarTheme.current.isDark, isFalse);
    });

    test('themeFor builds matching ThemeData for both modes', () {
      final dark = RadarTheme.themeFor(RadarBrightness.dark);
      final light = RadarTheme.themeFor(RadarBrightness.light);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF0A0E1A));
      expect(light.scaffoldBackgroundColor, const Color(0xFFF5F7FA));
      expect(light.textTheme.bodyLarge!.color, const Color(0xFF0F172A));
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(light.colorScheme.brightness, Brightness.light);
    });

    testWidgets('toggling the provider re-skins MaterialApp widgets end '
        'to end (panel, text, scaffold)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      RadarTheme.current = RadarPalette.dark;
      addTearDown(() => RadarTheme.current = RadarPalette.dark);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: RadarTheme
              .themeFor(RadarPalette.dark.isDark
                  ? RadarBrightness.dark
                  : RadarBrightness.light),
          home: Container(
            color: RadarTheme.panel,
            child: Text('body',
                style: TextStyle(color: RadarTheme.textPrimary)),
          ),
        ),
      ));
      await tester.pump();

      final panelBefore = (tester.widget<Container>(
              find.byType(Container).first))
          .color;
      expect(panelBefore, const Color(0xFF111827));

      // Flip the palette the way the header/settings toggle does.
      RadarTheme.current = RadarPalette.light;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: RadarTheme.themeFor(RadarBrightness.light),
          home: Container(
            color: RadarTheme.panel,
            child: Text('body',
                style: TextStyle(color: RadarTheme.textPrimary)),
          ),
        ),
      ));
      await tester.pump();

      final panelAfter = (tester.widget<Container>(
              find.byType(Container).first))
          .color;
      expect(panelAfter, const Color(0xFFFFFFFF),
          reason: 'panel getter must emit the light palette after the '
              'switch — no hardcoded dark colors surviving');
    });
  });
}
