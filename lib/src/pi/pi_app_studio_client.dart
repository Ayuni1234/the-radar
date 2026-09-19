// App Studio identity exchange (STEP 2 of the Pi authentication flow).
//
// Every sign-in MUST exchange the browser-obtained accessToken with App
// Studio. App Studio verifies it against the Pi Platform before answering,
// so the uid/username it returns are the only identity this app may trust.
// The browser-side Pi.authenticate result is for display only.
//
// Reference: https://pi-apps.github.io/pi-sdk-docs/quick-start/genai/Authentication
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Identity as verified by App Studio (the only trusted source).
class PiVerifiedIdentity {
  const PiVerifiedIdentity({
    required this.uid,
    required this.username,
    required this.sessionToken,
  });

  final String uid;
  final String username;
  final String sessionToken;
}

/// Thrown when the App Studio exchange fails.
class PiAuthExchangeException implements Exception {
  PiAuthExchangeException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'PiAuthExchangeException: $message';
}

/// HTTP client for the App Studio identity exchange.
class PiAppStudioClient {
  PiAppStudioClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// App Studio login endpoint. No Pi API key is needed for this call.
  static const String loginUrl =
      'https://backend.appstudio-u7cm9zhmha0ruwv8.piappengine.com/pi/auth/v1/login';

  /// Exchanges a browser-obtained `Pi.authenticate` accessToken for a
  /// verified identity (uid, username) plus an app session token.
  ///
  /// Exactly one exchange per sign-in — call this from the single place in
  /// the app that decides authorisation, never in addition to another path.
  Future<PiVerifiedIdentity> exchangeToken(String accessToken) async {
    if (accessToken.isEmpty) {
      throw PiAuthExchangeException('accessToken is empty — sign in first.');
    }

    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse(loginUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{'accessToken': accessToken}),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw PiAuthExchangeException('App Studio exchange failed: $e', cause: e);
    }

    if (res.statusCode != 200) {
      throw PiAuthExchangeException(
        'App Studio rejected the token (HTTP ${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }

    final Map<String, Object?> body;
    try {
      body = jsonDecode(res.body) as Map<String, Object?>;
    } on FormatException catch (e) {
      throw PiAuthExchangeException('Invalid App Studio response.', cause: e);
    }

    final sessionToken = body['sessionToken'];
    final user = body['user'];
    if (sessionToken is! String || sessionToken.isEmpty || user is! Map) {
      throw PiAuthExchangeException('App Studio response missing fields.');
    }

    final uid = user['uid'];
    final username = user['username'];
    if (uid is! String || uid.isEmpty) {
      throw PiAuthExchangeException('App Studio returned no uid.');
    }

    return PiVerifiedIdentity(
      uid: uid,
      username: username is String ? username : '',
      sessionToken: sessionToken,
    );
  }
}
