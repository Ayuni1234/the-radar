// High-level Dart bridge over the Pi Network Apps SDK.
//
// Depends only on the platform-neutral [PiSdkApi]; the web implementation
// (`pi_sdk_js.dart`) talks to `window.Pi`, the VM stub (`pi_sdk_stub.dart`)
// keeps tests compiling.
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../supabase/supabase_config.dart';
import 'pi_config.dart';
import 'pi_sdk_api.dart';
import 'pi_sdk_bridge.dart' show piSdk;

/// Exception raised by the Pi bridge.
class PiBridgeException implements Exception {
  PiBridgeException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'PiBridgeException: $message';
}

/// Outcome of `Pi.authenticate`.
@immutable
class PiAuthOutcome {
  const PiAuthOutcome({
    required this.uid,
    required this.username,
    required this.accessToken,
    required this.kycVerified,
  });

  /// App-scoped Pi user identifier.
  final String uid;

  /// Pi username (requires the `username` scope).
  final String username;

  /// Access token — for display logic only; the backend must verify via
  /// `GET https://api.minepi.com/v2/me` before trusting identity claims.
  final String accessToken;

  /// True when the Pi account is KYC-verified (when the SDK exposes it).
  final bool kycVerified;
}

/// A parsed Pi `PaymentDTO` (kept for diagnostics & recovery flows).
@immutable
class PiPaymentRecord {
  const PiPaymentRecord({
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

  factory PiPaymentRecord.fromData(PiPaymentDtoData data) => PiPaymentRecord(
        identifier: data.identifier,
        userUid: data.userUid,
        amount: data.amount,
        memo: data.memo,
        metadata: data.metadata,
        txid: data.txid,
        developerApproved: data.developerApproved,
        transactionVerified: data.transactionVerified,
        developerCompleted: data.developerCompleted,
        cancelled: data.cancelled,
        userCancelled: data.userCancelled,
        network: data.network,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'identifier': identifier,
        'user_uid': userUid,
        'amount': amount,
        'memo': memo,
        'metadata': metadata,
        'txid': txid,
        'status': <String, Object?>{
          'developer_approved': developerApproved,
          'transaction_verified': transactionVerified,
          'developer_completed': developerCompleted,
          'cancelled': cancelled,
          'user_cancelled': userCancelled,
        },
        'network': network,
      };
}

/// Live status of an in-flight Pi payment, surfaced to the UI.
enum PiPaymentPhase {
  idle,
  awaitingUser, // Pi overlay open — user reviews & submits the transaction
  readyForApproval, // onReadyForServerApproval fired
  readyForCompletion, // onReadyForServerCompletion fired (txid received)
  completing, // server-side completion webhook in flight
  completed,
  cancelled,
  error,
}

@immutable
class PiPaymentState {
  const PiPaymentState({
    this.phase = PiPaymentPhase.idle,
    this.paymentId,
    this.txid,
    this.error,
    this.record,
  });

  final PiPaymentPhase phase;
  final String? paymentId;
  final String? txid;
  final String? error;
  final PiPaymentRecord? record;

  PiPaymentState copyWith({
    PiPaymentPhase? phase,
    String? paymentId,
    String? txid,
    String? error,
    PiPaymentRecord? record,
    bool clearError = false,
  }) =>
      PiPaymentState(
        phase: phase ?? this.phase,
        paymentId: paymentId ?? this.paymentId,
        txid: txid ?? this.txid,
        error: clearError ? null : (error ?? this.error),
        record: record ?? this.record,
      );
}

/// Dart-facing facade for the Pi SDK.
class PiService {
  PiService({this.onIncompletePayment, PiSdkApi? sdk})
      : _sdkOverride = sdk;

  /// Optional injection point (tests / alternative implementations).
  final PiSdkApi? _sdkOverride;

  /// Called when `authenticate` (or a new payment) surfaces an unfinished
  /// payment. The default implementation forwards it to the backend for
  /// server-side completion.
  final void Function(PiPaymentRecord payment)? onIncompletePayment;

  bool _initialized = false;
  PiAuthOutcome? _lastAuth;

  bool get isSdkAvailable => _resolveSdk().isAvailable();
  PiAuthOutcome? get lastAuth => _lastAuth;

  PiSdkApi _resolveSdk() => _sdkOverride ?? piSdk;

  /// `Pi.init({ version, sandbox })` — idempotent and failure-tolerant.
  Future<bool> init() async {
    if (_initialized) return true;
    final ok = _resolveSdk().init(
      version: PiConfig.current.sdkVersion,
      sandbox: PiConfig.current.sandbox,
    );
    _initialized = ok;
    debugPrint('[Pi] init ${ok ? 'ok' : 'unavailable'} '
        '(version=${PiConfig.current.sdkVersion}, '
        'sandbox=${PiConfig.current.sandbox})');
    return ok;
  }

  /// Runs the native Pi authentication flow.
  Future<PiAuthOutcome> authenticate() async {
    if (!isSdkAvailable) {
      throw PiBridgeException(
          'Pi SDK unavailable. Open The Radar inside the Pi Browser.');
    }
    if (!_initialized) {
      final ok = await init();
      if (!ok) throw PiBridgeException('Pi.init() failed.');
    }

    try {
      final result = await _resolveSdk().authenticate(
        scopes: PiConfig.current.scopes,
        onIncompletePaymentFound: (dto) {
          final record = PiPaymentRecord.fromData(dto);
          debugPrint('[Pi] incomplete payment found: ${record.identifier}');
          final handler = onIncompletePayment ?? _defaultIncompleteHandler;
          handler(record);
        },
      );
      final outcome = PiAuthOutcome(
        uid: result.uid,
        username: result.username,
        accessToken: result.accessToken,
        kycVerified: result.kycApproved ?? false,
      );
      _lastAuth = outcome;
      return outcome;
    } on PiBridgeException {
      rethrow;
    } catch (e) {
      throw PiBridgeException('Pi.authenticate failed', cause: e);
    }
  }

  /// Starts a U2A payment. Returns a [Stream] of [PiPaymentState] updates
  /// mirroring the SDK callbacks.
  Stream<PiPaymentState> createPayment({
    required double amount,
    required String memo,
    required Map<String, Object?> metadata,
  }) {
    final controller = StreamController<PiPaymentState>.broadcast();
    var state = PiPaymentState();

    void emit(PiPaymentState next) {
      state = next;
      if (!controller.isClosed) controller.add(next);
    }

    if (!isSdkAvailable || !_initialized) {
      emit(const PiPaymentState(
        phase: PiPaymentPhase.error,
        error: 'Pi SDK unavailable — payments require the Pi Browser.',
      ));
      return controller.stream..listen(null, onDone: controller.close);
    }

    void onReadyForServerApproval(String paymentId) {
      debugPrint('[Pi] ready for server approval: $paymentId');
      emit(state.copyWith(
          phase: PiPaymentPhase.readyForApproval, paymentId: paymentId));
      _notifyBackendApproval(paymentId);
    }

    void onReadyForServerCompletion(String paymentId, String txid) {
      debugPrint('[Pi] ready for server completion: $paymentId txid=$txid');
      emit(state.copyWith(
        phase: PiPaymentPhase.readyForCompletion,
        paymentId: paymentId,
        txid: txid,
      ));
      _notifyBackendCompletion(paymentId, txid).then((record) {
        if (!controller.isClosed) {
          emit(state.copyWith(
            phase: PiPaymentPhase.completed,
            record: record ?? state.record,
          ));
          controller.close();
        }
      }).catchError((Object e) {
        debugPrint('[Pi] completion webhook failed: $e');
        if (!controller.isClosed) {
          emit(state.copyWith(
            phase: PiPaymentPhase.completing,
            error: 'Completion webhook failed — backend will retry.',
          ));
          controller.close();
        }
      });
    }

    void onCancel(String paymentId) {
      debugPrint('[Pi] payment cancelled: $paymentId');
      emit(state.copyWith(
          phase: PiPaymentPhase.cancelled,
          paymentId: paymentId,
          clearError: true));
      controller.close();
    }

    void onError(String message, PiPaymentDtoData? payment) {
      final record =
          payment == null ? null : PiPaymentRecord.fromData(payment);
      debugPrint('[Pi] payment error: $message (${record?.identifier})');
      emit(PiPaymentState(
        phase: PiPaymentPhase.error,
        paymentId: record?.identifier ?? state.paymentId,
        error: message,
        record: record,
      ));
      controller.close();
    }

    _resolveSdk().createPayment(
      amount: amount,
      memo: memo,
      metadata: metadata,
      callbacks: PiPaymentCallbacks(
        onReadyForServerApproval: onReadyForServerApproval,
        onReadyForServerCompletion: onReadyForServerCompletion,
        onCancel: onCancel,
        onError: onError,
      ),
    );

    emit(const PiPaymentState(phase: PiPaymentPhase.awaitingUser));
    return controller.stream;
  }

  Future<void> _notifyBackendApproval(String paymentId) async {
    try {
      await SupabaseConfig.functions
          .invoke('pi-payment-approve', body: {'paymentId': paymentId});
    } catch (e) {
      debugPrint('[Pi] approval webhook failed (backend will retry): $e');
    }
  }

  Future<PiPaymentRecord?> _notifyBackendCompletion(
      String paymentId, String txid) async {
    try {
      final res = await SupabaseConfig.functions.invoke(
        'pi-payment-complete',
        body: {'paymentId': paymentId, 'txid': txid},
      );
      final data = res.data;
      if (data is Map && data['payment'] != null && data['payment'] is Map) {
        final p = data['payment'] as Map;
        final tx = p['transaction'];
        return PiPaymentRecord(
          identifier: (p['identifier'] ?? paymentId).toString(),
          userUid: (p['user_uid'] ?? '').toString(),
          amount: (p['amount'] as num?)?.toDouble() ?? 0,
          memo: (p['memo'] ?? '').toString(),
          txid: tx is Map ? ((tx['txid'] ?? txid)).toString() : txid,
        );
      }
    } catch (e) {
      debugPrint('[Pi] completion webhook failed: $e');
    }
    return null;
  }

  void _defaultIncompleteHandler(PiPaymentRecord payment) {
    unawaited(() async {
      try {
        await SupabaseConfig.functions.invoke(
          'pi-payment-complete',
          body: {
            'paymentId': payment.identifier,
            if (payment.txid != null) 'txid': payment.txid,
            'incomplete': true,
          },
        );
      } catch (e) {
        debugPrint('[Pi] failed to recover incomplete payment: $e');
      }
    }());
  }
}
