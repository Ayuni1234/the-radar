import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics/tracking_session.dart';
import '../models/connection_request.dart';
import '../models/content_report.dart';
import '../models/enums.dart';
import '../models/feed_post.dart';
import '../models/guardian_link.dart';
import '../models/pi_payment.dart';
import '../models/publish_outcome.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../supabase/supabase_config.dart';
import '../diagnostics/diagnostics.dart';
import '../sync/sync_bridge.dart';
import 'demo_seed.dart';

/// Data layer for profiles and radar events.
///
/// Uses the live Supabase connection when configured; otherwise serves the
/// in-memory demo dataset so the whole app remains explorable offline.
class RadarRepository {
  RadarRepository._();

  static final RadarRepository instance = RadarRepository._();

  /// Hard deadline for one write round-trip (insert / upsert / storage
  /// upload). Without this a hung request — captive portal, dropped radio,
  /// stalled socket — would leave the composer spinning forever with no
  /// outcome at all; now it resolves as a queueable transport failure.
  static const Duration _writeTimeout = Duration(seconds: 20);

  bool get _live => SupabaseConfig.available;

  /// Applies [_writeTimeout] to a Supabase request. On expiry the returned
  /// future completes with the error object below, which
  /// [_publishFailureReason] classifies as a transport failure (queueable).
  Future<T> _withTimeout<T>(Future<T> request) {
    return request.timeout(_writeTimeout, onTimeout: () {
      throw TimeoutException(
          'request exceeded ${_writeTimeout.inSeconds}s — transport stalled');
    });
  }

  /// Diagnostics hook: nothing persistent is cached client-side today
  /// (providers refetch on invalidation); demo stores reset instead.
  String clearCaches() {
    DemoSeed.resetDemoStores();
    return 'Local caches cleared — demo stores reset to seed state.';
  }

  /// Sync-center replay hooks. The current write paths are direct
  /// (fail-fast) rather than queued, so replay re-fires the last-known
  /// local mutation: demo stores are already authoritative offline; in
  /// live mode these return whether the backend accepts a fresh sync.
  Future<bool> replayProfileEdit() async {
    if (!_live) return true; // demo store already holds the data
    try {
      await SupabaseConfig.client
          .from('profiles')
          .select('id')
          .limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Demo-mode guardian link store (offline exploration of Module 3).
  static List<GuardianLink> _demoGuardianLinks = <GuardianLink>[
    GuardianLink(
      id: 'demo-gl-seed-1',
      minorProfile: 'demo-player-minor',
      guardianProfile: 'demo-parent-1',
      status: GuardianLinkStatus.active,
      consentConnections: false,
      consentEvents: true,
      createdAt: DateTime(2026, 4, 2),
    ),
  ];

  // ---------------------------------------------------------------- profiles

  Future<List<UserProfile>> fetchProfiles() async {
    if (!_live) return List.of(DemoSeed.profiles);
    try {
      final res = await SupabaseConfig.client
          .from('profiles')
          .select()
          .order('credibility_score', ascending: false);
      return res.map<UserProfile>((e) => UserProfile.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchProfiles failed: $e');
      return List.of(DemoSeed.profiles);
    }
  }

  Future<UserProfile?> fetchProfile(String id) async {
    if (!_live) {
      final all = [for (final p in DemoSeed.profiles) if (p.id == id) p];
      return all.isEmpty ? null : all.first;
    }
    try {
      final row =
          await SupabaseConfig.client.from('profiles').select().eq('id', id).maybeSingle();
      return row == null ? null : UserProfile.fromJson(row);
    } catch (e) {
      debugPrint('[RadarRepo] fetchProfile failed: $e');
      return null;
    }
  }

  /// Upsert the viewer's own profile (CV, positions, videos, role...).
  Future<bool> upsertProfile(UserProfile profile) async {
    if (!_live) {
      debugPrint('[RadarRepo] demo mode: profile edit stored locally only');
      return true;
    }
    try {
      await SupabaseConfig.client.from('profiles').upsert(profile.toJson());
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] upsertProfile failed: $e');
      Diagnostics.instance.log('sync', 'profile write failed — queued: $e');
      SyncBridge.instance.onWriteFailed('profile_edit',
          'Profile update for ${profile.username}', e.toString());
      return false;
    }
  }

  Future<List<UserProfile>> searchProfiles({
    UserRole? role,
    String? query,
    double? minCredibility,
  }) async {
    if (!_live) {
      return DemoSeed.profiles.where((p) {
        if (role != null && p.role != role) return false;
        if (minCredibility != null && p.credibilityScore < minCredibility) return false;
        if (query != null && query.isNotEmpty) {
          final q = query.toLowerCase();
          final hay = '${p.bestName} ${p.username} ${p.city ?? ''} '
                  '${p.positions.join(' ')} ${p.footballCv ?? ''}'
              .toLowerCase();
          if (!hay.contains(q)) return false;
        }
        return true;
      }).toList();
    }
    try {
      var q = SupabaseConfig.client.from('profiles').select();
      if (role != null) q = q.eq('role', role.name);
      if (minCredibility != null) {
        q = q.gte('credibility_score', minCredibility);
      }
      if (query != null && query.isNotEmpty) {
        q = q.or('username.ilike.%$query%,display_name.ilike.%$query%,city.ilike.%$query%');
      }
      final res = await q.order('credibility_score', ascending: false);
      return res.map<UserProfile>((e) => UserProfile.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] searchProfiles failed: $e');
      return const [];
    }
  }

  // --------------------------------------------------------- connections

  /// Creates a connection request (contact / trial invite / application).
  Future<bool> createConnectionRequest(ConnectionRequest request) async {
    if (!_live) {
      debugPrint('[RadarRepo] demo mode: connection stored locally only');
      return true;
    }
    try {
      await SupabaseConfig.client
          .from('connection_requests')
          .insert(request.toJson());
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] createConnectionRequest failed: $e');
      return false;
    }
  }

  /// All requests involving [profileId] (sent or received), newest first.
  Future<List<ConnectionRequest>> fetchConnections(String profileId) async {
    if (!_live) return DemoSeed.requestsFor(profileId);
    try {
      final res = await SupabaseConfig.client
          .from('connection_requests')
          .select('*')
          .or('from_profile.eq.$profileId,to_profile.eq.$profileId')
          .order('created_at', ascending: false);
      return res
          .map<ConnectionRequest>((e) => ConnectionRequest.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchConnections failed: $e');
      return const [];
    }
  }

  /// Pending requests received by [profileId] (the inbox).
  Future<List<ConnectionRequest>> fetchPendingInbox(String profileId) async {
    final all = await fetchConnections(profileId);
    return all
        .where((r) => r.isPending && r.toProfile == profileId)
        .toList();
  }

  /// Accepts or declines a received request (RLS: recipient only).
  Future<bool> respondToConnection(
      String requestId, ConnectionStatus status) async {
    if (!_live) return DemoSeed.respondToDemoRequest(requestId, status);
    try {
      await SupabaseConfig.client.from('connection_requests').update({
        'status': status.name,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] respondToConnection failed: $e');
      return false;
    }
  }

  /// Sender withdraws a pending request.
  Future<bool> withdrawConnection(String requestId) async {
    return respondToConnection(requestId, ConnectionStatus.withdrawn);
  }

  /// Whether [fromProfile] already has a pending request to [toProfile].
  Future<bool> hasPendingRequest(
      String fromProfile, String toProfile) async {
    if (!_live) return false;
    try {
      final res = await SupabaseConfig.client
          .from('connection_requests')
          .select('id')
          .eq('from_profile', fromProfile)
          .eq('to_profile', toProfile)
          .eq('status', 'pending')
          .limit(1);
      return res.isNotEmpty;
    } catch (e) {
      debugPrint('[RadarRepo] hasPendingRequest failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------- guardian

  /// All guardian links involving [profileId] — as minor or as guardian.
  Future<List<GuardianLink>> fetchGuardianLinks(String profileId) async {
    if (!_live) {
      return _demoGuardianLinks
          .where((l) =>
              l.minorProfile == profileId || l.guardianProfile == profileId)
          .toList();
    }
    try {
      final res = await SupabaseConfig.client
          .from('guardian_links')
          .select('*')
          .or('minor_profile.eq.$profileId,guardian_profile.eq.$profileId')
          .order('created_at', ascending: false);
      return res.map<GuardianLink>((e) => GuardianLink.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchGuardianLinks failed: $e');
      return const [];
    }
  }

  /// Minor invites a guardian (row is created pending; only the guardian
  /// can approve — enforced by the `guardian_links_insert_guard` trigger).
  Future<bool> createGuardianLink(
      String minorProfileId, String guardianProfileId) async {
    if (!_live) {
      _demoGuardianLinks.add(GuardianLink(
        id: 'demo-gl-${_demoGuardianLinks.length + 1}',
        minorProfile: minorProfileId,
        guardianProfile: guardianProfileId,
        status: GuardianLinkStatus.pending,
        createdAt: DateTime.now(),
      ));
      return true;
    }
    try {
      await SupabaseConfig.client.from('guardian_links').insert({
        'minor_profile': minorProfileId,
        'guardian_profile': guardianProfileId,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] createGuardianLink failed: $e');
      return false;
    }
  }

  /// Guardian approves/declines; the minor may revoke. The database trigger
  /// rejects anything else regardless of what the client sends.
  Future<bool> respondToGuardianLink(String linkId, String status) async {
    if (!_live) {
      _demoGuardianLinks = [
        for (final l in _demoGuardianLinks)
          if (l.id == linkId)
            GuardianLink(
              id: l.id,
              minorProfile: l.minorProfile,
              guardianProfile: l.guardianProfile,
              status: GuardianLinkStatus.fromRaw(status),
              consentConnections: l.consentConnections,
              consentEvents: l.consentEvents,
              createdAt: l.createdAt,
              updatedAt: DateTime.now(),
            )
          else
            l,
      ];
      return true;
    }
    try {
      await SupabaseConfig.client.from('guardian_links').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', linkId);
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] respondToGuardianLink failed: $e');
      return false;
    }
  }

  /// Guardian flips one or both consent switches (active links only).
  Future<bool> setGuardianConsent(
    String linkId, {
    bool? consentConnections,
    bool? consentEvents,
  }) async {
    if (!_live) {
      _demoGuardianLinks = [
        for (final l in _demoGuardianLinks)
          if (l.id == linkId)
            GuardianLink(
              id: l.id,
              minorProfile: l.minorProfile,
              guardianProfile: l.guardianProfile,
              status: l.status,
              consentConnections:
                  consentConnections ?? l.consentConnections,
              consentEvents: consentEvents ?? l.consentEvents,
              createdAt: l.createdAt,
              updatedAt: DateTime.now(),
            )
          else
            l,
      ];
      return true;
    }
    try {
      final patch = <String, Object?>{
        'updated_at': DateTime.now().toIso8601String(),
        'consent_connections': ?consentConnections,
        'consent_events': ?consentEvents,
      };
      await SupabaseConfig.client
          .from('guardian_links')
          .update(patch)
          .eq('id', linkId);
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] setGuardianConsent failed: $e');
      return false;
    }
  }

  /// The signed-in user's own payment receipts (RLS: payer only).
  Future<List<PiPayment>> fetchMyPayments() async {
    if (!_live) return const [];
    try {
      final res = await SupabaseConfig.client
          .from('pi_payments')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      return res.map<PiPayment>((e) => PiPayment.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchMyPayments failed: $e');
      return const [];
    }
  }

  /// The signed-in user's entitlements — boosts, premium access, bounties
  /// (RLS: `user_uid = verified_pi_uid()`).
  Future<List<Entitlement>> fetchMyEntitlements() async {
    if (!_live) return const [];
    try {
      final res = await SupabaseConfig.client
          .from('entitlements')
          .select()
          .order('granted_at', ascending: false);
      return res.map<Entitlement>((e) => Entitlement.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchMyEntitlements failed: $e');
      return const [];
    }
  }

  /// Consent ground truth for a profile (calls the `minor_consent_status`
  /// SECURITY DEFINER RPC — booleans only, no PII).
  Future<MinorConsent> fetchConsentStatus(String minorProfileId) async {
    if (!_live) {
      final links = _demoGuardianLinks.where((l) =>
          l.minorProfile == minorProfileId &&
          l.status == GuardianLinkStatus.active);
      final anyLink = links.isNotEmpty;
      final isMinor = DemoSeed.profiles
          .any((p) => p.id == minorProfileId && p.isMinor);
      return MinorConsent(
        isMinor: isMinor,
        consentConnections:
            !isMinor || (anyLink && links.any((l) => l.consentConnections)),
        consentEvents:
            !isMinor || (anyLink && links.any((l) => l.consentEvents)),
      );
    }
    try {
      final res = await SupabaseConfig.client.rpc(
        'minor_consent_status',
        params: {'p_minor': minorProfileId},
      );
      return MinorConsent.fromJson(res);
    } catch (e) {
      debugPrint('[RadarRepo] fetchConsentStatus failed: $e');
      // Fail CLOSED: treat as blocked until proven otherwise.
      return const MinorConsent(isMinor: true);
    }
  }

  /// Consent history for the signed-in user (as minor and/or guardian),
  /// read through the participant-scoped `read_consent_audit` RPC. The
  /// append-only log is written by database triggers; the client can
  /// never insert into it.
  Future<List<ConsentAuditEntry>> fetchConsentAudit() async {
    if (!_live) return const [];
    try {
      final res = await SupabaseConfig.client.rpc('read_consent_audit');
      return (res as List)
          .map<ConsentAuditEntry>(
              (e) => ConsentAuditEntry.fromJson(Map<String, Object?>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchConsentAudit failed: $e');
      return const [];
    }
  }

  /// Finds a guardian account by Pi username (used by the minor invite
  /// flow). Returns null when no parent profile matches.
  Future<UserProfile?> findGuardianByUsername(String username) async {
    final u = username.trim();
    if (u.isEmpty) return null;
    if (!_live) {
      for (final p in DemoSeed.profiles) {
        if (p.username.toLowerCase() == u.toLowerCase() &&
            p.role == UserRole.parent) {
          return p;
        }
      }
      return null;
    }
    try {
      final res = await SupabaseConfig.client
          .from('profiles')
          .select()
          .ilike('username', u)
          .eq('role', 'parent')
          .limit(1);
      return res.isEmpty ? null : UserProfile.fromJson(res.first);
    } catch (e) {
      debugPrint('[RadarRepo] findGuardianByUsername failed: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------ events

  Future<List<RadarEvent>> fetchEvents() async {
    if (!_live) return List.of(DemoSeed.events);
    try {
      final res = await SupabaseConfig.client
          .from('radar_events')
          .select()
          .gte('ends_at', DateTime.now().toUtc().toIso8601String())
          .order('starts_at', ascending: true);
      return res.map<RadarEvent>((e) => RadarEvent.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchEvents failed: $e');
      return List.of(DemoSeed.events);
    }
  }

  // ------------------------------------------------------------------ feed

  /// Latest social-feed posts (highlights, drills, tactical sessions).
  Future<List<FeedPost>> fetchFeedPosts({int limit = 60}) async {
    if (!_live) return List.of(DemoSeed.feedPosts);
    try {
      final res = await SupabaseConfig.client
          .from('feed_posts')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return res.map<FeedPost>((p) => FeedPost.fromJson(p)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchFeedPosts failed: $e');
      return List.of(DemoSeed.feedPosts);
    }
  }

  /// Publishes a feed post. The `enforce_feed_post_privacy` trigger fences
  /// minor-posters at the database level (coordinates nulled, coarse area
  /// only, media stripped).
  ///
  /// Returns a [PublishOutcome]: server rejections surface their real
  /// reason instead of being mislabeled as offline; only genuine
  /// transport failures are queued in the outbox (the payload is kept for
  /// [replayFeedPost]).
  Future<PublishOutcome> createFeedPost(FeedPost post) async {
    if (!_live) {
      DemoSeed.feedPosts.insert(0, post);
      return PublishOutcome.ok;
    }
    // Client-generated ids ('post-…') are not uuids — let Postgres issue
    // the primary key instead of failing the insert.
    _pendingFeedPost = post;
    try {
      await _withTimeout(
          SupabaseConfig.client.from('feed_posts').insert(post.toJson()));
      _pendingFeedPost = null;
      return PublishOutcome.ok;
    } catch (e) {
      debugPrint('[RadarRepo] createFeedPost failed: $e');
      final reason = _publishFailureReason(e);
      if (reason.$1) {
        Diagnostics.instance.log(
            'sync', 'feed post queued: ${post.kind.label}: $e');
        SyncBridge.instance.onWriteFailed(
            'feed_post', 'Publish ${post.kind.label.toLowerCase()}',
            e.toString());
        return PublishOutcome.queued(reason.$2);
      }
      _pendingFeedPost = null;
      return PublishOutcome.rejected(reason.$2);
    }
  }

  FeedPost? _pendingFeedPost;

  /// Outbox replay for a queued feed post (real re-fire, not a probe).
  ///
  /// Idempotent: if a timed-out request actually landed server-side, a
  /// blind re-insert would create a duplicate post. Re-inserts collide on
  /// the same deterministic `pending:<micros>` id instead — the duplicate
  /// attempt fails with a unique-violation, which counts as success and
  /// clears the outbox.
  Future<bool> replayFeedPost() async {
    final post = _pendingFeedPost;
    if (!_live) return post == null || true;
    if (post == null) return true;
    try {
      final row = post.toJson()
        ..['id'] = pendingReplayId(post); // uuid-shaped, deterministic
      await _withTimeout(
          SupabaseConfig.client.from('feed_posts').upsert(row));
      _pendingFeedPost = null;
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] replayFeedPost failed: $e');
      final duplicate = e is PostgrestException &&
          (e.code == '23505' || // unique_violation (id already stored)
              e.message.toLowerCase().contains('duplicate key'));
      if (duplicate) {
        _pendingFeedPost = null;
        return true; // already stored — nothing left to replay
      }
      return false;
    }
  }

  static final RegExp _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Deterministic, collision-resistant uuid (v4-shaped, hash-derived) for
  /// outbox replay ids. Only 32-bit-safe integer ops are used so the hash
  /// is identical on VM, web (dart2js/dart2wasm) and mobile.
  ///
  /// Why not a `pending:…` text id: feed_posts.id and radar_events.id are
  /// uuid columns — a non-uuid id would be rejected with 22P02 and the
  /// queued mutation would replay forever without ever succeeding.
  @visibleForTesting
  static String deterministicUuid(String seed) {
    var a = 0x9E3779B9, b = 0x85EBCA6B, c = 0xC2B2AE35, d = 0x27D4EB2F;
    for (var i = 0; i < seed.length; i++) {
      final cu = seed.codeUnitAt(i);
      a = (a ^ cu) & 0xFFFFFFFF;
      b = (b + ((a << 7) & 0xFFFFFFFF) + i) & 0xFFFFFFFF;
      c = (c ^ ((b >> 3) ^ cu)) & 0xFFFFFFFF;
      d = (d + ((c << 11) & 0xFFFFFFFF) ^ (a >> 5)) & 0xFFFFFFFF;
    }
    a = (a ^ (b >> 16)) & 0xFFFFFFFF;
    b = (b ^ ((c << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    c = (c ^ (d >> 7)) & 0xFFFFFFFF;
    d = (d ^ ((a << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    String hex(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final raw = '${hex(a)}${hex(b)}${hex(c)}${hex(d)}';
    // 8-4-4-4-12 with version 4 and an RFC-4122 variant nibble.
    return '${raw.substring(0, 8)}-${raw.substring(8, 12)}-'
        '4${raw.substring(13, 16)}-8${raw.substring(17, 20)}-'
        '${raw.substring(20, 32)}';
  }

  /// Whether [s] is a uuid — the shape Postgres uuid columns accept.
  @visibleForTesting
  static bool isValidUuid(String s) => _uuidRe.hasMatch(s);

  /// Deterministic outbox replay id for a client-draft post
  /// (`post-<micros>`). A valid uuid so the replay upsert is accepted, and
  /// stable so a replay after a timed-out-but-landed write collides on the
  /// same row (unique-violation ⇒ idempotent success) instead of
  /// duplicating. Exposed for tests.
  @visibleForTesting
  static String pendingReplayId(FeedPost post) => deterministicUuid(post.id);

  // ---------------------------------------------------------------- reports

  /// Files a content report (feed post / radar event / market listing)
  /// into `content_reports`. RLS stamps the reporter (`auth.uid()`), so
  /// the client never sends an identity.
  ///
  /// Returns `(reportId, error)` — exactly one is non-null. A duplicate
  /// open report (one open report per reporter per target, enforced by the
  /// `content_reports_one_open_per_target` partial unique index) is a
  /// definitive server answer, not a transport failure: it surfaces as a
  /// friendly error instead of being queued for replay, because replaying
  /// it would fail identically forever.
  Future<(String?, String?)> createContentReport({
    required String targetType,
    required String targetId,
    required ContentReportReason reason,
    String? details,
  }) async {
    if (!_live) {
      Diagnostics.instance.log('moderation', 'report filed (demo): $reason');
      return ('demo-report', null);
    }
    final payload = ContentReport(
      id: '',
      reporterProfileId: '',
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
      status: ContentReportStatus.open,
      createdAt: DateTime.now(),
    ).toJson();
    try {
      final res = await _withTimeout(SupabaseConfig.client
          .from('content_reports')
          .insert(payload)
          .select('id')
          .single());
      final id = (res['id'] ?? '').toString();
      Diagnostics.instance.log('moderation', 'report filed: $id ($reason)');
      return (id, null);
    } catch (e) {
      debugPrint('[RadarRepo] createContentReport failed: $e');
      if (e is PostgrestException && e.code == '23505') {
        return (
          null,
          'You already reported this — it is still awaiting review by the '
          'moderation team.'
        );
      }
      return (
        null,
        'Could not file the report right now — check your connection and '
        'try again.'
      );
    }
  }

  /// All content reports, newest first. RLS does the filtering: reporters
  /// see their own, admins see everything (the queue), so an empty result
  /// for a non-admin viewer is the server's answer, not an error.
  Future<List<ContentReport>> fetchContentReports() async {
    if (!_live) return List.of(DemoSeed.contentReports);
    try {
      final res = await SupabaseConfig.client
          .from('content_reports')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      return res.map<ContentReport>((e) => ContentReport.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchContentReports failed: $e');
      return const [];
    }
  }

  /// Advances the status workflow (open → reviewing → resolved/dismissed).
  /// Stamps `reviewed_at` on first close. Admin-only by RLS; updates the
  /// demo store when offline. Returns the updated report, or null if the
  /// write failed (the queue keeps the previous state and shows an error).
  Future<ContentReport?> updateContentReportStatus(
    ContentReport report,
    ContentReportStatus status,
  ) async {
    final closing =
        status == ContentReportStatus.resolved ||
        status == ContentReportStatus.dismissed;
    final reviewedAt =
        closing && report.reviewedAt == null ? DateTime.now() : report.reviewedAt;
    if (!_live) {
      DemoSeed.setReportStatus(report.id, status, reviewedAt);
      return report.copyWith(status: status, reviewedAt: reviewedAt);
    }
    try {
      await _withTimeout(SupabaseConfig.client
          .from('content_reports')
          .update({
            'status': status.name,
            if (reviewedAt != null)
              'reviewed_at': reviewedAt.toUtc().toIso8601String(),
          })
          .eq('id', report.id));
      return report.copyWith(status: status, reviewedAt: reviewedAt);
    } catch (e) {
      debugPrint('[RadarRepo] updateContentReportStatus failed: $e');
      return null;
    }
  }

  /// Failure classifier — exposed for tests. Returns `(retryable, message)`
  /// exactly as the publish paths consume it.
  @visibleForTesting
  static (bool, String) classifyFailure(Object e) =>
      instance._publishFailureReason(e);

  /// Classifies a failed Supabase write. Returns `(retryable, message)`:
  /// retryable ⇒ transport/offline (queue it); otherwise the server
  /// rejected the write and the message is the human-readable reason.
  (bool, String) _publishFailureReason(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();

    // Transport problems are the ONLY retryable class. They queue into the
    // outbox and replay automatically, so the message tells the user what
    // will happen instead of pretending the post was published.
    const transportHints = [
      'socketexception', 'clientexception', 'failed host lookup',
      'connection', 'timeout', 'timed out', 'network', 'offline',
      'connectionclosed', 'handshake', 'transport stalled',
    ];
    for (final h in transportHints) {
      if (lower.contains(h)) {
        return (
          true,
          'The server could not be reached — your post is saved and will '
          'publish automatically once the connection is back.'
        );
      }
    }

    // Everything below is a definitive server answer: retrying verbatim
    // fails identically, so surface the real reason with a next step.
    // Typed Supabase exceptions carry a clean `message` — prefer it over
    // regex-parsing the toString() dump.
    String message;
    if (e is PostgrestException) {
      message = e.message;
    } else if (e is StorageException) {
      message = e.message;
    } else {
      message = raw.length > 220 ? '${raw.substring(0, 220)}…' : raw;
      final msgMatch = RegExp('["\']?message["\']?\\s*[:=]\\s*["\']([^"\']+)')
          .firstMatch(raw);
      if (msgMatch != null) message = msgMatch.group(1)!;
    }
    message = message
        .replaceFirst(
            RegExp(r'^(Exception|PostgrestException|StorageException)[:]?\s*'),
            '')
        .trim();
    if (message.isEmpty) message = 'Unknown server error';

    final action = _serverHint(message, lower, e);
    return (false, action == null ? message : '$message. $action');
  }

  /// Maps known server rejections to an actionable next step for the
  /// composer banner / snackbar.
  String? _serverHint(String message, String lower, Object e) {
    final code = e is PostgrestException ? (e.code ?? '') : '';
    if (code == '23503' || lower.contains('foreign key')) {
      return 'Your sign-in session may have expired — reopen the app and try '
          'again.';
    }
    if (code == '42501' || lower.contains('row-level security')) {
      return 'You are not allowed to publish this — sign in again or check '
          'your profile role.';
    }
    if (code == '23514' ||
        lower.contains('violates check constraint') ||
        lower.contains('validation')) {
      return 'Adjust the content (length, media size or kind) and retry.';
    }
    if (lower.contains('does not exist') || code == '42703') {
      return 'The app version looks outdated — hard-refresh (Ctrl+Shift+R) '
          'to pick up the latest build.';
    }
    return null;
  }

  /// Deletes one of the viewer's own feed posts.
  Future<bool> deleteFeedPost(String postId) async {
    if (!_live) {
      DemoSeed.feedPosts.removeWhere((p) => p.id == postId);
      return true;
    }
    try {
      await SupabaseConfig.client.from('feed_posts').delete().eq('id', postId);
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] deleteFeedPost failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------- stream bounties

  /// The AI-tracking session bound to a bounty broadcast. Live deployments
  /// would stream engine frames from the streamer's phone; today the
  /// binding resolves to a deterministic synthetic session (demo) or null
  /// until the streamer's tracker has published telemetry.
  Future<TrackingSession?> fetchTrackingSession(String bountyId) async {
    if (!_live) return DemoSeed.trackingSessions[bountyId];
    try {
      final res = await SupabaseConfig.client
          .from('tracking_sessions')
          .select()
          .eq('bounty_id', bountyId)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      final frames = res['samples_json'] is List
          ? List<Map<String, Object?>>.from(
              (res['samples_json'] as List).cast<Map<String, Object?>>())
          : const <Map<String, Object?>>[];
      return TrackingSession(
        id: (res['id'] ?? '').toString(),
        bountyId: bountyId,
        playerLabel: (res['player_label'] ?? 'Locked player').toString(),
        startedAt: DateTime.tryParse(res['started_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
        durationMin: (res['duration_min'] as num?)?.toInt() ?? 90,
        lockConfidence: (res['lock_confidence'] as num?)?.toDouble() ?? 0.9,
        samples: frames
            .map(TrackSampleJson.fromJson)
            .toList(growable: false),
      );
    } catch (e) {
      debugPrint('[RadarRepo] fetchTrackingSession failed: $e');
      return null;
    }
  }

  /// All visible stream bounties (gig board), newest first.
  Future<List<StreamBounty>> fetchStreamBounties() async {
    if (!_live) return List.of(DemoSeed.streamBounties);
    try {
      final res = await SupabaseConfig.client
          .from('stream_bounties')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      return res.map<StreamBounty>((b) => StreamBounty.fromJson(b)).toList();
    } catch (e) {
      debugPrint('[RadarRepo] fetchStreamBounties failed: $e');
      return List.of(DemoSeed.streamBounties);
    }
  }

  /// Creates a bounty row. The poster then funds it with a Pi U2A payment
  /// (product `stream_bounty_funding`, reference_id = bounty id).
  Future<StreamBounty?> createStreamBounty(StreamBounty bounty) async {
    if (!_live) {
      DemoSeed.streamBounties.insert(0, bounty);
      return bounty;
    }
    try {
      final res = await SupabaseConfig.client
          .from('stream_bounties')
          .insert({
            'poster_profile_id': bounty.posterProfileId,
            'poster_name': bounty.posterName,
            'title': bounty.title,
            'brief': bounty.brief,
            'area_name': bounty.areaName,
            'venue_name': bounty.venueName,
            'latitude': bounty.latitude,
            'longitude': bounty.longitude,
            'amount_pi': bounty.amountPi,
            'duration_minutes': bounty.durationMinutes,
            'kickoff_at': bounty.kickoffAt?.toIso8601String(),
            'status': 'open',
          })
          .select()
          .single();
      return StreamBounty.fromJson(res);
    } catch (e) {
      debugPrint('[RadarRepo] createStreamBounty failed: $e');
      return null;
    }
  }

  /// Client-side status edit. Most transitions go through dedicated RPCs or
  /// edge functions; this is the thin update used for assign/start/finish.
  Future<bool> updateBounty(String id, Map<String, Object?> patch) async {
    if (!_live) {
      for (var i = 0; i < DemoSeed.streamBounties.length; i++) {
        if (DemoSeed.streamBounties[i].id == id) {
          final b = DemoSeed.streamBounties[i];
          DemoSeed.streamBounties[i] = StreamBounty.fromJson({
            'id': b.id,
            'poster_profile_id': b.posterProfileId,
            'poster_name': b.posterName,
            'title': b.title,
            'brief': b.brief,
            'area_name': b.areaName,
            'venue_name': b.venueName,
            'latitude': b.latitude,
            'longitude': b.longitude,
            'amount_pi': b.amountPi,
            'duration_minutes': b.durationMinutes,
            'kickoff_at': b.kickoffAt?.toIso8601String(),
            'status': patch['status'] ?? b.status,
            'streamer_profile_id':
                patch['streamer_profile_id'] ?? b.streamerProfileId,
            'streamer_name': patch['streamer_name'] ?? b.streamerName,
            'stream_url': patch['stream_url'] ?? b.streamUrl,
            'watched_minutes': b.watchedMinutes,
            'completed_at': b.completedAt?.toIso8601String(),
            'created_at': b.createdAt.toIso8601String(),
          });
          return true;
        }
      }
      return false;
    }
    try {
      await SupabaseConfig.client
          .from('stream_bounties')
          .update(patch)
          .eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] updateBounty failed: $e');
      return false;
    }
  }

  /// Poster-only escrow release through the `release_bounty` SECURITY
  /// DEFINER RPC. Returns true when the bounty flipped to completed.
  Future<bool> releaseBounty(String bountyId) async {
    if (!_live) {
      for (var i = 0; i < DemoSeed.streamBounties.length; i++) {
        final b = DemoSeed.streamBounties[i];
        if (b.id == bountyId && (b.status == 'live' || b.status == 'disputed')) {
          DemoSeed.streamBounties[i] = b.copyWith(status: 'completed');
          return true;
        }
      }
      return false;
    }
    try {
      await SupabaseConfig.client.rpc('release_bounty', params: {
        'bounty_id': bountyId,
      });
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] releaseBounty failed: $e');
      return false;
    }
  }

  /// Triggers the instant A2U micro-payout to the streamer's Pi wallet via
  /// the `bounty-payout` edge function (idempotent — safe to re-invoke).
  /// Returns the payout payment id, or null on failure.
  Future<String?> triggerBountyPayout(String bountyId) async {
    if (!_live) return 'demo-payout-$bountyId';
    try {
      final res = await SupabaseConfig.functions.invoke(
        'bounty-payout',
        body: {'bountyId': bountyId},
      );
      final data = res.data;
      if (data is Map) {
        if (data['ok'] == true) {
          return (data['paymentId'] ?? 'unknown').toString();
        }
        debugPrint(
            '[RadarRepo] bounty payout rejected: ${data['error']}');
      }
      return null;
    } catch (e) {
      debugPrint('[RadarRepo] triggerBountyPayout failed: $e');
      return null;
    }
  }

  Future<PublishOutcome> upsertEvent(RadarEvent event) async {
    if (!_live) {
      // Demo mode: keep the published event visible on the offline radar.
      DemoSeed.events.removeWhere((e) => e.id == event.id);
      DemoSeed.events.add(event);
      return PublishOutcome.ok;
    }
    // Client ids ('pin-…', 'evt-…') are not uuids — omit and let Postgres
    // generate the primary key. Real uuid ids (server-issued) upsert fine.
    final row = event.toJson();
    if (!_uuidRe.hasMatch(event.id)) row.remove('id');
    _pendingEvent = event;
    try {
      await _withTimeout(
          SupabaseConfig.client.from('radar_events').upsert(row));
      _pendingEvent = null;
      return PublishOutcome.ok;
    } catch (e) {
      debugPrint('[RadarRepo] upsertEvent failed: $e');
      final reason = _publishFailureReason(e);
      if (reason.$1) {
        Diagnostics.instance.log(
            'sync', 'event write queued: ${event.title}: $e');
        SyncBridge.instance.onWriteFailed(
            'event_create', 'Publish “${event.title}”', e.toString());
        return PublishOutcome.queued(reason.$2);
      }
      _pendingEvent = null;
      return PublishOutcome.rejected(reason.$2);
    }
  }

  RadarEvent? _pendingEvent;

  /// Outbox replay for a queued radar pin/event (real re-fire).
  Future<bool> replayEventCreate() async {
    final event = _pendingEvent;
    if (!_live) return true; // demo store already holds the data
    if (event == null) {
      // Legacy queue item: probe reachability so the item can be cleared.
      try {
        await SupabaseConfig.client.from('radar_events').select('id').limit(1);
        return true;
      } catch (_) {
        return false;
      }
    }    final row = event.toJson();
    if (!_uuidRe.hasMatch(event.id)) {
      // Deterministic replay id: a timed-out attempt that actually landed
      // server-side makes the re-upsert a no-op instead of a duplicate.
      // Must be uuid-shaped — the column rejects anything else.
      row['id'] = deterministicUuid(event.id);
    }

    try {
      await _withTimeout(
          SupabaseConfig.client.from('radar_events').upsert(row));
      _pendingEvent = null;
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] replayEventCreate failed: $e');
      return false;
    }
  }

  /// Leaves a channel previously returned by [subscribeEvents] or
  /// [subscribeProfiles].
  Future<void> unsubscribe(RealtimeChannel? channel) async {
    if (channel == null || !_live) return;
    try {
      await SupabaseConfig.client.removeChannel(channel);
    } catch (e) {
      debugPrint('[RadarRepo] unsubscribe failed: $e');
    }
  }

  /// Realtime: subscribe to `radar_events` changes (INSERT/UPDATE/DELETE).
  /// Returns the joined [RealtimeChannel] (pass it to [unsubscribe] when
  /// done), or null in demo mode / on failure. [onNext] fires immediately
  /// with the current snapshot and again after every change.
  RealtimeChannel? subscribeEvents(void Function(List<RadarEvent>) onNext) {
    if (!_live) {
      // Demo mode: no realtime, but keep the callback contract.
      onNext(List.of(DemoSeed.events));
      return null;
    }
    try {
      final channel = SupabaseConfig.client.channel('radar-events-live');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'radar_events',
        callback: (payload) {
          debugPrint('[RadarRepo] realtime ${payload.eventType.name}');
          Diagnostics.instance.log('realtime',
              'radar_events ${payload.eventType.name} — refetching');
          
          // Re-fetch for a consistent snapshot instead of patching locally —
          // robust to RLS-masked rows.
          unawaited(fetchEvents().then(onNext, onError: (Object e) {
            debugPrint('[RadarRepo] refetch failed: $e');
          }));
        },
      ).subscribe();
      Diagnostics.instance.trackChannel('radar-events-live');
      return null;
    } catch (e) {
      debugPrint('[RadarRepo] subscribeEvents failed: $e');
      return null;
    }
  }

  /// Realtime: subscribe to `profiles` changes. Same contract as
  /// [subscribeEvents].
  RealtimeChannel? subscribeProfiles(void Function(List<UserProfile>) onNext) {
    if (!_live) {
      onNext(List.of(DemoSeed.profiles));
      return null;
    }
    try {
      final channel = SupabaseConfig.client.channel('radar-profiles-live');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: (payload) {
          Diagnostics.instance
              .log('realtime', 'profiles ${payload.eventType.name} — refetching');
          unawaited(fetchProfiles().then(onNext, onError: (Object e) {
            debugPrint('[RadarRepo] refetch failed: $e');
          }));
        },
      ).subscribe();
      Diagnostics.instance.trackChannel('radar-profiles-live');
      return null;
    } catch (e) {
      debugPrint('[RadarRepo] subscribeProfiles failed: $e');
      return null;
    }
  }
}
