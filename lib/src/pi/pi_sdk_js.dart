// Web implementation of [PiSdkApi] backed by `dart:js_interop`.
//
// The SDK script is injected in web/index.html:
//   <script src="https://sdk.minepi.com/pi-sdk.js"></script>
// Reference: https://github.com/pi-apps/pi-platform-docs/blob/master/SDK_reference.md
//
// Snake_case external member names are intentional: they must match the Pi
// SDK's JS property names exactly.
// ignore_for_file: non_constant_identifier_names
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'pi_sdk_api.dart';

// ---------------------------------------------------------------------------
// JS interop bindings (all private to this file)
// ---------------------------------------------------------------------------

@JS()
@staticInterop
@anonymous
class _PiInitOptions {
  external factory _PiInitOptions({JSString version});
}

@JS()
@staticInterop
@anonymous
class _PiAuthResult {
  external factory _PiAuthResult();
}

extension _PiAuthResultExt on _PiAuthResult {
  external JSString get accessToken;
  external JSObject get user;
}

@JS()
@staticInterop
@anonymous
class _PiPaymentData {
  external factory _PiPaymentData({
    JSNumber amount,
    JSString memo,
    JSObject metadata,
  });
}

@JS()
@staticInterop
@anonymous
class _PiPaymentCallbacks {
  external factory _PiPaymentCallbacks({
    JSFunction onReadyForServerApproval,
    JSFunction onReadyForServerCompletion,
    JSFunction onCancel,
    JSFunction onError,
  });
}

@JS()
@staticInterop
@anonymous
class _PiPaymentDto {
  external factory _PiPaymentDto();
}

extension _PiPaymentDtoExt on _PiPaymentDto {
  external JSString get identifier;
  external JSString get user_uid;
  external JSNumber get amount;
  external JSString get memo;
  external JSAny? get metadata;
  external JSString get network;
  external JSObject get status;
  external JSObject? get transaction;
}

/// The global `Pi` object installed by pi-sdk.js.
extension type _PiGlobal._(JSObject _) implements JSObject {
  external void init(_PiInitOptions options);
  external JSPromise<JSAny?> authenticate(
    JSArray<JSString> scopes,
    JSFunction onIncompletePaymentFound,
  );
  external void createPayment(
    _PiPaymentData paymentData,
    _PiPaymentCallbacks callbacks,
  );
  external void openShareDialog(JSString title, JSString message);
  external JSPromise<JSArray<JSString>> nativeFeaturesList();
}

// ---------------------------------------------------------------------------
// Dart implementation
// ---------------------------------------------------------------------------

class PiSdkWeb implements PiSdkApi {
  PiSdkWeb();

  bool _initialized = false;

  _PiGlobal? _sdk() {
    try {
      final any = globalContext.getProperty<JSAny?>('Pi'.toJS);
      if (any == null || !any.isA<JSObject>()) return null;
      return any as _PiGlobal;
    } catch (_) {
      return null;
    }
  }

  @override
  bool isAvailable() => _sdk() != null;

  @override
  bool init({required String version}) {
    if (_initialized) return true;
    final pi = _sdk();
    if (pi == null) return false;
    try {
      // Official v2.0 standard: Pi.init({ version: "2.0" }).
      pi.init(_PiInitOptions(version: version.toJS));
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PiAuthData> authenticate({
    required List<String> scopes,
    required void Function(PiPaymentDtoData payment) onIncompletePaymentFound,
  }) async {
    final pi = _sdk();
    if (pi == null) {
      throw StateError('Pi SDK unavailable — open The Radar in the Pi Browser.');
    }

    void handleIncomplete(_PiPaymentDto dto) =>
        onIncompletePaymentFound(_dtoToData(dto));

    final result = await pi.authenticate(
      scopes.map((s) => s.toJS).toList().toJS,
      handleIncomplete.toJS,
    ).toDart as _PiAuthResult;

    final user = result.user;
    final uid = (user.getProperty<JSAny?>('uid'.toJS) as JSString?)?.toDart ?? '';
    final username =
        (user.getProperty<JSAny?>('username'.toJS) as JSString?)?.toDart ?? '';

    // KYC: probe defensively; not part of the public SDK contract.
    bool? kyc;
    final kycRaw = user.getProperty<JSAny?>('kyc_approved'.toJS) ??
        user.getProperty<JSAny?>('is_kyc_approved'.toJS);
    if (kycRaw != null && kycRaw.isA<JSBoolean>()) {
      kyc = (kycRaw as JSBoolean).toDart;
    }

    return PiAuthData(
      accessToken: result.accessToken.toDart,
      uid: uid,
      username: username,
      kycApproved: kyc,
    );
  }

  @override
  void createPayment({
    required double amount,
    required String memo,
    required Map<String, Object?> metadata,
    required PiPaymentCallbacks callbacks,
  }) {
    final pi = _sdk();
    if (pi == null) {
      callbacks.onError(
        'Pi SDK unavailable — open The Radar in the Pi Browser.',
        null,
      );
      return;
    }

    void onReadyForServerApproval(JSString paymentId) =>
        callbacks.onReadyForServerApproval(paymentId.toDart);

    void onReadyForServerCompletion(JSString paymentId, JSString txid) =>
        callbacks.onReadyForServerCompletion(paymentId.toDart, txid.toDart);

    void onCancel(JSString paymentId) =>
        callbacks.onCancel(paymentId.toDart);

    void onError(JSObject error, [JSObject? payment]) {
      String message = 'Unknown Pi payment error';
      try {
        final s = (error as JSAny?)?.dartify();
        if (s is Map && s['message'] != null) {
          message = s['message'].toString();
        } else if (s != null) {
          message = s.toString();
        }
      } catch (_) {}
      callbacks.onError(
        message,
        payment == null ? null : _dtoToData(payment as _PiPaymentDto),
      );
    }

    pi.createPayment(
      _PiPaymentData(
        amount: amount.toJS,
        memo: memo.toJS,
        metadata: (metadata.jsify() ?? JSObject()) as JSObject,
      ),
      _PiPaymentCallbacks(
        onReadyForServerApproval: onReadyForServerApproval.toJS,
        onReadyForServerCompletion: onReadyForServerCompletion.toJS,
        onCancel: onCancel.toJS,
        onError: onError.toJS,
      ),
    );
  }

  @override
  List<String> jsErrors() {
    try {
      final errors = globalContext.getProperty<JSArray<JSString>?>('__radarJsErrors'.toJS);
      return errors?.toDart.map((e) => e.toDart).toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  PiPaymentDtoData _dtoToData(_PiPaymentDto dto) {
    Map<String, Object?> readMetadata() {
      try {
        final map = dto.metadata.dartify();
        if (map is Map) return map.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
      return const {};
    }

    String? readTxid() {
      try {
        final tx = dto.transaction;
        return tx == null ? null : (tx.getProperty<JSAny?>('txid'.toJS) as JSString?)?.toDart;
      } catch (_) {
        return null;
      }
    }

    bool readStatus(String key) {
      try {
        final v = dto.status.getProperty<JSAny?>(key.toJS);
        return v != null && v.isA<JSBoolean>() && (v as JSBoolean).toDart;
      } catch (_) {
        return false;
      }
    }

    String? safeString(JSString? Function() get) {
      try {
        final v = get();
        return v?.toDart;
      } catch (_) {
        return null;
      }
    }

    return PiPaymentDtoData(
      identifier: safeString(() => dto.identifier) ?? '',
      userUid: safeString(() => dto.user_uid) ?? '',
      amount: _amountOf(dto),
      memo: safeString(() => dto.memo) ?? '',
      metadata: readMetadata(),
      txid: readTxid(),
      developerApproved: readStatus('developer_approved'),
      transactionVerified: readStatus('transaction_verified'),
      developerCompleted: readStatus('developer_completed'),
      cancelled: readStatus('cancelled'),
      userCancelled: readStatus('user_cancelled'),
      network: safeString(() => dto.network),
    );
  }

  double _amountOf(_PiPaymentDto dto) {
    try {
      return dto.amount.toDartDouble;
    } catch (_) {
      return 0;
    }
  }
}
