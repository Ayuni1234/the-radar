import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/radar_repository.dart';
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
    this.role = UserRole.player,
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
  final UserRole role;

  RadarSession copyWith({
    String? piUid,
    String? username,
    bool? kycVerified,
    bool? isDemo,
    String? profileId,
    String? accessToken,
    UserRole? role,
  }) =>
      RadarSession(
        piUid: piUid ?? this.piUid,
        username: username ?? this.username,
        kycVerified: kycVerified ?? this.kycVerified,
        isDemo: isDemo ?? this.isDemo,
        profileId: profileId ?? this.profileId,
        accessToken: accessToken ?? this.accessToken,
        role: role ?? this.role,
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
    const outcome = PiAuthOutcome(
      uid: 'demo-uid-0001',
      username: 'demo_scout',
      accessToken: 'demo-token',
      sessionToken: 'demo-session-token',
      kycVerified: true,
    );
    final session = await _persistSession(outcome);
    state = AsyncData(AuthSignedIn(session));
  }

  /// Builds/loads the Supabase profile row for the authenticated Pi user and
  /// derives the signed-in [RadarSession].
  ///
  /// [outcome] carries the App Studio-verified identity (uid/username from
  /// the exchange, never the raw browser-side values), so profile lookup and
  /// creation are keyed on a server-trusted uid.
  Future<RadarSession> _persistSession(PiAuthOutcome outcome) async {
    UserProfile? profile;
    final repo = RadarRepository.instance;

    if (SupabaseConfig.available) {
      try {
        final rows = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('pi_uid', outcome.uid)
            .limit(1);
        if (rows.isNotEmpty) {
          profile = UserProfile.fromJson(rows.first);
        } else {
          final newProfile = UserProfile(
            id: outcome.uid, // profiles.id == pi uid for 1:1 mapping
            piUid: outcome.uid,
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
    profile ??= DemoFallback.profileForUid(outcome.uid, outcome.username);

    return RadarSession(
      piUid: outcome.uid,
      username: outcome.username,
      kycVerified: profile.kycVerified,
      isDemo: !SupabaseConfig.available,
      profileId: profile.id,
      accessToken: outcome.accessToken,
      role: profile.role,
    );
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
