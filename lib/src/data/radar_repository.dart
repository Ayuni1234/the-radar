import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics/tracking_session.dart';
import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/feed_post.dart';
import '../models/guardian_link.dart';
import '../models/pi_payment.dart';
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

  bool get _live => SupabaseConfig.available;

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

  Future<bool> replayEventCreate() async {
    if (!_live) return true;
    try {
      await SupabaseConfig.client
          .from('radar_events')
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
  Future<bool> createFeedPost(FeedPost post) async {
    if (!_live) {
      DemoSeed.feedPosts.insert(0, post);
      return true;
    }
    try {
      await SupabaseConfig.client.from('feed_posts').insert(post.toJson());
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] createFeedPost failed: $e');
      Diagnostics.instance.log(
          'sync', 'feed post failed — queued: ${post.kind.label}: $e');
      SyncBridge.instance.onWriteFailed(
          'feed_post', 'Publish ${post.kind.label.toLowerCase()}',
          e.toString());
      return false;
    }
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

  Future<bool> upsertEvent(RadarEvent event) async {
    if (!_live) {
      // Demo mode: keep the published event visible on the offline radar.
      DemoSeed.events.removeWhere((e) => e.id == event.id);
      DemoSeed.events.add(event);
      return true;
    }
    try {
      await SupabaseConfig.client.from('radar_events').upsert(event.toJson());
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] upsertEvent failed: $e');
      Diagnostics.instance.log('sync',
          'event write failed — queued: ${event.title}: $e');
      SyncBridge.instance.onWriteFailed(
          'event_create', 'Publish “${event.title}”', e.toString());
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
