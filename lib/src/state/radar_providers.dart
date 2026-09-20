import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../data/radar_repository.dart';
import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/feed_post.dart' show FeedPost, FeedPostKind, distanceKm;
import '../models/guardian_link.dart';
import '../models/pi_payment.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
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
    this.ageBracket,
    this.position,
    this.verifiedHostsOnly = false,
    this.radiusKm,
    this.viewerLat,
    this.viewerLon,
  });

  final Set<RadarEventType> types;
  final bool onlyBoosted;
  final bool showMinorProtected;
  final String query;

  /// Age bracket the event must overlap (e.g. U15 = 12..15).
  final AgeBracket? ageBracket;

  /// Position the event is recruiting (matches positions_required).
  final String? position;

  /// Only events hosted by verified profiles (scout/club/academy + KYC or
  /// high credibility — same rule as the badge in the directory).
  final bool verifiedHostsOnly;

  /// Radius filter around the viewer's position (km). Null = unlimited.
  final double? radiusKm;
  final double? viewerLat;
  final double? viewerLon;

  RadarFilter copyWith({
    Set<RadarEventType>? types,
    bool clearTypes = false,
    bool? onlyBoosted,
    bool? showMinorProtected,
    String? query,
    AgeBracket? ageBracket,
    bool clearAgeBracket = false,
    String? position,
    bool clearPosition = false,
    bool? verifiedHostsOnly,
    double? radiusKm,
    bool clearRadius = false,
    double? viewerLat,
    double? viewerLon,
  }) =>
      RadarFilter(
        types: clearTypes ? const {} : (types ?? this.types),
        onlyBoosted: onlyBoosted ?? this.onlyBoosted,
        showMinorProtected: showMinorProtected ?? this.showMinorProtected,
        query: query ?? this.query,
        ageBracket:
            clearAgeBracket ? null : (ageBracket ?? this.ageBracket),
        position: clearPosition ? null : (position ?? this.position),
        verifiedHostsOnly: verifiedHostsOnly ?? this.verifiedHostsOnly,
        radiusKm: clearRadius ? null : (radiusKm ?? this.radiusKm),
        viewerLat: viewerLat ?? this.viewerLat,
        viewerLon: viewerLon ?? this.viewerLon,
      );
}

/// Age brackets used across the platform (mirrors safeguarding bands).
enum AgeBracket {
  u13('U13', 6, 13),
  u15('U15', 13, 15),
  u17('U17', 15, 17),
  u20('U20', 17, 20),
  open('Open age', 18, 99);

  const AgeBracket(this.label, this.min, this.max);
  final String label;
  final int min;
  final int max;

  /// True when an event's [min,max] age window overlaps this bracket.
  bool matches(int? eventMin, int? eventMax) {
    final lo = eventMin ?? 0;
    final hi = eventMax ?? 99;
    return lo <= max && hi >= min;
  }
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

  void setAgeBracket(AgeBracket? b) =>
      state = state.copyWith(ageBracket: b, clearAgeBracket: true);

  void setPosition(String? p) =>
      state = state.copyWith(position: p, clearPosition: true);

  void setVerifiedHostsOnly(bool v) =>
      state = state.copyWith(verifiedHostsOnly: v);

  void setRadius(double? km, {double? viewerLat, double? viewerLon}) =>
      state = state.copyWith(
        radiusKm: km,
        clearRadius: km == null,
        viewerLat: viewerLat,
        viewerLon: viewerLon,
      );
}

final filteredEventsProvider = Provider<List<RadarEvent>>((ref) {
  final events = ref.watch(radarEventsProvider).value ?? const [];
  final filter = ref.watch(radarFilterProvider);
  final profiles = ref.watch(profilesProvider).value ?? const <UserProfile>[];

  // Verified-host set, resolved once per emission: scouts/clubs/academies
  // whose KYC is done or whose credibility is high.
  final verifiedHostIds = <String>{
    for (final p in profiles)
      if (p.isVerifiedRole && (p.kycVerified || p.credibilityScore >= 40)) p.id,
  };

  return events.where((e) {
    if (filter.types.isNotEmpty && !filter.types.contains(e.type)) return false;
    if (filter.onlyBoosted && !e.isBoosted) return false;
    if (!filter.showMinorProtected && e.isMinorProtected) return false;
    if (filter.ageBracket != null &&
        !filter.ageBracket!.matches(e.minAge, e.maxAge)) {
      return false;
    }
    if (filter.position != null && filter.position!.isNotEmpty) {
      if (!e.positionsRequired
          .any((p) => p.toLowerCase() == filter.position!.toLowerCase())) {
        return false;
      }
    }
    if (filter.verifiedHostsOnly && !verifiedHostIds.contains(e.hostProfileId)) {
      return false;
    }
    if (filter.radiusKm != null &&
        filter.viewerLat != null &&
        filter.viewerLon != null &&
        filter.radiusKm! > 0) {
      final d = distanceKm(
        lat1: filter.viewerLat!,
        lon1: filter.viewerLon!,
        lat2: e.latitude,
        lon2: e.longitude,
      );
      if (d > filter.radiusKm!) return false;
    }
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

/// Connection requests involving the signed-in user (sent + received).
final connectionsProvider =
    AsyncNotifierProvider<ConnectionsController, List<ConnectionRequest>>(
        ConnectionsController.new);

class ConnectionsController extends AsyncNotifier<List<ConnectionRequest>> {
  @override
  Future<List<ConnectionRequest>> build() async {
    final session = ref.watch(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return const [];
    return RadarRepository.instance.fetchConnections(profileId);
  }

  Future<void> refresh() async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return;
    final list =
        await RadarRepository.instance.fetchConnections(profileId);
    state = AsyncData(list);
  }

  /// Accept / decline a received request, or withdraw a sent one.
  Future<bool> respond(String requestId, ConnectionStatus status) async {
    final ok =
        await RadarRepository.instance.respondToConnection(requestId, status);
    if (ok) await refresh();
    return ok;
  }

  /// Whether [fromProfile] already has a pending request to [toProfile].
  Future<bool> hasPending(String fromProfile, String toProfile) {
    return RadarRepository.instance.hasPendingRequest(fromProfile, toProfile);
  }
}

/// Guardian links for the signed-in user (as minor and/or as guardian).
/// Refreshed after every action and when the session changes.
final guardianLinksProvider =
    AsyncNotifierProvider<GuardianLinksController, List<GuardianLink>>(
        GuardianLinksController.new);

class GuardianLinksController extends AsyncNotifier<List<GuardianLink>> {
  @override
  Future<List<GuardianLink>> build() async {
    final session = ref.watch(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return const [];
    return RadarRepository.instance.fetchGuardianLinks(profileId);
  }

  Future<bool> refresh() async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return false;
    final links =
        await RadarRepository.instance.fetchGuardianLinks(profileId);
    state = AsyncData(links);
    return true;
  }

  /// Minor invites a guardian by Pi username. Returns an error string on
  /// failure, or null on success.
  Future<String?> inviteGuardian(String username) async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return 'You must be signed in as the minor.';
    final guardian = await RadarRepository.instance
        .findGuardianByUsername(username);
    if (guardian == null) {
      return 'No guardian (parent) account found for "${username.trim()}".';
    }
    if (guardian.id == profileId) return 'You cannot invite yourself.';
    final ok = await RadarRepository.instance
        .createGuardianLink(profileId, guardian.id);
    if (!ok) return 'Could not send the invite — try again.';
    await refresh();
    unawaited(
        ref.read(consentAuditProvider.notifier).refresh());
    return null;
  }

  /// Guardian approves a pending link.
  Future<void> approveLink(String linkId) async {
    await RadarRepository.instance.respondToGuardianLink(linkId, 'active');
    await refresh();
    unawaited(ref.read(consentAuditProvider.notifier).refresh());
  }

  /// Guardian declines; minor may revoke their own pending link.
  Future<void> declineLink(String linkId) async {
    await RadarRepository.instance.respondToGuardianLink(linkId, 'declined');
    await refresh();
    unawaited(ref.read(consentAuditProvider.notifier).refresh());
  }

  Future<void> revokeLink(String linkId) async {
    await RadarRepository.instance.respondToGuardianLink(linkId, 'revoked');
    await refresh();
    unawaited(ref.read(consentAuditProvider.notifier).refresh());
  }

  Future<void> setConsent(
    String linkId, {
    bool? consentConnections,
    bool? consentEvents,
  }) async {
    await RadarRepository.instance.setGuardianConsent(
      linkId,
      consentConnections: consentConnections,
      consentEvents: consentEvents,
    );
    await refresh();
    unawaited(ref.read(consentAuditProvider.notifier).refresh());
  }
}

/// Consent status for an arbitrary profile (family-cached). Used by the
/// connection-request sheet for friendly pre-checks; the database trigger
/// remains the authoritative gate.
final consentStatusProvider =
    FutureProvider.autoDispose.family<MinorConsent, String>((ref, profileId) {
  return RadarRepository.instance.fetchConsentStatus(profileId);
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
            // Pull the fresh entitlement + receipt from the backend.
            unawaited(
                ref.read(entitlementsProvider.notifier).refresh());
            unawaited(ref.read(paymentLedgerProvider.notifier).refresh());
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

// ---------------------------------------------------------------------------
// Global search — saved filters & quick presets
// ---------------------------------------------------------------------------

/// A named, re-playable search configuration (scouting window shortcut).
class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.query,
  });

  final String id;
  final String name;
  final GlobalSearchQuery query;
}

/// The saved-search store. Session-scoped for now: presets survive
/// navigation and hot reload; cross-device persistence can later ride on
/// `auth.updateUser(data: ...)` app metadata.
final savedSearchesProvider =
    NotifierProvider<SavedSearchesController, List<SavedSearch>>(
        SavedSearchesController.new);

class SavedSearchesController extends Notifier<List<SavedSearch>> {
  @override
  List<SavedSearch> build() => const [];

  void save(String name, GlobalSearchQuery query) {
    state = [
      SavedSearch(
        id: 'saved-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        query: query,
      ),
      ...state,
    ];
  }

  void remove(String id) =>
      state = state.where((s) => s.id != id).toList();
}

/// A full global-search query spanning players and events.
class GlobalSearchQuery {
  const GlobalSearchQuery({
    this.text = '',
    this.positions = const {},
    this.ageBracket,
    this.country,
    this.city,
    this.dominantFoot,
    this.minCredibility = 0,
    this.eventTypes = const {},
    this.playersScope = true,
    this.eventsScope = true,
  });

  final String text;
  final Set<String> positions;
  final AgeBracket? ageBracket;
  final String? country;
  final String? city;
  final String? dominantFoot;
  final double minCredibility;
  final Set<RadarEventType> eventTypes;
  final bool playersScope;
  final bool eventsScope;

  bool get isEmpty =>
      text.isEmpty &&
      positions.isEmpty &&
      ageBracket == null &&
      country == null &&
      city == null &&
      dominantFoot == null &&
      minCredibility <= 0 &&
      eventTypes.isEmpty;

  GlobalSearchQuery copyWith({
    String? text,
    Set<String>? positions,
    bool clearPositions = false,
    AgeBracket? ageBracket,
    bool clearAgeBracket = false,
    String? country,
    bool clearCountry = false,
    String? city,
    bool clearCity = false,
    String? dominantFoot,
    bool clearDominantFoot = false,
    double? minCredibility,
    Set<RadarEventType>? eventTypes,
    bool clearEventTypes = false,
    bool? playersScope,
    bool? eventsScope,
  }) =>
      GlobalSearchQuery(
        text: text ?? this.text,
        positions: clearPositions ? const {} : (positions ?? this.positions),
        ageBracket:
            clearAgeBracket ? null : (ageBracket ?? this.ageBracket),
        country: clearCountry ? null : (country ?? this.country),
        city: clearCity ? null : (city ?? this.city),
        dominantFoot:
            clearDominantFoot ? null : (dominantFoot ?? this.dominantFoot),
        minCredibility: minCredibility ?? this.minCredibility,
        eventTypes:
            clearEventTypes ? const {} : (eventTypes ?? this.eventTypes),
        playersScope: playersScope ?? this.playersScope,
        eventsScope: eventsScope ?? this.eventsScope,
      );
}

/// Consent audit history for the signed-in user (minor and/or guardian).
/// Backed by the append-only `consent_audit_log` via the participant-
/// scoped `read_consent_audit` RPC; refreshed after every consent action.
final consentAuditProvider =
    AsyncNotifierProvider<ConsentAuditController, List<ConsentAuditEntry>>(
        ConsentAuditController.new);

class ConsentAuditController extends AsyncNotifier<List<ConsentAuditEntry>> {
  @override
  Future<List<ConsentAuditEntry>> build() async {
    final session = ref.watch(sessionProvider);
    if (session?.profileId == null) return const [];
    return RadarRepository.instance.fetchConsentAudit();
  }

  Future<void> refresh() async {
    final list = await RadarRepository.instance.fetchConsentAudit();
    state = AsyncData(list);
  }
}

/// The signed-in user's active boosts, entitlements and payment receipts.
/// Refreshed when the wallet tab opens and after any completed payment.
final entitlementsProvider =
    AsyncNotifierProvider<EntitlementsController, List<Entitlement>>(
        EntitlementsController.new);

class EntitlementsController
    extends AsyncNotifier<List<Entitlement>> {
  @override
  Future<List<Entitlement>> build() async {
    final session = ref.watch(sessionProvider);
    if (session?.profileId == null) return const [];
    return RadarRepository.instance.fetchMyEntitlements();
  }

  Future<void> refresh() async {
    final list = await RadarRepository.instance.fetchMyEntitlements();
    state = AsyncData(list);
  }
}

/// The signed-in user's payment ledger (own receipts only, via RLS).
final paymentLedgerProvider =
    AsyncNotifierProvider<PaymentLedgerController, List<PiPayment>>(
        PaymentLedgerController.new);

class PaymentLedgerController extends AsyncNotifier<List<PiPayment>> {
  @override
  Future<List<PiPayment>> build() async {
    final session = ref.watch(sessionProvider);
    if (session?.profileId == null) return const [];
    return RadarRepository.instance.fetchMyPayments();
  }

  Future<void> refresh() async {
    final list = await RadarRepository.instance.fetchMyPayments();
    state = AsyncData(list);
  }
}

// --------------------------------------------------------------- social feed

/// Social feed posts — latest first, refreshed on demand.
final feedPostsProvider =
    AsyncNotifierProvider<FeedPostsController, List<FeedPost>>(
        FeedPostsController.new);

class FeedPostsController extends AsyncNotifier<List<FeedPost>> {
  @override
  Future<List<FeedPost>> build() =>
      RadarRepository.instance.fetchFeedPosts();

  Future<void> refresh() async {
    final list = await RadarRepository.instance.fetchFeedPosts();
    if (list.isNotEmpty) state = AsyncData(list);
  }

  /// Publishes a post as the signed-in user; returns true on success.
  Future<bool> createPost({
    required FeedPostKind kind,
    required String body,
    String? mediaUrl,
    String? mediaPlatform,
    String? areaName,
    double? latitude,
    double? longitude,
  }) async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return false;
    final post = FeedPost(
      id: 'post-${DateTime.now().microsecondsSinceEpoch}',
      authorProfileId: profileId,
      authorName: session!.username,
      authorRole: session.role.name,
      kind: kind,
      body: body.trim(),
      createdAt: DateTime.now(),
      mediaUrl: (mediaUrl?.trim().isEmpty ?? true) ? null : mediaUrl!.trim(),
      mediaPlatform:
          (mediaPlatform?.trim().isEmpty ?? true) ? null : mediaPlatform!.trim(),
      areaName: (areaName?.trim().isEmpty ?? true) ? null : areaName!.trim(),
      latitude: latitude,
      longitude: longitude,
    );
    final ok = await RadarRepository.instance.createFeedPost(post);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> deletePost(String postId) async {
    final ok = await RadarRepository.instance.deleteFeedPost(postId);
    if (ok) await refresh();
    return ok;
  }
}

// ------------------------------------------------------------- stream bounties

/// Pi-backed "Talent Watcher" bounties: scouts post escrowed Pi for live
/// tactical streams; local videographers accept, stream and get released
/// the escrow on broadcast completion.
final streamBountiesProvider =
    AsyncNotifierProvider<StreamBountiesController, List<StreamBounty>>(
        StreamBountiesController.new);

class StreamBountiesController extends AsyncNotifier<List<StreamBounty>> {
  @override
  Future<List<StreamBounty>> build() =>
      RadarRepository.instance.fetchStreamBounties();

  Future<void> refresh() async {
    final list = await RadarRepository.instance.fetchStreamBounties();
    if (list.isNotEmpty) state = AsyncData(list);
  }

  /// Creates the bounty row and returns its id — the caller immediately
  /// starts the Pi funding payment bound to it (reference_id).
  Future<String?> postBounty({
    required String title,
    required String brief,
    required String areaName,
    String? venueName,
    required double amountPi,
    required int durationMinutes,
    DateTime? kickoffAt,
  }) async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return null;
    final draft = StreamBounty(
      id: 'bounty-${DateTime.now().microsecondsSinceEpoch}',
      posterProfileId: profileId,
      posterName: session!.username,
      title: title.trim(),
      brief: brief.trim(),
      areaName: areaName.trim(),
      venueName: venueName?.trim().isEmpty == true ? null : venueName!.trim(),
      latitude: session.viewerLatitude,
      longitude: session.viewerLongitude,
      amountPi: amountPi,
      durationMinutes: durationMinutes,
      kickoffAt: kickoffAt,
      status: 'open',
      createdAt: DateTime.now(),
    );
    final created =
        await RadarRepository.instance.createStreamBounty(draft);
    await refresh();
    return created?.id;
  }

  /// Funds a bounty: opens the Pi U2A payment with product
  /// `stream_bounty_funding` and reference_id = bounty id. The completion
  /// webhook flips the bounty to `funded` (escrow held by the platform).
  void fundBounty(String bountyId, double amountPi, String title) {
    ref.read(paymentFlowProvider.notifier).pay(
          amount: amountPi,
          memo: 'The Radar — bounty escrow: $title',
          product: 'stream_bounty_funding',
          metadata: {
            'sku': 'stream_bounty_funding',
            'price_pi': amountPi,
            'reference_id': bountyId,
          },
        );
  }

  /// A local streamer accepts a funded bounty (claims the gig).
  Future<bool> acceptBounty(String bountyId) async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return false;
    final ok = await RadarRepository.instance.updateBounty(bountyId, {
      'status': 'accepted',
      'streamer_profile_id': profileId,
      'streamer_name': session!.username,
    });
    await refresh();
    return ok;
  }

  /// Streamer goes live / posts their stream link.
  Future<bool> goLive(String bountyId, String streamUrl) async {
    final ok = await RadarRepository.instance.updateBounty(bountyId, {
      'status': 'live',
      if (streamUrl.trim().isNotEmpty) 'stream_url': streamUrl.trim(),
    });
    await refresh();
    return ok;
  }

  /// Streamer marks the broadcast finished (watched minutes logged).
  Future<bool> finishBroadcast(String bountyId, int minutes) async {
    final ok = await RadarRepository.instance.updateBounty(bountyId, {
      'watched_minutes': minutes,
    });
    await refresh();
    return ok;
  }

  /// Poster-only: releases the escrow to the streamer via the
  /// SECURITY DEFINER `release_bounty` RPC (the "smart contract" payout).
  Future<bool> releaseEscrow(String bountyId) async {
    final ok = await RadarRepository.instance.releaseBounty(bountyId);
    await refresh();
    return ok;
  }

  /// Poster-only: cancels an unfunded (or disputed) bounty. Escrowed Pi for
  /// funded bounties is refunded through the disputed path instead.
  Future<bool> cancelBounty(String bountyId) async {
    final ok =
        await RadarRepository.instance.updateBounty(bountyId, {
      'status': 'cancelled',
    });
    await refresh();
    return ok;
  }
}
