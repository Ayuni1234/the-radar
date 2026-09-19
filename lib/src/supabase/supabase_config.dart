// Supabase bootstrap for The Radar.
//
// Paste your project credentials into [SupabaseEnv] (or supply them via
// `--dart-define`), then run `supabase_schema.sql` in the SQL editor.
//
// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time overrides, e.g.
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///              --dart-define=SUPABASE_ANON_KEY=eyJ...
const String _kEnvUrl = String.fromEnvironment('SUPABASE_URL');
const String _kEnvAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Replace with your own project values, or use the dart-define overrides.
class SupabaseEnv {
  static const String url = _kEnvUrl;
  static const String publishableKey = _kEnvAnonKey;
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

/// Global accessor. [available] is false when no credentials are configured —
/// repositories then fall back to the built-in demo dataset.
class SupabaseConfig {
  static bool _initialized = false;
  static bool _available = false;

  /// True once `initialize()` succeeded with real credentials.
  static bool get available => _available;

  static SupabaseClient get client {
    assert(_available,
        'Supabase is not configured. Set SUPABASE_URL / SUPABASE_ANON_KEY.');
    return Supabase.instance.client;
  }

  /// Edge Functions client — used by the Pi payment webhooks.
  static FunctionsClient get functions => client.functions;

  static GoTrueClient get auth => client.auth;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!SupabaseEnv.isConfigured) {
      debugPrint(
          '[Supabase] No SUPABASE_URL / SUPABASE_ANON_KEY provided — '
          'running in demo mode with local seed data.');
      return;
    }

    try {
      await Supabase.initialize(
        url: SupabaseEnv.url,
        publishableKey: SupabaseEnv.publishableKey,
        debug: kDebugMode,
      );
      _available = true;
      debugPrint('[Supabase] initialized at ${SupabaseEnv.url}');
    } catch (e) {
      debugPrint('[Supabase] initialization failed: $e');
    }
  }

  /// Establishes the Supabase session from the App Studio-verified Pi
  /// identity (STEP 2/3 of the Pi authentication flow, server-side).
  ///
  /// The `pi-session` edge function exchanges the browser-obtained Pi
  /// accessToken with App Studio — exactly once per sign-in — and provisions
  /// a Supabase auth user whose app_metadata.pi_uid IS the VERIFIED uid.
  /// This method then verifies in with the returned one-time token, yielding
  /// a real Supabase session that every RLS policy trusts via
  /// `verified_pi_uid()` / `auth.uid()`. Browser-side uid/username are never
  /// used for authorisation.
  static Future<PiSupabaseSession> signInWithPiToken(String accessToken) async {
    if (!available) {
      throw const PiSessionException('Supabase is not configured.');
    }

    final res = await functions
        .invoke('pi-session', body: {'accessToken': accessToken});
    final data = res.data;
    if (data is! Map || data['ok'] != true) {
      throw const PiSessionException('Session provisioning failed.');
    }

    final user = data['user'];
    final magic = data['magic'];
    if (user is! Map || magic is! Map) {
      throw const PiSessionException('Session response missing fields.');
    }
    final token = magic['token'];
    final email = magic['email'];
    if (token is! String || token.isEmpty || email is! String) {
      throw const PiSessionException('One-time session token missing.');
    }

    final authRes = await auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.magiclink,
    );
    final session = authRes.session;
    if (session == null) {
      throw const PiSessionException('Supabase session missing after verify.');
    }

    return PiSupabaseSession(
      piUid: (user['uid'] as String?) ?? '',
      username: (user['username'] as String?) ?? '',
      sessionToken: (data['sessionToken'] as String?) ?? '',
      userId: session.user.id,
    );
  }
}

/// Thrown when server-side session provisioning fails.
class PiSessionException implements Exception {
  const PiSessionException(this.message);

  final String message;

  @override
  String toString() => 'PiSessionException: $message';
}

/// Result of the server-verified Pi sign-in.
class PiSupabaseSession {
  const PiSupabaseSession({
    required this.piUid,
    required this.username,
    required this.sessionToken,
    required this.userId,
  });

  /// App Studio-verified Pi uid (the only trusted identity).
  final String piUid;

  /// App Studio-verified username.
  final String username;

  /// App Studio session token from the server-side exchange.
  final String sessionToken;

  /// Supabase auth user id (deterministic UUID of [piUid]).
  final String userId;
}
