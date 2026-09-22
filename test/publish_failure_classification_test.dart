import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:the_radar/src/data/media_upload_service.dart';
import 'package:the_radar/src/data/radar_repository.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/models/publish_outcome.dart';

/// The original bug: a server-side rejection during publish was classified
/// as a transport failure and mislabeled "offline — queued for sync".
/// These tests pin the classifier so rejections surface their real reason
/// and only genuine transport problems ever queue.
void main() {
  FeedPost draft(String id) => FeedPost(
        id: id,
        authorProfileId: 'author-1',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'Test post body',
        createdAt: DateTime(2026, 9, 22),
      );

  group('publish failure classification (no false offline errors)', () {
    test('PostgrestException → rejection with the real server reason',
        () {
      final outcome = RadarRepository.classifyFailure(const PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      ));

      expect(outcome.$1, isFalse, reason: 'RLS denial is NOT offline');
      expect(outcome.$2, contains('row-level security'));
      expect(outcome.$2, contains('sign in'),
          reason: 'message must include an actionable next step');
    });

    test('missing column (schema drift) → rejection, not offline', () {
      final outcome = RadarRepository.classifyFailure(const PostgrestException(
        message: "column feed_posts.author_id does not exist",
        code: '42703',
      ));

      expect(outcome.$1, isFalse);
      expect(outcome.$2, contains('does not exist'));
    });

    test('unique violation → rejection (replay path treats it as success)',
        () {
      final (retryable, message) = RadarRepository.classifyFailure(
          const PostgrestException(
              message: 'duplicate key value violates unique constraint',
              code: '23505'));

      expect(retryable, isFalse);
      expect(message, contains('duplicate key'));
    });

    test('socket errors → retryable with a clear queued-for-sync message', () {
      final (retryable, message) = RadarRepository.classifyFailure(
          const SocketException('Failed host lookup: supabase.co'));

      expect(retryable, isTrue);
      expect(message, contains('saved'));
      expect(message, contains('publish automatically'));
    });

    test('timeout → retryable (the 20s write deadline)', () {
      final (retryable, message) =
          RadarRepository.classifyFailure(TimeoutException(
              'request exceeded 20s', const Duration(seconds: 20)));

      expect(retryable, isTrue);
      expect(message, contains('saved'));
    });

    test('client exception (browser transport reset) → retryable', () {
      final (retryable, _) = RadarRepository.classifyFailure(
          ClientException('Connection closed while receiving data'));

      expect(retryable, isTrue);
    });

    test('unknown exception with no hints → rejection, never queued', () {
      // The historic mislabel: any error that MENTIONED nothing transporty
      // used to be treated as offline when its text matched no pattern —
      // the classifier must default to surfacing the reason instead.
      final (retryable, message) = RadarRepository.classifyFailure(
          Exception('something unexpected'));

      expect(retryable, isFalse);
      expect(message, isNotEmpty);
    });
  });

  group('PublishOutcome contract', () {
    test('queued outcomes carry the retry hint in their detail', () {
      final o = PublishOutcome.queued('server could not be reached');
      expect(o.queued, isTrue);
      expect(o.detail, contains('back online'));
    });

    test('rejected outcomes never claim to be queued', () {
      final o = PublishOutcome.rejected('real reason');
      expect(o.queued, isFalse);
      expect(o.detail, 'real reason');
    });
  });

  group('storage upload failure mapping (actionable messages)', () {
    test('offline upload (no status) → connection guidance, not raw dump',
        () {
      final msg = MediaUploadService.storageFailureMessage(
          const StorageException('Client is offline', statusCode: null),
          1024);

      expect(msg, contains('could not be reached'));
      expect(msg, contains('connection'));
      expect(msg, isNot(contains('null')));
    });

    test('413 payload too large → size guidance', () {
      final msg = MediaUploadService.storageFailureMessage(
          const StorageException('Payload too large', statusCode: '413'),
          12 * 1024 * 1024);

      expect(msg, contains('too large'));
      expect(msg, contains('MB'));
    });

    test('403 storage rules denial → session-expiry guidance', () {
      final msg = MediaUploadService.storageFailureMessage(
          const StorageException('new row violates row level security',
              statusCode: '403'),
          1024);

      expect(msg, contains('session may have expired'));
    });

    test('409 duplicate object name → retry guidance', () {
      final msg = MediaUploadService.storageFailureMessage(
          const StorageException('The resource already exists',
              statusCode: '409'),
          1024);

      expect(msg, contains('already exists'));
    });

    test('unknown status → surfaces status and server message', () {
      final msg = MediaUploadService.storageFailureMessage(
          const StorageException('Bucket not found', statusCode: '404'),
          1024);

      expect(msg, contains('404'));
      expect(msg, contains('Bucket not found'));
    });
  });

  group('idempotent outbox replay ids', () {
    test('client draft ids map to stable uuid replay ids', () {
      final id = RadarRepository.pendingReplayId(draft('post-1726950000123456'));
      // The replay upsert targets a uuid PK column — a non-uuid id would
      // be rejected (22P02) and the outbox would never clear.
      expect(RadarRepository.isValidUuid(id), isTrue, reason: id);
      // Stability matters: two replays must collide on the same row.
      expect(
        RadarRepository.pendingReplayId(draft('post-1726950000123456')),
        id,
      );
    });

    test('different drafts map to different pending ids', () {
      expect(
        RadarRepository.pendingReplayId(draft('post-111')),
        isNot(RadarRepository.pendingReplayId(draft('post-222'))),
      );
    });
  });
}
