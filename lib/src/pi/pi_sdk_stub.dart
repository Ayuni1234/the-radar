// Non-web stub of the Pi SDK.
//
// Selected by the conditional import in `pi_sdk_bridge.dart` on VM / test
// platforms, where `dart:js_interop` is unavailable. Reports the SDK as
// unavailable so the app runs in demo mode during headless tests.
library;

import 'pi_sdk_api.dart';

/// The platform implementation used by [piSdk] (mirrors pi_sdk_web.dart).
final PiSdkApi piSdk = const PiSdkStub();

class PiSdkStub implements PiSdkApi {
  const PiSdkStub();

  @override
  bool isAvailable() => false;

  @override
  bool init({required String version, bool sandbox = false}) => false;

  @override
  Future<PiAuthData> authenticate({
    required List<String> scopes,
    required void Function(PiPaymentDtoData payment) onIncompletePaymentFound,
  }) async {
    throw UnsupportedError('Pi SDK is only available on Flutter Web.');
  }

  @override
  void createPayment({
    required double amount,
    required String memo,
    required Map<String, Object?> metadata,
    required PiPaymentCallbacks callbacks,
  }) {
    callbacks.onError(
      'Pi SDK is only available inside the Pi Browser (Flutter Web).',
      null,
    );
  }

  @override
  List<String> jsErrors() => const [];
}
