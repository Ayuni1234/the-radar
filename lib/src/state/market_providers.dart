// Riverpod state for The PitchMarket — feed filters, merchant shop +
// inventory, and the Pi fee-split checkout flow.
//
// The checkout binds a normal U2A Pi payment (product =
// `market_gear_purchase`, reference_id = listing id) to the
// `market-checkout` edge function, which verifies the payment, splits the
// fee (merchant pi_uid ← core amount, treasury ← maintenance cut) and
// decrements stock server-side.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/market_repository.dart';
import '../models/market.dart';
import '../models/market_order.dart';
import '../models/market_sales.dart';
import '../pi/pi_service.dart';
import '../supabase/supabase_config.dart';
import 'auth_controller.dart';

// ----------------------------------------------------------------- catalog

/// All active gear listings (public marketplace feed).
final marketListingsProvider =
    AsyncNotifierProvider<MarketListingsController, List<MarketListing>>(
        MarketListingsController.new);

class MarketListingsController
    extends AsyncNotifier<List<MarketListing>> {
  @override
  Future<List<MarketListing>> build() =>
      MarketRepository.instance.fetchListings();

  Future<void> refresh() async {
    state = AsyncData(await MarketRepository.instance.fetchListings());
  }
}

/// All merchant shops (shop headers on the feed & detail views).
final marketShopsProvider =
    AsyncNotifierProvider<MarketShopsController, List<MarketShop>>(
        MarketShopsController.new);

class MarketShopsController extends AsyncNotifier<List<MarketShop>> {
  @override
  Future<List<MarketShop>> build() => MarketRepository.instance.fetchShops();

  Future<void> refresh() async {
    state = AsyncData(await MarketRepository.instance.fetchShops());
  }
}

// ----------------------------------------------------------------- filters

/// Feed filters: category, free-text search and Pi price range.
class MarketFilter {
  const MarketFilter({
    this.category,
    this.query = '',
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
  });

  final String? category;
  final String query;

  /// Inclusive Pi price bounds (null = unbounded).
  final double? minPrice;
  final double? maxPrice;
  final bool inStockOnly;

  bool get hasActiveFilters =>
      category != null ||
      query.isNotEmpty ||
      minPrice != null ||
      maxPrice != null ||
      inStockOnly;

  MarketFilter copyWith({
    String? category,
    bool clearCategory = false,
    String? query,
    double? minPrice,
    bool clearMinPrice = false,
    double? maxPrice,
    bool clearMaxPrice = false,
    bool? inStockOnly,
  }) =>
      MarketFilter(
        category: clearCategory ? null : (category ?? this.category),
        query: query ?? this.query,
        minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
        maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
        inStockOnly: inStockOnly ?? this.inStockOnly,
      );
}

final marketFilterProvider =
    NotifierProvider<MarketFilterController, MarketFilter>(
        MarketFilterController.new);

class MarketFilterController extends Notifier<MarketFilter> {
  @override
  MarketFilter build() => const MarketFilter();

  void setCategory(String? category) =>
      state = state.copyWith(category: category, clearCategory: true);

  void setQuery(String q) => state = state.copyWith(query: q);

  void setPriceRange({double? min, double? max}) => state = state.copyWith(
        minPrice: min,
        clearMinPrice: min == null,
        maxPrice: max,
        clearMaxPrice: max == null,
      );

  void setInStockOnly(bool v) => state = state.copyWith(inStockOnly: v);

  void reset() => state = const MarketFilter();
}

/// Filtered feed view.
final filteredMarketListingsProvider = Provider<List<MarketListing>>((ref) {
  final listings = ref.watch(marketListingsProvider).value ?? const [];
  final f = ref.watch(marketFilterProvider);

  return listings.where((l) {
    if (!l.inStock) return false;
    if (f.inStockOnly && l.stockQuantity <= 1) return false;
    if (f.category != null && l.category != f.category) return false;
    if (f.minPrice != null && l.pricePi < f.minPrice!) return false;
    if (f.maxPrice != null && l.pricePi > f.maxPrice!) return false;
    if (!MarketListing.matchesQuery(l, f.query)) return false;
    return true;
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

// ----------------------------------------------------------------- my shop

/// The signed-in merchant's shop (null = not yet registered).
final myMarketShopProvider =
    AsyncNotifierProvider<MyMarketShopController, MarketShop?>(
        MyMarketShopController.new);

class MyMarketShopController extends AsyncNotifier<MarketShop?> {
  @override
  Future<MarketShop?> build() async {
    final session = ref.watch(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return null;
    return MarketRepository.instance.fetchMyShop(profileId);
  }

  Future<void> refresh() async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    state = AsyncData(
        profileId == null ? null : await MarketRepository.instance.fetchMyShop(profileId));
  }

  /// Registers or updates the storefront. Returns null on success or a
  /// user-facing error message.
  Future<String?> saveShop({
    required String shopName,
    required String piUid,
    required String locationArea,
    String? description,
  }) async {
    final session = ref.read(sessionProvider);
    final profileId = session?.profileId;
    if (profileId == null) return 'You must be signed in to register a shop.';
    final name = shopName.trim();
    final uid = piUid.trim();
    final area = locationArea.trim();
    if (name.length < 3) return 'Shop name needs at least 3 characters.';
    if (uid.isEmpty) {
      return 'Add your verified Pi uid so sales pay out to your wallet.';
    }
    if (area.isEmpty) return 'Add your pickup / delivery area.';

    final existing = state.value;
    final saved = await MarketRepository.instance.upsertMyShop(
      profileId,
      MarketShop(
        id: existing?.id ?? '',
        ownerId: profileId,
        shopName: name,
        description: description?.trim().isEmpty ?? true
            ? null
            : description!.trim(),
        piUid: uid,
        locationArea: area,
        isVerified: existing?.isVerified ?? false,
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
    if (saved == null) {
      return 'Could not save your shop — try again in a moment.';
    }
    state = AsyncData(saved);
    unawaited(ref.read(marketShopsProvider.notifier).refresh());
    return null;
  }
}

/// The signed-in merchant's inventory (all listings, incl. inactive).
final myListingsProvider =
    AsyncNotifierProvider<MyListingsController, List<MarketListing>>(
        MyListingsController.new);

class MyListingsController extends AsyncNotifier<List<MarketListing>> {
  @override
  Future<List<MarketListing>> build() async {
    final shop = ref.watch(myMarketShopProvider).value;
    if (shop == null || shop.id.isEmpty) return const [];
    return MarketRepository.instance.fetchMyListings(shop.id);
  }

  Future<void> refresh() async {
    final shop = ref.read(myMarketShopProvider).value;
    if (shop == null || shop.id.isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = AsyncData(await MarketRepository.instance.fetchMyListings(shop.id));
  }

  /// Publishes a new gear item. Returns null on success or an error string.
  Future<String?> addListing({
    required String title,
    required String category,
    required double pricePi,
    required String condition,
    required int stockQuantity,
    List<String> mediaUrls = const [],
  }) async {
    final shop = ref.read(myMarketShopProvider).value;
    if (shop == null || shop.id.isEmpty) {
      return 'Register your shop before adding gear.';
    }
    final t = title.trim();
    if (t.length < 3) return 'Give the item a clear title.';
    if (pricePi <= 0) return 'Set a price above 0 π.';
    if (stockQuantity < 1) return 'Stock must be at least 1.';

    final created = await MarketRepository.instance.createListing(
      MarketListing(
        id: '',
        shopId: shop.id,
        title: t,
        category: category,
        pricePi: pricePi,
        condition: condition,
        stockQuantity: stockQuantity,
        mediaUrls: mediaUrls,
        isActive: true,
        createdAt: DateTime.now(),
      ),
    );
    if (created == null) return 'Could not publish the listing — try again.';
    await refresh();
    unawaited(ref.read(marketListingsProvider.notifier).refresh());
    return null;
  }

  Future<bool> setListingActive(String id, bool active) async {
    final ok =
        await MarketRepository.instance.updateListing(id, {'is_active': active});
    if (ok) await refresh();
    return ok;
  }

  Future<bool> adjustStock(String id, int delta) async {
    final current = state.value?.where((l) => l.id == id).firstOrNull;
    if (current == null) return false;
    final next = (current.stockQuantity + delta).clamp(0, 9999);
    final ok = await MarketRepository.instance
        .updateListing(id, {'stock_quantity': next});
    if (ok) await refresh();
    return ok;
  }

  Future<bool> deleteListing(String id) async {
    final ok = await MarketRepository.instance.deleteListing(id);
    if (ok) {
      await refresh();
      unawaited(ref.read(marketListingsProvider.notifier).refresh());
    }
    return ok;
  }
}

// ------------------------------------------------------------- my orders

/// The signed-in buyer's completed PitchMarket purchases with the fee-split
/// breakdown, newest first. Refreshed after every checkout settle.
final myMarketOrdersProvider =
    AsyncNotifierProvider<MyMarketOrdersController, List<MarketOrder>>(
        MyMarketOrdersController.new);

class MyMarketOrdersController
    extends AsyncNotifier<List<MarketOrder>> {
  @override
  Future<List<MarketOrder>> build() async {
    final session = ref.watch(sessionProvider);
    if (session?.profileId == null) return const [];
    return MarketRepository.instance.fetchMyMarketOrders();
  }

  Future<void> refresh() async {
    final session = ref.read(sessionProvider);
    if (session?.profileId == null) {
      state = const AsyncData([]);
      return;
    }
    state = AsyncData(await MarketRepository.instance.fetchMyMarketOrders());
  }
}

// -------------------------------------------------------------- my sales

/// The signed-in merchant's aggregated sales economics (units sold, gross Pi,
/// fees paid, net payout), rebuilt from their own A2U payout receipts.
final mySalesSummaryProvider =
    AsyncNotifierProvider<MySalesSummaryController, MarketSalesSummary>(
        MySalesSummaryController.new);

class MySalesSummaryController
    extends AsyncNotifier<MarketSalesSummary> {
  @override
  Future<MarketSalesSummary> build() async {
    final shop = ref.watch(myMarketShopProvider).value;
    if (shop == null) return MarketSalesSummary.of(const []);
    final sales = await MarketRepository.instance.fetchMySales();
    return MarketSalesSummary.of(sales);
  }

  Future<void> refresh() async {
    final shop = ref.read(myMarketShopProvider).value;
    if (shop == null) {
      state = AsyncData(MarketSalesSummary.of(const []));
      return;
    }
    final sales = await MarketRepository.instance.fetchMySales();
    state = AsyncData(MarketSalesSummary.of(sales));
  }
}

// ---------------------------------------------------------------- checkout

/// Lifecycle of a PitchMarket gear purchase.
class MarketCheckoutState {
  const MarketCheckoutState({
    this.phase = PiPaymentPhase.idle,
    this.message,
    this.result,
  });

  final PiPaymentPhase phase;
  final String? message;
  final MarketCheckoutResult? result;

  bool get busy =>
      phase == PiPaymentPhase.awaitingUser ||
      phase == PiPaymentPhase.readyForApproval ||
      phase == PiPaymentPhase.readyForCompletion ||
      phase == PiPaymentPhase.completing;

  MarketCheckoutState copyWith({
    PiPaymentPhase? phase,
    String? message,
    MarketCheckoutResult? result,
    bool clearMessage = false,
  }) =>
      MarketCheckoutState(
        phase: phase ?? this.phase,
        message: clearMessage ? null : (message ?? this.message),
        result: result ?? this.result,
      );
}

final marketCheckoutProvider =
    NotifierProvider<MarketCheckoutController, MarketCheckoutState>(
        MarketCheckoutController.new);

class MarketCheckoutController extends Notifier<MarketCheckoutState> {
  StreamSubscription<PiPaymentState>? _sub;

  @override
  MarketCheckoutState build() => const MarketCheckoutState();

  /// Buys a gear item: opens the buyer's Pi wallet for the full price, then
  /// hands the payment to `market-checkout` for the fee-split settlement.
  /// Offline (demo) sessions settle through the simulated split instead so
  /// the full flow stays explorable.
  Future<void> buy(MarketListing listing) async {
    if (state.busy) return;
    if (!listing.inStock) {
      state = MarketCheckoutState(
        phase: PiPaymentPhase.error,
        message: 'This item just went out of stock.',
      );
      return;
    }
    final pi = ref.read(authProvider.notifier).pi;
    if (pi == null || !pi.isSdkAvailable) {
      if (SupabaseConfig.available) {
        state = const MarketCheckoutState(
          phase: PiPaymentPhase.error,
          message: 'Pi payments require the Pi Browser.',
        );
        return;
      }
      // Demo mode: simulate the split locally.
      await _settle(
        'demo-pay-${DateTime.now().millisecondsSinceEpoch}',
        null,
        listing,
      );
      return;
    }

    state = MarketCheckoutState(phase: PiPaymentPhase.awaitingUser);

    _sub?.cancel();
    _sub = pi
        .createPayment(
      amount: listing.pricePi,
      memo: 'PitchMarket — ${listing.title}',
      metadata: <String, Object?>{
        'product': MarketListing.purchaseProduct,
        'sku': 'market_gear',
        'price_pi': listing.pricePi,
        'reference_id': listing.id,
        'listing_title': listing.title,
        'category': listing.category,
      },
    )
        .listen(
      (ps) async {
        switch (ps.phase) {
          case PiPaymentPhase.awaitingUser:
          case PiPaymentPhase.readyForApproval:
          case PiPaymentPhase.readyForCompletion:
            state = state.copyWith(phase: ps.phase, clearMessage: true);
            break;
          case PiPaymentPhase.completing:
          case PiPaymentPhase.completed:
            // The completion webhook already mirrored the payment; the
            // dedicated market-checkout function performs the split.
            await _settle(ps.paymentId ?? '', ps.txid, listing);
            break;
          case PiPaymentPhase.cancelled:
            state = MarketCheckoutState(
              phase: PiPaymentPhase.cancelled,
              message: 'Checkout cancelled — nothing was charged.',
            );
            break;
          case PiPaymentPhase.error:
            state = MarketCheckoutState(
              phase: PiPaymentPhase.error,
              message: ps.error ?? 'Payment failed.',
            );
            break;
          case PiPaymentPhase.idle:
            break;
        }
      },
      onError: (Object e) {
        state = MarketCheckoutState(
          phase: PiPaymentPhase.error,
          message: 'Unexpected checkout error: $e',
        );
      },
    );
  }

  /// Invokes the market-checkout edge function (fee split + A2U merchant
  /// payout + stock decrement) and refreshes the listing view.
  Future<void> _settle(
      String paymentId, String? txid, MarketListing listing) async {
    if (paymentId.isEmpty) {
      state = MarketCheckoutState(
        phase: PiPaymentPhase.error,
        message: 'Payment id missing — contact support with your receipt.',
      );
      return;
    }
    state = state.copyWith(phase: PiPaymentPhase.completing);

    MarketCheckoutResult? result;
    if (SupabaseConfig.available && txid != null && txid.isNotEmpty) {
      try {
        final res = await SupabaseConfig.functions
            .invoke('market-checkout', body: {
          'paymentId': paymentId,
          'txid': txid,
        });
        final data = res.data;
        if (data is Map && data['ok'] == true) {
          final split = data['split'];
          result = MarketCheckoutResult(
            paymentId: paymentId,
            listingId: (data['listingId'] ?? listing.id).toString(),
            remainingStock: (data['remainingStock'] as num?)?.toInt() ?? 0,
            merchantAmount: split is Map
                ? (split['merchantAmount'] as num?)?.toDouble()
                : null,
            platformFee: split is Map
                ? (split['platformFee'] as num?)?.toDouble()
                : null,
            merchantPayoutId: split is Map
                ? split['merchantPayoutId']?.toString()
                : null,
          );
        } else if (data is Map && data['alreadySettled'] == true) {
          // Retry after a dropped connection — the split already happened.
          result = MarketCheckoutResult(
            paymentId: paymentId,
            listingId: (data['listingId'] ?? listing.id).toString(),
            remainingStock: listing.stockQuantity > 0
                ? listing.stockQuantity - 1
                : 0,
          );
        } else {
          final err = data is Map ? (data['error'] ?? 'unknown') : 'unknown';
          state = MarketCheckoutState(
            phase: PiPaymentPhase.error,
            message: 'Settlement failed ($err) — your payment is safe; '
                'support can release it.',
          );
          return;
        }
      } catch (e) {
        debugPrint('[Market] checkout settle failed: $e');
        state = MarketCheckoutState(
          phase: PiPaymentPhase.error,
          message: 'Settlement call failed — your payment is safe; '
              'the purchase will be reconciled.',
        );
        return;
      }
    } else {
      // Demo mode: simulate the split locally.
      result = await MarketRepository.instance.settleDemoCheckout(
        paymentId: paymentId.isEmpty
            ? 'demo-pay-${DateTime.now().millisecondsSinceEpoch}'
            : paymentId,
        listing: listing,
      );
    }

    // Refresh local stock views from the (server-settled) source of truth.
    final fresh =
        await MarketRepository.instance.refreshAfterCheckout(listing.id);
    if (fresh != null) {
      await ref.read(marketListingsProvider.notifier).refresh();
      await ref.read(myListingsProvider.notifier).refresh();
    }
    // The settle wrote the buyer receipt (demo store or pi_payments row) —
    // pull the fresh order history for the wallet ledger.
    unawaited(ref.read(myMarketOrdersProvider.notifier).refresh());
    // Demo sessions share one user, so a purchase can also be the seller's
    // sale — keep the merchant summary fresh either way.
    unawaited(ref.read(mySalesSummaryProvider.notifier).refresh());

    final demo = result?.demo ?? false;
    state = MarketCheckoutState(
      phase: PiPaymentPhase.completed,
      message: demo
          ? 'Demo purchase complete — fee split simulated '
              '(${result?.merchantAmount?.toStringAsFixed(2)} π to merchant, '
              '${result?.platformFee?.toStringAsFixed(2)} π maintenance).'
          : 'Purchase complete! The merchant has been paid their share '
              'and your gear is reserved.',
      result: result,
    );
  }

  void dismiss() {
    _sub?.cancel();
    state = const MarketCheckoutState();
  }
}
