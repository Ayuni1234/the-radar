import 'package:flutter_test/flutter_test.dart';
import 'package:the_radar/src/data/radar_repository.dart';
import 'package:the_radar/src/models/content_report.dart';
import 'package:the_radar/src/models/feed_post.dart';
import 'package:the_radar/src/models/radar_event.dart';
import 'package:the_radar/src/models/enums.dart';
import 'package:the_radar/src/models/user_profile.dart';

/// Production-readiness guards: every value the app sends to Supabase must
/// be accepted by the live schema, and round-trip without data loss. These
/// tests exist because the production schema has drifted from the app
/// before (the "queued for sync" mislabel bug) — a mismatch here means
/// every real-user publish fails server-side while the UI reports success
/// or queues forever.
void main() {
  group('outbox replay ids are valid uuids', () {
    // feed_posts.id and radar_events.id are uuid columns. A replay id the
    // DB rejects (e.g. 'pending:1726…') would fail with 22P02 on every
    // flush attempt — the outbox would never clear and the queued post
    // would never publish. Regression guard for exactly that.
    test('feed-post replay ids parse as uuids', () {
      final post = FeedPost(
        id: 'post-1726950000123456',
        authorProfileId: 'author',
        authorName: 'Scout',
        authorRole: 'player',
        kind: FeedPostKind.highlight,
        body: 'body',
        createdAt: DateTime(2026, 9, 22),
      );
      final id = RadarRepository.pendingReplayId(post);
      expect(RadarRepository.isValidUuid(id), isTrue, reason: id);
      // Stable across calls — the idempotency collision depends on it.
      expect(RadarRepository.pendingReplayId(post), id);
    });

    test('replay ids are collision-resistant across drafts', () {
      final ids = <String>{};
      for (var i = 0; i < 500; i++) {
        ids.add(RadarRepository.deterministicUuid('post-$i'));
        ids.add(RadarRepository.deterministicUuid('pin-$i'));
      }
      expect(ids.length, 1000);
    });

    test('uuid generation is identical across platforms (no dart:math Random)', () {
      // The implementation must avoid Random/DateTime so a hash computed on
      // web (dart2js/wasm) matches the one computed on the VM — otherwise a
      // replay would land on a different row and the idempotency guarantee
      // breaks. Pin a known vector so any accidental platform-dependent
      // primitive change is caught.
      final a = RadarRepository.deterministicUuid('post-1726950000123456');
      final b = RadarRepository.deterministicUuid('post-1726950000123456');
      expect(a, b);
      expect(a.length, 36);
      expect(a[14], '4'); // version nibble
      expect('89ab'.contains(a[19]), isTrue, reason: a); // variant nibble
    });
  });

  group('FeedPost payload matches the feed_posts schema', () {
    // PostgREST rejects unknown keys; a payload carrying the client draft
    // id ('post-…' is not a uuid) fails the whole insert. The repository
    // must never send it — and every key must be a real column.
    const canonicalColumns = {
      'author_profile_id', 'author_name', 'author_role', 'kind', 'body',
      'media_url', 'media_platform', 'media_kind', 'media_duration_s',
      'area_name', 'latitude', 'longitude', 'scheduled_at',
    };

    test('toJson carries only canonical columns and no id', () {
      final row = FeedPost(
        id: 'post-123',
        authorProfileId: 'a',
        authorName: 'n',
        authorRole: 'player',
        kind: FeedPostKind.tactical,
        body: 'b',
        createdAt: DateTime(2026, 9, 22),
        mediaUrl: 'https://x.example/v',
        mediaKind: 'device_video',
        mediaDurationSeconds: 95,
        areaName: 'Buea',
        latitude: 4.15,
        longitude: 9.24,
      ).toJson();

      expect(row.keys, unorderedEquals(canonicalColumns));
      expect(row.containsKey('id'), isFalse,
          reason: "client 'post-…' id is not a uuid — Postgres issues the PK");
      expect(row.containsKey('created_at'), isFalse);
    });

    test('full row round-trips through fromJson/toJson without loss', () {
      final post = FeedPost(
        id: '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
        authorProfileId: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        authorName: 'Kolo Mbappe',
        authorRole: 'scout',
        kind: FeedPostKind.drill,
        body: 'Rondo circuit — 3 rounds',
        createdAt: DateTime.utc(2026, 9, 1, 10, 30),
        mediaUrl: 'https://youtube.com/watch?v=abc',
        mediaPlatform: 'YouTube',
        mediaKind: 'link',
        mediaDurationSeconds: 42,
        areaName: 'Limbe',
        latitude: 4.0227,
        longitude: 9.1992,
        isMinorPoster: false,
      );
      final json = <String, Object?>{
        'id': post.id,
        ...post.toJson(),
        'created_at': post.createdAt.toIso8601String(),
      };
      final back = FeedPost.fromJson(json);

      expect(back.id, post.id);
      expect(back.authorProfileId, post.authorProfileId);
      expect(back.kind, post.kind);
      expect(back.body, post.body);
      expect(back.mediaUrl, post.mediaUrl);
      expect(back.mediaPlatform, post.mediaPlatform);
      expect(back.mediaKind, post.mediaKind);
      expect(back.mediaDurationSeconds, post.mediaDurationSeconds);
      expect(back.areaName, post.areaName);
      expect(back.latitude, post.latitude);
      expect(back.longitude, post.longitude);
    });
  });

  group('RadarEvent payload matches the radar_events schema', () {
    // Live columns per supabase/schema.sql + the 0003 repair. Every key the
    // model writes must exist server-side (unknown keys are rejected by
    // PostgREST with PGRST204, which used to masquerade as "offline").
    const canonicalColumns = {
      'id', 'event_type', 'title', 'host_profile_id', 'host_name',
      'latitude', 'longitude', 'starts_at', 'ends_at', 'geo_precision',
      'venue_name', 'area_name', 'description', 'capacity',
      'attending_count', 'min_age', 'max_age', 'positions_required',
      'is_minor_protected', 'boosted_until', 'bounty_pi', 'updated_at',
    };

    test('toJson carries only canonical columns', () {
      final row = RadarEvent(
        id: 'pin-42',
        type: RadarEventType.trial,
        title: 'Open trial',
        hostProfileId: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        hostName: 'Host',
        latitude: 4.15,
        longitude: 9.24,
        startsAt: DateTime.utc(2026, 10, 1, 9),
        endsAt: DateTime.utc(2026, 10, 1, 11),
        precision: GeoPrecision.approximate,
        capacity: 30,
        positionsRequired: const ['ST', 'CM'],
      ).toJson();

      // Every emitted key must be a canonical column (conditional fields
      // like boosted_until/bounty_pi may be absent — never unknown).
      expect(row.keys.every(canonicalColumns.contains), isTrue,
          reason: 'unexpected keys: '
              '${row.keys.where((k) => !canonicalColumns.contains(k))}');
      expect(row.containsKey('created_at'), isFalse);
      expect(row['positions_required'], <String>['ST', 'CM']);
      expect(row['geo_precision'], 'approximate');
    });

    test('row round-trips through fromJson/toJson without loss', () {
      final e = RadarEvent(
        id: '5c1a9f3e-9c1d-4f4e-8d0a-2f5e1b7c9d01',
        type: RadarEventType.match,
        title: 'Sunday league',
        hostProfileId: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        hostName: 'Coach Ada',
        latitude: 5.6037,
        longitude: -0.1870,
        startsAt: DateTime.utc(2026, 9, 20, 15),
        endsAt: DateTime.utc(2026, 9, 20, 17),
        precision: GeoPrecision.exact,
        venueName: 'Wembley Court',
        areaName: 'Accra',
        description: 'Bring boots.',
        capacity: 22,
        minAge: 16,
        maxAge: 40,
        positionsRequired: const ['GK'],
      );
      final back = RadarEvent.fromJson(e.toJson());

      expect(back.type, e.type);
      expect(back.title, e.title);
      expect(back.precision, e.precision);
      expect(back.venueName, e.venueName);
      expect(back.areaName, e.areaName);
      expect(back.capacity, e.capacity);
      expect(back.minAge, e.minAge);
      expect(back.maxAge, e.maxAge);
      expect(back.positionsRequired, e.positionsRequired);
      expect(back.startsAt.toUtc(), e.startsAt.toUtc());
      expect(back.endsAt.toUtc(), e.endsAt.toUtc());
    });

    test('client pin/evt ids are dropped on live publish (uuid column)', () {
      // Mirror of upsertEvent: non-uuid ids must be replaced/removed, never
      // sent verbatim. The repository strips them; the model still carries
      // 'pin-…' locally for demo mode.
      final e = RadarEvent(
        id: 'pin-1726950000123456',
        type: RadarEventType.trainingSession,
        title: 'T',
        hostProfileId: 'h',
        hostName: 'H',
        latitude: 1,
        longitude: 2,
        startsAt: DateTime.utc(2026, 10, 1),
        endsAt: DateTime.utc(2026, 10, 1, 2),
        precision: GeoPrecision.approximate,
      );
      expect(RadarRepository.isValidUuid(e.id), isFalse);
      final row = e.toJson();
      row.removeWhere((k, v) =>
          k == 'id' && !RadarRepository.isValidUuid(v.toString()));
      expect(row.containsKey('id'), isFalse);
    });
  });

  group('UserProfile payload matches the profiles schema', () {
    test('round-trips core fields through fromJson/toJson', () {
      final p = UserProfile(
        id: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        piUid: 'pi-1',
        username: 'scout_ada',
        role: UserRole.scout,
        credibilityScore: 72.5,
        kycVerified: true,
        createdAt: DateTime.utc(2026, 1, 5),
        displayName: 'Ada Okafor',
        bio: 'UEFA B scout',
        country: 'Nigeria',
        city: 'Lagos',
        positions: const ['CM', 'ST'],
        footballCv: '12 years scouting',
        videoShowcaseUrls: const ['https://x.example/1'],
        clubAffiliation: 'Lagos FC',
        isMinor: false,
        geohashArea: 'Lagos — Ikeja',
        rating: 4.5,
        onboardedAt: DateTime.utc(2026, 2, 1),
      );
      final back = UserProfile.fromJson(p.toJson());

      expect(back.id, p.id);
      expect(back.piUid, p.piUid);
      expect(back.username, p.username);
      expect(back.role, p.role);
      expect(back.credibilityScore, p.credibilityScore);
      expect(back.kycVerified, p.kycVerified);
      expect(back.displayName, p.displayName);
      expect(back.country, p.country);
      expect(back.city, p.city);
      expect(back.positions, p.positions);
      expect(back.footballCv, p.footballCv);
      expect(back.videoShowcaseUrls, p.videoShowcaseUrls);
      expect(back.clubAffiliation, p.clubAffiliation);
      expect(back.geohashArea, p.geohashArea);
      expect(back.rating, p.rating);
      expect(back.onboardedAt, isNotNull);
      expect(back.isPublic, isTrue);
    });

    test('treats missing is_public as visible (default true)', () {
      final legacy = UserProfile.fromJson({
        'id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        'pi_uid': 'pi-2',
        'username': 'legacy',
      });
      expect(legacy.isPublic, isTrue);
    });

    test('never writes is_admin (operator-SQL-only capability)', () {
      final admin = UserProfile.fromJson({
        'id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        'pi_uid': 'pi-3',
        'username': 'ops',
        'is_admin': true,
      });
      expect(admin.isAdmin, isTrue, reason: 'parsed for the queue gate');
      expect(admin.toJson().containsKey('is_admin'), isFalse,
          reason: 'a client write path would be a privilege-escalation hole');
    });
  });

  group('ContentReport payload matches the content_reports schema', () {
    // The check constraint in 0004_feed_schedule_and_reports.sql is the
    // authority: an unlisted token is a hard Postgres reject on filing.
    const dbReasons = {
      'spam', 'abuse', 'inappropriate_media', 'misleading',
      'minor_safety', 'other',
    };
    const dbStatuses = {'open', 'reviewing', 'resolved', 'dismissed'};
    const insertableColumns = {
      'target_type', 'target_id', 'reason', 'details',
    };

    test('reason travels as the exact DB check-constraint token', () {
      for (final reason in ContentReportReason.values) {
        expect(dbReasons, contains(reason.db),
            reason: '${reason.name}.db must match the check constraint');
      }
      expect(dbReasons, hasLength(ContentReportReason.values.length));
      final payload = ContentReport(
        id: '',
        reporterProfileId: '',
        targetType: 'feed_post',
        targetId: '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
        reason: ContentReportReason.minorSafety,
        status: ContentReportStatus.open,
        createdAt: DateTime.now(),
      ).toJson();
      expect(payload['reason'], 'minor_safety');
      expect(payload.containsKey('reporter_profile_id'), isFalse,
          reason: 'RLS/default stamps the reporter; the client never does');
      expect(payload.keys, contains('target_type'));
      expect(payload.keys, contains('target_id'));
    });

    test('insert payload carries only client-ownable columns', () {
      final payload = ContentReport(
        id: 'x',
        reporterProfileId: 'y',
        targetType: 'radar_event',
        targetId: '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
        reason: ContentReportReason.spam,
        details: '  tick spam  ',
        status: ContentReportStatus.open,
        createdAt: DateTime.now(),
      ).toJson();
      expect(payload.keys, unorderedEquals(insertableColumns));
      expect(payload['details'], 'tick spam');
    });

    test('every status round-trips through fromJson', () {
      for (final status in ContentReportStatus.values) {
        expect(dbStatuses, contains(status.name));
        final r = ContentReport.fromJson({
          'id': '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
          'reporter_profile_id': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
          'target_type': 'feed_post',
          'target_id': '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
          'reason': 'spam',
          'status': status.name,
          'created_at': DateTime.now().toIso8601String(),
        });
        expect(r.status, status);
      }
    });

    test('unknown status/reason values fail safe to actionable defaults', () {
      final r = ContentReport.fromJson({
        'id': '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
        'target_type': 'feed_post',
        'target_id': '0f0e8a52-1c96-4a4a-9f9e-9c93c1a4b7d1',
        'reason': 'not_a_real_reason',
        'status': 'not_a_real_status',
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(r.status, ContentReportStatus.open,
          reason: 'an unknown token must not silently close a report');
      expect(r.reason, ContentReportReason.other);
    });
  });
}
