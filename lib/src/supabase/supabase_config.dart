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
}
