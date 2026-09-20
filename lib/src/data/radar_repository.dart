import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';
import '../supabase/supabase_config.dart';
import 'demo_seed.dart';

/// Data layer for profiles and radar events.
///
/// Uses the live Supabase connection when configured; otherwise serves the
/// in-memory demo dataset so the whole app remains explorable offline.
class RadarRepository {
  RadarRepository._();

  static final RadarRepository instance = RadarRepository._();

  bool get _live => SupabaseConfig.available;

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
    if (!_live) return const [];
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
    if (!_live) return true;
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

  Future<bool> upsertEvent(RadarEvent event) async {
    if (!_live) {
      debugPrint('[RadarRepo] demo mode: event stored locally only');
      return true;
    }
    try {
      await SupabaseConfig.client.from('radar_events').upsert(event.toJson());
      return true;
    } catch (e) {
      debugPrint('[RadarRepo] upsertEvent failed: $e');
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
          // Re-fetch for a consistent snapshot instead of patching locally —
          // robust to RLS-masked rows.
          unawaited(fetchEvents().then(onNext, onError: (Object e) {
            debugPrint('[RadarRepo] refetch failed: $e');
          }));
        },
      ).subscribe();
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
          unawaited(fetchProfiles().then(onNext, onError: (Object e) {
            debugPrint('[RadarRepo] refetch failed: $e');
          }));
        },
      ).subscribe();
      return null;
    } catch (e) {
      debugPrint('[RadarRepo] subscribeProfiles failed: $e');
      return null;
    }
  }
}
