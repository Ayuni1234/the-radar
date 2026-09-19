// Tests for the App Studio token-exchange client (STEP 2 of Pi auth).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_radar/src/pi/pi_app_studio_client.dart';

void main() {
  test('exchanges a valid accessToken for a verified identity', () async {
    http.Request? captured;
    final client = PiAppStudioClient(
      httpClient: MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'sessionToken': 'sess_123',
            'user': {'uid': 'pi-uid-1', 'username': 'pioneer'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final id = await client.exchangeToken('tok_abc');

    expect(captured, isNotNull);
    expect(captured!.url.toString(), PiAppStudioClient.loginUrl);
    expect(jsonDecode(captured!.body), {
      'accessToken': 'tok_abc',
    });
    expect(id.uid, 'pi-uid-1');
    expect(id.username, 'pioneer');
    expect(id.sessionToken, 'sess_123');
  });

  test('throws on non-200 responses', () async {
    final client = PiAppStudioClient(
      httpClient: MockClient((_) async => http.Response('denied', 401)),
    );

    await expectLater(
      client.exchangeToken('bad-token'),
      throwsA(isA<PiAuthExchangeException>()),
    );
  });

  test('throws when the response is missing fields', () async {
    final client = PiAppStudioClient(
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'sessionToken': 'x'}), 200),
      ),
    );

    await expectLater(
      client.exchangeToken('tok'),
      throwsA(isA<PiAuthExchangeException>()),
    );
  });

  test('rejects an empty accessToken before making a request', () async {
    var called = false;
    final client = PiAppStudioClient(
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.exchangeToken(''),
      throwsA(isA<PiAuthExchangeException>()),
    );
    expect(called, isFalse);
  });
}
