import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/radar_repository.dart';
import '../models/enums.dart';
import '../models/pi_payment.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';
import '../pi/pi_service.dart';
import 'auth_controller.dart';

/// Live radar events — initial fetch + Supabase realtime updates.
final radarEventsProvider =
    AsyncNotifierProvider<RadarEventsController, List<RadarEvent>>(
        RadarEventsController.new);

class RadarEventsController extends AsyncNotifier<List<RadarEvent>> {
  RealtimeChannel? _channel;
  Timer? _refreshTimer;

  @override
  Future<List<RadarEvent>> build() async {
    final repo = RadarRepository.instance;
    // Initial snapshot.
    final events = await repo.fetchEvents();

    // Realtime subscription (no-op in demo mode).
    ref.onDispose(() {
      unawaited(repo.unsubscribe(_channel));
      _refreshTimer?.cancel();
    });
    _channel = repo.subscribeEvents((list) {
      if (list.isNotEmpty) state = AsyncData(list);
    });

    // Periodic re-evaluation so isLive/isBoosted flags stay fresh.
    _refreshTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => unawaited(repo.fetchEvents().then(
              (list) {
                if (list.isNotEmpty) state = AsyncData(list);
              },
              onError: (Object e) {},
            )));

    return events;
  }

  Future<bool> createEvent(RadarEvent event) async {
    final ok = await RadarRepository.instance.upsertEvent(event);
    if (ok) {
      ref.invalidateSelf();
    }
    return ok;
  }
}

/// All profiles (used for the directory & map host chips).
final profilesProvider = AsyncNotifierProvider<ProfilesController,
    List<UserProfile>>(ProfilesController.new);

class ProfilesController extends AsyncNotifier<List<UserProfile>> {
  RealtimeChannel? _channel;

  @override
  Future<List<UserProfile>> build() async {
    final repo = RadarRepository.instance;
    final profiles = await repo.fetchProfiles();
    ref.onDispose(() => unawaited(repo.unsubscribe(_channel)));
    _channel = repo.subscribeProfiles((list) {
      if (list.isNotEmpty) state = AsyncData(list);
    });
    return profiles;
  }
}

/// Directory filters.
class ProfileFilter {
  const ProfileFilter({
    this.role,
    this.query = '',
    this.minCredibility = 0,
  });

  final UserRole? role;
  final String query;
  final double minCredibility;

  ProfileFilter copyWith({
    UserRole? role,
    bool clearRole = false,
    String? query,
    double? minCredibility,
  }) =>
      ProfileFilter(
        role: clearRole ? null : (role ?? this.role),
        query: query ?? this.query,
        minCredibility: minCredibility ?? this.minCredibility,
      );
}

final profileFilterProvider =
    NotifierProvider<ProfileFilterController, ProfileFilter>(
        ProfileFilterController.new);

class ProfileFilterController extends Notifier<ProfileFilter> {
  @override
  ProfileFilter build() => const ProfileFilter();

  void setRole(UserRole? role) =>
      state = state.copyWith(role: role, clearRole: true);

  void setQuery(String query) => state = state.copyWith(query: query);

  void setMinCredibility(double v) =>
      state = state.copyWith(minCredibility: v);
}

/// Filtered, sorted view of the directory.
final filteredProfilesProvider = FutureProvider<List<UserProfile>>((ref) async {
  final filter = ref.watch(profileFilterProvider);
  return RadarRepository.instance.searchProfiles(
    role: filter.role,
    query: filter.query.isEmpty ? null : filter.query,
    minCredibility:
        filter.minCredibility > 0 ? filter.minCredibility : null,
  );
});

/// Radar map filters.
class RadarFilter {
  const RadarFilter({
    this.types = const {},
    this.onlyBoosted = false,
    this.showMinorProtected = true,
    this.query = '',
  });

  final Set<RadarEventType> types;
  final bool onlyBoosted;
  final bool showMinorProtected;
  final String query;

  RadarFilter copyWith({
    Set<RadarEventType>? types,
    bool clearTypes = false,
    bool? onlyBoosted,
    bool? showMinorProtected,
    String? query,
  }) =>
      RadarFilter(
        types: clearTypes ? const {} : (types ?? this.types),
        onlyBoosted: onlyBoosted ?? this.onlyBoosted,
        showMinorProtected: showMinorProtected ?? this.showMinorProtected,
        query: query ?? this.query,
      );
}

final radarFilterProvider =
    NotifierProvider<RadarFilterController, RadarFilter>(
        RadarFilterController.new);

class RadarFilterController extends Notifier<RadarFilter> {
  @override
  RadarFilter build() => const RadarFilter();

  void toggleType(RadarEventType type) {
    final next = Set<RadarEventType>.of(state.types);
    if (!next.remove(type)) next.add(type);
    state = state.copyWith(types: next);
  }

  void setOnlyBoosted(bool v) => state = state.copyWith(onlyBoosted: v);

  void setShowMinorProtected(bool v) =>
      state = state.copyWith(showMinorProtected: v);

  void setQuery(String q) => state = state.copyWith(query: q);
}

final filteredEventsProvider = Provider<List<RadarEvent>>((ref) {
  final events = ref.watch(radarEventsProvider).value ?? const [];
  final filter = ref.watch(radarFilterProvider);
  return events.where((e) {
    if (filter.types.isNotEmpty && !filter.types.contains(e.type)) return false;
    if (filter.onlyBoosted && !e.isBoosted) return false;
    if (!filter.showMinorProtected && e.isMinorProtected) return false;
    if (filter.query.isNotEmpty) {
      final q = filter.query.toLowerCase();
      final hay = '${e.title} ${e.hostName} ${e.areaName ?? ''} '
              '${e.description ?? ''}'
          .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList()
    ..sort((a, b) {
      // Boosted first, then soonest start.
      final boost = (b.isBoosted ? 1 : 0).compareTo(a.isBoosted ? 1 : 0);
      if (boost != 0) return boost;
      return a.startsAt.compareTo(b.startsAt);
    });
});

/// Pi payment lifecycle state for the UI.
class PaymentFlowState {
  const PaymentFlowState({
    this.phase = PiPaymentPhase.idle,
    this.message,
    this.paymentId,
    this.txid,
    this.history = const [],
  });

  final PiPaymentPhase phase;
  final String? message;
  final String? paymentId;
  final String? txid;
  final List<PiPayment> history;

  PaymentFlowState copyWith({
    PiPaymentPhase? phase,
    String? message,
    String? paymentId,
    String? txid,
    List<PiPayment>? history,
    bool clearMessage = false,
  }) =>
      PaymentFlowState(
        phase: phase ?? this.phase,
        message: clearMessage ? null : (message ?? this.message),
        paymentId: paymentId ?? this.paymentId,
        txid: txid ?? this.txid,
        history: history ?? this.history,
      );
}

final paymentFlowProvider =
    NotifierProvider<PaymentFlowController, PaymentFlowState>(
        PaymentFlowController.new);

class PaymentFlowController extends Notifier<PaymentFlowState> {
  StreamSubscription<PiPaymentState>? _sub;

  @override
  PaymentFlowState build() => const PaymentFlowState();

  /// Launches a Pi payment for a Radar product.
  Future<void> pay({
    required double amount,
    required String memo,
    required String product,
    Map<String, Object?> metadata = const {},
  }) async {
    final auth = ref.read(authProvider).value;
    final pi = ref.read(authProvider.notifier).pi;
    if (pi == null || !pi.isSdkAvailable) {
      state = state.copyWith(
        phase: PiPaymentPhase.error,
        message: 'Pi payments require the Pi Browser. Demo mode: no charge.',
      );
      return;
    }

    state = state.copyWith(
      phase: PiPaymentPhase.awaitingUser,
      message: null,
      paymentId: null,
      txid: null,
    );

    final session = auth is AuthSignedIn ? auth.session : null;
    final enrichedMetadata = <String, Object?>{
      'product': product,
      'pi_uid': session?.piUid ?? 'unknown',
      'username': session?.username ?? 'unknown',
      ...metadata,
    };

    _sub?.cancel();
    _sub = pi.createPayment(amount: amount, memo: memo, metadata: enrichedMetadata).listen(
      (ps) {
        switch (ps.phase) {
          case PiPaymentPhase.awaitingUser:
          case PiPaymentPhase.readyForApproval:
          case PiPaymentPhase.readyForCompletion:
          case PiPaymentPhase.completing:
            state = state.copyWith(
              phase: ps.phase,
              paymentId: ps.paymentId,
              txid: ps.txid,
              message: null,
            );
            break;
          case PiPaymentPhase.completed:
            state = state.copyWith(
              phase: ps.phase,
              paymentId: ps.paymentId,
              txid: ps.txid,
              message: 'Payment confirmed — thank you!',
              history: [
                PiPayment(
                  id: ps.paymentId ?? 'unknown',
                  piUid: session?.piUid ?? 'unknown',
                  amount: amount,
                  memo: memo,
                  product: product,
                  status: 'completed',
                  createdAt: DateTime.now(),
                  txid: ps.txid,
                  metadata: enrichedMetadata,
                ),
                ...state.history,
              ],
            );
            break;
          case PiPaymentPhase.cancelled:
            state = state.copyWith(
              phase: ps.phase,
              message: 'Payment cancelled.',
            );
            break;
          case PiPaymentPhase.error:
            state = state.copyWith(
              phase: ps.phase,
              message: ps.error ?? 'Payment failed.',
            );
            break;
          case PiPaymentPhase.idle:
            break;
        }
      },
      onError: (Object e) {
        state = state.copyWith(
          phase: PiPaymentPhase.error,
          message: 'Unexpected error: $e',
        );
      },
    );
  }

  void dismiss() {
    state = state.copyWith(phase: PiPaymentPhase.idle, message: null);
  }
}
