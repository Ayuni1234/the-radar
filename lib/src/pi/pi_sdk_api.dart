// Platform-neutral Pi SDK contract and data types.
//
// `pi_service.dart` and everything above it depends ONLY on this file —
// never on `dart:js_interop`. The web implementation lives in
// `pi_sdk_js.dart`, the VM/test stub in `pi_sdk_stub.dart`, and the
// conditional import that selects between them in `pi_sdk_bridge.dart`.
library;

/// Data result of a successful `Pi.authenticate`.
class PiAuthData {
  const PiAuthData({
    required this.accessToken,
    required this.uid,
    required this.username,
    this.kycApproved,
  });

  final String accessToken;

  /// App-scoped Pi user identifier.
  final String uid;

  /// Pi username.
  final String username;

  /// KYC flag when the host browser exposes it; null when unknown. The
  /// backend profile row remains the authoritative source of record.
  final bool? kycApproved;
}

/// Plain-Dart mirror of the Pi `PaymentDTO`.
class PiPaymentDtoData {
  const PiPaymentDtoData({
    required this.identifier,
    required this.userUid,
    required this.amount,
    required this.memo,
    this.metadata = const {},
    this.txid,
    this.developerApproved = false,
    this.transactionVerified = false,
    this.developerCompleted = false,
    this.cancelled = false,
    this.userCancelled = false,
    this.network,
  });

  final String identifier;
  final String userUid;
  final double amount;
  final String memo;
  final Map<String, Object?> metadata;
  final String? txid;
  final bool developerApproved;
  final bool transactionVerified;
  final bool developerCompleted;
  final bool cancelled;
  final bool userCancelled;
  final String? network;
}

/// Callback bundle mirroring the Pi `PaymentCallbacks` object.
class PiPaymentCallbacks {
  const PiPaymentCallbacks({
    required this.onReadyForServerApproval,
    required this.onReadyForServerCompletion,
    required this.onCancel,
    required this.onError,
  });

  final void Function(String paymentId) onReadyForServerApproval;
  final void Function(String paymentId, String txid) onReadyForServerCompletion;
  final void Function(String paymentId) onCancel;
  final void Function(String message, PiPaymentDtoData? payment) onError;
}

/// Platform boundary to the Pi Apps SDK.
abstract interface class PiSdkApi {
  /// Whether the SDK global exists (only true inside the Pi Browser).
  bool isAvailable();

  /// `Pi.init({ version, sandbox })` — idempotent.
  bool init({required String version, required bool sandbox});

  /// `Pi.authenticate(scopes, onIncompletePaymentFound)`.
  Future<PiAuthData> authenticate({
    required List<String> scopes,
    required void Function(PiPaymentDtoData payment) onIncompletePaymentFound,
  });

  /// `Pi.createPayment(data, callbacks)`.
  void createPayment({
    required double amount,
    required String memo,
    required Map<String, Object?> metadata,
    required PiPaymentCallbacks callbacks,
  });

  /// Uncaught JS errors recorded since page load (diagnostics).
  List<String> jsErrors();
}
