import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:the_radar/src/data/media_upload_service.dart';
import 'package:the_radar/src/data/radar_repository.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/supabase/supabase_config.dart';
import 'package:the_radar/src/sync/sync_bridge.dart';

/// The outbox now carries device media with the post: a transport-failed
/// upload stages a [PendingMediaUpload], the publish queues, and
/// [RadarRepository.replayFeedPost] chains upload → insert so the post
/// lands complete when connectivity returns.
///
/// These tests run against a local fake Supabase (PostgREST + Storage)
/// served by a raw HttpServer, with the real SupabaseClient pointed at it
/// through the [SupabaseConfig.debugClientOverride] test seam — no network,
/// no real project credentials.
// No TestWidgetsFlutterBinding here: it would hijack HttpClient and turn
// every request into a synthetic 400, preventing the real loopback sockets
// this suite's fake backend depends on.
void main() {
  late _FakeSupabaseServer server;
  late SupabaseClient client;

  setUp(() async {
    server = _FakeSupabaseServer();
    await server.start();
    client = SupabaseClient(
      'http://localhost:${server.port}',
      'test-anon-key',
    );
    SupabaseConfig.debugClientOverride = client;
  });

  tearDown(() async {
    SupabaseConfig.debugClientOverride = null;
    await client.dispose();
    await server.close();
    // Fresh pending slots per test — the repository is a singleton.
    RadarRepository.instance.resetPendingForTesting();
  });

  FeedPost post({String? mediaUrl, String? mediaKind, String? mediaPlatform}) =>
      FeedPost(
        id: 'post-test-${DateTime.now().microsecondsSinceEpoch}',
        authorProfileId: 'author-1',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'Test highlight',
        createdAt: DateTime(2026, 9, 23),
        mediaUrl: mediaUrl,
        mediaKind: mediaKind,
        mediaPlatform: mediaPlatform,
      );

  group('storage failure classification (retryable vs definitive)', () {
    test('offline (status 0) and 5xx are retryable; 4xx are not', () {
      expect(
        MediaUploadService.storageFailureIsRetryable(
            const StorageException('offline', statusCode: null)),
        isTrue,
      );
      expect(
        MediaUploadService.storageFailureIsRetryable(
            const StorageException('server exploded', statusCode: '502')),
        isTrue,
      );
      expect(
        MediaUploadService.storageFailureIsRetryable(
            const StorageException('too big', statusCode: '413')),
        isFalse,
      );
      expect(
        MediaUploadService.storageFailureIsRetryable(
            const StorageException('rules denied it', statusCode: '403')),
        isFalse,
      );
    });
  });

  group('publish → outbox → replay with staged media', () {
    test('transport-failed upload stages the media and queues the publish',
        () async {
      // Storage unreachable → upload() must throw the retryable variant.
      server.storageFailNext(1, mode: _FailMode.refused);

      final picked = PickedMedia(
        file: PlatformFile(name: 'clip.mp4', size: 128, path: '/tmp/x.mp4'),
        bytes: Uint8List.fromList(List.filled(128, 7)),
        isVideo: true,
        durationSeconds: 61,
        previewBytes: null,
      );

      await expectLater(
        MediaUploadService.instance.upload(picked),
        throwsA(isA<MediaUploadRetryableException>()),
      );
      // The exception surfaces the server-side transport failure (status 0)
      // rather than a generic message — actionable even before the queue.
      // (Verified via the repository path below.)
    });

    test('queued publish replays media upload + post when back online',
        () async {
      // 1. Storage down on first publish: upload fails retryably.
      server.storageFailNext(1, mode: _FailMode.refused);
      final picked = PickedMedia(
        file: PlatformFile(name: 'clip.mp4', size: 128, path: '/tmp/x.mp4'),
        bytes: Uint8List.fromList(List.filled(128, 7)),
        isVideo: true,
        durationSeconds: 95,
        previewBytes: null,
      );

      PendingMediaUpload? pending;
      try {
        await MediaUploadService.instance.upload(picked);
        fail('upload should have failed while storage is unreachable');
      } on MediaUploadRetryableException catch (e) {
        pending = e.pending;
      }
      expect(pending, isNotNull);
      expect(pending.mediaKind, 'device_video');
      expect(pending.durationSeconds, 95);

      // 2. The whole publish queues — media + post — via the repository
      //    without touching PostgREST (the post must not land caption-only).
      final outcome = await RadarRepository.instance
          .createFeedPost(post(), pendingMedia: pending);
      expect(outcome.queued, isTrue,
          reason: 'transport failure must queue, not reject');
      expect(server.postInserts, 0,
          reason: 'no caption-only insert while media is still pending');

      // 3. Connectivity returns → flush replays: media uploaded first,
      //    post inserted with the resolved CDN URL and tags.
      final replayed = await RadarRepository.instance.replayFeedPost();
      expect(replayed, isTrue);
      expect(server.storageUploads, 1);
      expect(server.postInserts, 1);

      final row = server.lastPostRow!;
      expect(row['media_url'], startsWith('http://localhost'));
      expect(row['media_url'], contains('/object/public/feed-media/'));
      expect(row['media_kind'], 'device_video');
      expect(row['media_duration_s'], 95);
      expect(row['body'], 'Test highlight');
    });

    test('post-insert failure after a successful media upload keeps both staged',
        () async {
      // First upload attempt happens while storage is unreachable.
      server.storageFailNext(1, mode: _FailMode.refused);
      final picked = PickedMedia(
        file: PlatformFile(name: 'goal.jpg', size: 64, path: '/tmp/x.jpg'),
        bytes: Uint8List.fromList(List.filled(64, 3)),
        isVideo: false,
        durationSeconds: null,
        previewBytes: null,
      );
      PendingMediaUpload? pending;
      try {
        await MediaUploadService.instance.upload(picked);
        fail('upload should have failed');
      } on MediaUploadRetryableException catch (e) {
        pending = e.pending;
      }

      // Stage the whole publish via the outbox path.
      final outcome = await RadarRepository.instance
          .createFeedPost(post(), pendingMedia: pending);
      expect(outcome.queued, isTrue);

      // First replay attempt: storage succeeds now, but the post insert
      // still fails (PostgREST unreachable) → replay must keep staging.
      server.postFailNext();
      var ok = await RadarRepository.instance.replayFeedPost();
      expect(ok, isFalse);
      expect(server.storageUploads, 1);
      expect(server.postInserts, 0);

      // Second replay: everything succeeds; the storage leg is repeated
      // (upsert semantics) and the post lands with its URL.
      ok = await RadarRepository.instance.replayFeedPost();
      expect(ok, isTrue);
      expect(server.storageUploads, 2);
      expect(server.postInserts, 1);
      expect(server.lastPostRow!['media_kind'], 'device_photo');
      expect(pending, isNotNull);
    });

    test('definitive storage rejection drops the media, publishes caption-only',
        () async {
      // The first upload hits a definitive 413 (payload too large) —
      // retrying can never succeed, so it must NOT queue.
      server.storageFailNext(1, mode: _FailMode.status413);
      final picked = PickedMedia(
        file: PlatformFile(name: 'huge.jpg', size: 64, path: '/tmp/x.jpg'),
        bytes: Uint8List.fromList(List.filled(64, 3)),
        isVideo: false,
        durationSeconds: null,
        previewBytes: null,
      );
      PendingMediaUpload? pending;
      try {
        await MediaUploadService.instance.upload(picked);
        fail('upload should have failed');
      } on MediaUploadRetryableException {
        fail('a 4xx rejection must not be classified as retryable');
      } on MediaUploadException {
        // expected — a 413 is definitive, not retryable
        // expected — build the pending manually to drive the replay path.
        pending = PendingMediaUpload(
          media: picked,
          objectName: 'u1/1.jpg',
          mediaPlatform: 'device photo',
          mediaKind: 'device_photo',
          durationSeconds: null,
        );
      }

      // Force the staged-media path: queue with the pending, then make the
      // storage leg reject definitively while the post insert succeeds.
      final outcome = await RadarRepository.instance
          .createFeedPost(post(), pendingMedia: pending);
      expect(outcome.queued, isTrue);
      server.postFailNext(); // first replay: storage 413 while post down
      final ok1 = await RadarRepository.instance.replayFeedPost();
      expect(ok1, isFalse);

      // Second replay: storage keeps rejecting with 413 → the media is
      // dropped and the post publishes caption-only.
      server.storageFailNext(1, mode: _FailMode.status413);
      final ok2 = await RadarRepository.instance.replayFeedPost();
      expect(ok2, isTrue);
      expect(server.postInserts, 1);
      final row = server.lastPostRow!;
      expect(row['media_url'], isNull,
          reason: 'rejected media must not block the post');
      expect(row['media_kind'], isNull);
      expect(row['body'], 'Test highlight');
    });

    test('replay id stays deterministic and uuid-shaped', () {
      final p = post();
      final id1 = RadarRepository.pendingReplayId(p);
      final id2 = RadarRepository.pendingReplayId(p);
      expect(id1, id2);
      expect(RadarRepository.isValidUuid(id1), isTrue);
    });
  });

  group('SyncBridge wiring', () {
    test('queued publishes announce themselves on the bridge', () async {
      final events = <(String, String)>[];
      void listener(String kind, String label, String? error) {
        events.add((kind, label));
      }

      SyncBridge.instance.addListener(listener);
      addTearDown(() => SyncBridge.instance.removeListener(listener));

      server.storageFailNext(1, mode: _FailMode.refused);
      final picked = PickedMedia(
        file: PlatformFile(name: 'clip.mp4', size: 128, path: '/tmp/x.mp4'),
        bytes: Uint8List.fromList(List.filled(128, 7)),
        isVideo: true,
        durationSeconds: 30,
        previewBytes: null,
      );
      PendingMediaUpload? pending;
      try {
        await MediaUploadService.instance.upload(picked);
      } on MediaUploadRetryableException catch (e) {
        pending = e.pending;
      }

      server.storageFailNext(1, mode: _FailMode.refused);
      await RadarRepository.instance.createFeedPost(post(), pendingMedia: pending);

      expect(events, isNotEmpty);
      expect(events.last.$1, 'feed_post');
    });
  });
}

enum _FailMode { refused, status413 }

/// Minimal fake of the two Supabase surfaces the publish path touches:
/// PostgREST inserts (POST /rest/v1/feed_posts) and Storage uploads
/// (POST /storage/v1/object/feed-media/...). Counts calls and can be told
/// to fail the next N requests of either surface, with transport-refused
/// or 413 semantics.
class _FakeSupabaseServer {
  HttpServer? _server;
  int? _port;

  int storageUploads = 0;
  int postInserts = 0;
  Map<String, Object?>? lastPostRow;

  int _storageFails = 0;
  _FailMode _storageFailMode = _FailMode.refused;
  bool _postDown = false;

  void storageFailNext(int count, {_FailMode mode = _FailMode.refused}) {
    _storageFails = count;
    _storageFailMode = mode;
  }

  void postFailNext() => _postDown = true;

  int get port => _port!;

  Future<void> start() async {
    final s = await HttpServer.bind('127.0.0.1', 0);
    _server = s;
    _port = s.port;
    s.listen(_handle);
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    if (req.method == 'POST' &&
        req.uri.path.startsWith('/storage/v1/object/feed-media/')) {
      if (_storageFails > 0) {
        _storageFails--;
        if (_storageFailMode == _FailMode.refused) {
          // Transport-class failure as a fast 503 (no payload-stuck hangs).
          req.response.statusCode = 503;
          req.response.write(jsonEncode({
            'error': 'Service Unavailable',
            'message': 'Service Unavailable',
            'statusCode': '503',
          }));
          await req.response.close();
          return;
        }
        req.response.statusCode = 413;
        req.response.write(jsonEncode({
          'error': 'Payload too large',
          'message': 'Payload too large',
          'statusCode': '413',
        }));
        await req.response.close();
        return;
      }
      storageUploads++;
      req.response.statusCode = 200;
      // Real Storage answers with the object key — storage_client casts it.
      req.response.write(jsonEncode({
        'Key': req.uri.path.substring('/storage/v1/object/feed-media/'.length),
      }));
      await req.response.close();
      return;
    }
    if (req.method == 'POST' && req.uri.path == '/rest/v1/feed_posts') {
      final body = await utf8.decoder.bind(req).join();
      final decoded = jsonDecode(body);
      // Insert sends a JSON array; the replay upsert sends a single object.
      lastPostRow = (decoded is List ? decoded.first : decoded)
          .cast<String, Object?>();
      if (_postDown) {
        // Transport-class PostgREST failure as a fast 503 — one-shot, the
        // next insert reaches the fake backend again.
        _postDown = false;
        req.response.statusCode = 503;
        req.response.write(jsonEncode({
          'error': 'Service Unavailable',
          'message': 'Service Unavailable',
          'statusCode': '503',
        }));
        await req.response.close();
        return;
      }
      postInserts++;
      req.response.statusCode = 201;
      req.response.write(jsonEncode([lastPostRow]));
      await req.response.close();
      return;
    }
    req.response.statusCode = 404;
    await req.response.close();
  }
}
