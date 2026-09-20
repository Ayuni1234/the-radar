import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_seed.dart';
import '../data/radar_repository.dart';
import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../pi/pi_service.dart';
import '../supabase/supabase_config.dart';

/// The signed-in Radar user (Pi-authenticated or demo).
@immutable
class RadarSession {
  const RadarSession({
    required this.piUid,
    required this.username,
    required this.kycVerified,
    required this.isDemo,
    this.profileId,
    this.accessToken,
    this.sessionToken,
    this.needsOnboarding = false,
    this.role = UserRole.player,
    this.isMinor = false,
  });

  final String piUid;
  final String username;
  final bool kycVerified;

  /// True when signed in through the offline demo fallback instead of the
  /// real Pi SDK.
  final bool isDemo;

  /// Supabase `profiles.id` once a profile row exists/loaded.
  final String? profileId;
  final String? accessToken;

  /// True while the guided onboarding (role → region → profile) is pending.
  final bool needsOnboarding;

  /// App Studio session token from the server-side exchange — proof the
  /// identity was verified server-side before this session existed.
  final String? sessionToken;
  final UserRole role;

  /// Safeguarding flag from the profile — drives location masking and the
  /// guardian-consent gates across the UI.
  final bool isMinor;

  RadarSession copyWith({
    String? piUid,
    String? username,
    bool? kycVerified,
    bool? isDemo,
    String? profileId,
    String? accessToken,
    String? sessionToken,
    bool? needsOnboarding,
    UserRole? role,
    bool? isMinor,
  }) =>
      RadarSession(
        piUid: piUid ?? this.piUid,
        username: username ?? this.username,
        kycVerified: kycVerified ?? this.kycVerified,
        isDemo: isDemo ?? this.isDemo,
        profileId: profileId ?? this.profileId,
        accessToken: accessToken ?? this.accessToken,
        sessionToken: sessionToken ?? this.sessionToken,
        needsOnboarding: needsOnboarding ?? this.needsOnboarding,
        role: role ?? this.role,
        isMinor: isMinor ?? this.isMinor,
      );
}

/// Authentication states for the login UI.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.reason});

  /// e.g. "Pi SDK unavailable — demo mode available below".
  final String? reason;
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session);
  final RadarSession session;
}

class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}

/// Owns the Pi SDK lifecycle and the signed-in session.
class AuthController extends AsyncNotifier<AuthState> {
  PiService? _pi;

  @override
  Future<AuthState> build() async {
    await SupabaseConfig.initialize();
    // PiConfig.current follows the official v2.0 standard: init with version
    // only — the SDK/Developer Portal decides the environment.
    _pi = PiService(onIncompletePayment: _handleIncompletePayment);
    await _pi!.init();
    if (_pi!.isSdkAvailable) {
      debugPrint('[Auth] Pi SDK detected — real authentication available.');
    } else {
      debugPrint('[Auth] Pi SDK not present — plain browser, demo mode only.');
    }
    return const AuthSignedOut();
  }

  PiService? get pi => _pi;

  /// Real Pi authentication.
  Future<void> signInWithPi() async {
    final service = _pi;
    if (service == null || !service.isSdkAvailable) {
      state = AsyncData(AuthSignedOut(
        reason: 'Pi SDK not available in this browser. Use demo sign-in.',
      ));
      return;
    }
    state = const AsyncData(AuthLoading());
    try {
      final outcome = await service.authenticate();
      final session = await _persistSession(outcome);
      state = AsyncData(AuthSignedIn(session));
    } on PiBridgeException catch (e) {
      state = AsyncData(AuthError(e.message));
    } catch (e) {
      state = AsyncData(AuthError('Pi sign-in failed: $e'));
    }
  }

  /// Offline/demo fallback (plain browsers, dev builds).
  Future<void> signInDemo() async {
    state = const AsyncData(AuthLoading());
    await Future<void>.delayed(const Duration(milliseconds: 400));
    const outcome = AuthSessionOutcome(
      piUid: 'demo-uid-0001',
      username: 'demo_scout',
      accessToken: 'demo-token',
      sessionToken: 'demo-session-token',
      supabaseUserId: 'demo-supabase-user',
      kycVerified: true,
    );
    final session = await _persistSession(outcome);
    state = AsyncData(AuthSignedIn(session));
  }

  /// Builds/loads the Supabase profile row for the authenticated Pi user and
  /// derives the signed-in [RadarSession].
  ///
  /// [outcome] carries the server-verified identity (App Studio values that
  /// arrived via the `pi-session` edge function — never the raw browser-side
  /// uid/username), so profile lookup and creation are keyed on a trusted
  /// uid and a real Supabase session (auth.uid() == profiles.id).
  Future<RadarSession> _persistSession(AuthSessionOutcome outcome) async {
    UserProfile? profile;
    final repo = RadarRepository.instance;

    if (SupabaseConfig.available) {
      try {
        final rows = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('pi_uid', outcome.piUid)
            .limit(1);
        if (rows.isNotEmpty) {
          profile = UserProfile.fromJson(rows.first);
        } else {
          // profiles.id == supabase auth uid for Pi users, so the insert
          // satisfies the RLS check (id = auth.uid(), pi_uid = verified).
          final newProfile = UserProfile(
            id: outcome.supabaseUserId,
            piUid: outcome.piUid,
            username: outcome.username,
            role: UserRole.player,
            credibilityScore: 10,
            kycVerified: outcome.kycVerified,
            createdAt: DateTime.now(),
          );
          await repo.upsertProfile(newProfile);
          profile = newProfile;
        }
      } catch (e) {
        debugPrint('[Auth] profile load/create failed: $e');
      }
    }

    // Pick an existing demo profile if running offline.
    profile ??= DemoFallback.profileForUid(outcome.piUid, outcome.username);

    return RadarSession(
      piUid: outcome.piUid,
      username: outcome.username,
      kycVerified: profile.kycVerified,
      isDemo: !SupabaseConfig.available,
      profileId: profile.id,
      accessToken: outcome.accessToken,
      sessionToken: outcome.sessionToken,
      needsOnboarding: profile.needsOnboarding,
      role: profile.role,
      isMinor: profile.isMinor,
    );
  }

  /// Persists the onboarding answers onto the profile row and marks it
  /// onboarded. Returns the refreshed session (no longer needsOnboarding).
  Future<RadarSession> finishOnboarding({
    required UserRole role,
    String? displayName,
    String? bio,
    String? country,
    String? city,
    bool isMinor = false,
  }) async {
    final auth = state.value;
    if (auth is! AuthSignedIn) {
      throw StateError('Cannot finish onboarding while signed out.');
    }
    final session = auth.session;
    final repo = RadarRepository.instance;

    UserProfile profile;
    try {
      List<Map<String, Object?>> rows = const [];
      if (SupabaseConfig.available && session.profileId != null) {
        final res = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('id', session.profileId!)
            .limit(1);
        rows = res.cast<Map<String, Object?>>();
      }
      profile = rows.isNotEmpty
          ? UserProfile.fromJson(rows.first)
          : DemoFallback.profileForUid(session.piUid, session.username);
    } catch (e) {
      debugPrint('[Auth] onboarding profile load failed: $e');
      profile = DemoFallback.profileForUid(session.piUid, session.username);
    }

    final updated = profile.copyWith(
      id: session.profileId ?? profile.id,
      piUid: session.piUid,
      role: role,
      displayName: (displayName?.trim().isNotEmpty ?? false)
          ? displayName!.trim()
          : profile.displayName,
      bio: bio?.trim(),
      country: country?.trim(),
      city: city?.trim(),
      isMinor: isMinor,
      onboardedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await repo.upsertProfile(updated);
    debugPrint('[Auth] onboarding complete for ${updated.username} '
        '(role=${updated.role.name}, minor=${updated.isMinor})');

    final next = session.copyWith(
      needsOnboarding: false,
      role: updated.role,
      isMinor: updated.isMinor,
    );
    state = AsyncData(AuthSignedIn(next));
    return next;
  }

  /// Account settings — role, region and visibility updates.
  /// Returns null on success, or a user-facing error message.
  Future<String?> updateAccount({
    UserRole? role,
    String? country,
    String? city,
    bool? isPublic,
  }) async {
    final auth = state.value;
    if (auth is! AuthSignedIn) return 'Not signed in.';
    final session = auth.session;
    final profileId = session.profileId;
    if (profileId == null) return 'Profile not provisioned yet.';

    final repo = RadarRepository.instance;
    UserProfile profile;
    try {
      List<Map<String, Object?>> rows = const [];
      if (SupabaseConfig.available) {
        final res = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('id', profileId)
            .limit(1);
        rows = res.cast<Map<String, Object?>>();
      }
      profile = rows.isNotEmpty
          ? UserProfile.fromJson(rows.first)
          : DemoFallback.profileForUid(session.piUid, session.username);
    } catch (e) {
      profile = DemoFallback.profileForUid(session.piUid, session.username);
    }

    final updated = profile.copyWith(
      id: profileId,
      piUid: session.piUid,
      role: role,
      country: (country?.trim().isNotEmpty ?? false)
          ? country!.trim()
          : profile.country,
      city:
          (city?.trim().isNotEmpty ?? false) ? city!.trim() : profile.city,
      isPublic: isPublic,
      updatedAt: DateTime.now(),
    );
    final ok = await repo.upsertProfile(updated);
    if (!ok) return 'Could not save settings — check your connection.';

    // Keep the offline dataset in sync so demo mode reflects the change.
    if (!SupabaseConfig.available) {
      final idx = DemoSeed.profiles.indexWhere((p) => p.id == profileId);
      if (idx >= 0) DemoSeed.profiles[idx] = updated;
    }

    final next = session.copyWith(role: updated.role);
    state = AsyncData(AuthSignedIn(next));
    return null;
  }

  /// Exports everything the platform stores about this account as
  /// pretty-printed JSON (GDPR-style data portability).
  Future<String> exportAccountData() async {
    final auth = state.value;
    if (auth is! AuthSignedIn) return '{}';
    final session = auth.session;
    final profileId = session.profileId ?? '';
    final repo = RadarRepository.instance;

    UserProfile? profile;
    try {
      List<Map<String, Object?>> rows = const [];
      if (SupabaseConfig.available && profileId.isNotEmpty) {
        final res = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('id', profileId)
            .limit(1);
        rows = res.cast<Map<String, Object?>>();
      }
      if (rows.isNotEmpty) profile = UserProfile.fromJson(rows.first);
    } catch (_) {}
    profile ??= DemoFallback.profileForUid(session.piUid, session.username);

    final events = await repo.fetchEvents();
    final myEvents =
        events.where((e) => e.hostProfileId == profileId).toList();
    final requests = profileId.isEmpty
        ? const <ConnectionRequest>[]
        : await repo.fetchConnections(profileId);

    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toIso8601String(),
      'profile': profile.toJson(),
      'hosted_events': [for (final e in myEvents) e.toJson()],
      'connection_requests': [
        for (final r in requests)
          {
            'id': r.id,
            'type': r.type.name,
            'status': r.status.name,
            'created_at': r.createdAt?.toIso8601String(),
          },
      ],
      'note': 'Guardian links and consent history are retained by the '
          'platform for safeguarding compliance and are not part of this '
          'export.',
    });
  }

  /// Secure account termination: deletes the profile row (RLS-scoped to
  /// the verified identity; dependent rows cascade server-side).
  /// Requires the user to type DELETE as confirmation.
  Future<String?> deleteAccount(String confirmation) async {
    if (confirmation.trim().toUpperCase() != 'DELETE') {
      return 'Type DELETE to confirm account termination.';
    }
    final auth = state.value;
    if (auth is! AuthSignedIn) return 'Not signed in.';
    final profileId = auth.session.profileId;
    if (profileId == null) return 'No profile to delete.';

    if (SupabaseConfig.available) {
      try {
        await SupabaseConfig.client
            .from('profiles')
            .delete()
            .eq('id', profileId);
      } catch (e) {
        debugPrint('[Auth] deleteAccount failed: $e');
        return 'Deletion failed — contact support if this persists.';
      }
    }
    await signOut();
    return null;
  }

  /// Refreshes the Supabase auth token backing the active session.
  Future<String?> refreshSessionToken() async {
    final auth = state.value;
    if (auth is! AuthSignedIn) return 'Not signed in.';
    if (!SupabaseConfig.available) {
      return 'Demo mode — no live session token to refresh.';
    }
    try {
      final res = await SupabaseConfig.client.auth.refreshSession();
      final s = res.session;
      if (s == null) return 'Refresh failed — sign in again with Pi.';
      final next = auth.session.copyWith(accessToken: s.accessToken);
      state = AsyncData(AuthSignedIn(next));
      return null;
    } catch (e) {
      debugPrint('[Auth] token refresh failed: $e');
      return 'Token refresh failed — re-authenticate with Pi.';
    }
  }

  void _handleIncompletePayment(PiPaymentRecord payment) {
    debugPrint(
        '[Auth] recovering incomplete payment ${payment.identifier}');
    // The PiService default handler already notifies the backend; nothing
    // further is required client-side.
  }

  Future<void> signOut() async {
    if (SupabaseConfig.available) {
      try {
        await SupabaseConfig.client.auth.signOut();
      } catch (_) {}
    }
    state = const AsyncData(AuthSignedOut());
  }
}

/// Small helper so demo sign-ins still get a plausible profile offline.
class DemoFallback {
  static UserProfile profileForUid(String uid, String username) {
    return UserProfile(
      id: uid,
      piUid: uid,
      username: username,
      role: UserRole.scout,
      credibilityScore: 55,
      kycVerified: true,
      createdAt: DateTime.now(),
      displayName: 'Demo Scout',
      bio: 'Demo session — Supabase not configured.',
      geohashArea: 'Demo area',
    );
  }
}

/// Provider: current auth state machine.
final authProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience provider for the signed-in session (or null).
final sessionProvider = Provider<RadarSession?>((ref) {
  final auth = ref.watch(authProvider).value;
  return auth is AuthSignedIn ? auth.session : null;
});
