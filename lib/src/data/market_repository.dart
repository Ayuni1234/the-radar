// Data layer for The PitchMarket — merchant shops, gear listings and the
// fee-split checkout flow.
//
// Uses the live Supabase connection when configured; otherwise serves the
// in-memory demo dataset so the marketplace remains explorable offline
// (same pattern as [RadarRepository]).

import 'package:flutter/foundation.dart';

import '../models/market.dart';
import '../models/market_order.dart';
import '../models/market_sales.dart';
import '../supabase/supabase_config.dart';
import 'demo_seed.dart';

/// Result of a completed gear purchase (fee split + stock state).
@immutable
class MarketCheckoutResult {
  const MarketCheckoutResult({
    required this.paymentId,
    required this.listingId,
    required this.remainingStock,
    this.merchantAmount,
    this.platformFee,
    this.merchantPayoutId,
    this.demo = false,
  });

  final String paymentId;
  final String listingId;
  final int remainingStock;
  final double? merchantAmount;
  final double? platformFee;

  /// Pi payment id of the merchant A2U payout leg (null while pending).
  final String? merchantPayoutId;

  /// True when no Supabase backend is configured (demo checkout).
  final bool demo;
}

class MarketRepository {
  MarketRepository._();

  static final MarketRepository instance = MarketRepository._();

  bool get _live => SupabaseConfig.available;

  // ---------------------------------------------------------------- shops

  /// All merchant shops, newest first.
  Future<List<MarketShop>> fetchShops() async {
    if (!_live) return List.of(DemoSeed.marketShops);
    try {
      final res = await SupabaseConfig.client
          .from('market_shops')
          .select()
          .order('created_at', ascending: false);
      return res.map<MarketShop>((e) => MarketShop.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[MarketRepo] fetchShops failed: $e');
      return List.of(DemoSeed.marketShops);
    }
  }

  /// The signed-in merchant's own shop, or null when not registered.
  Future<MarketShop?> fetchMyShop(String ownerId) async {
    if (!_live) {
      for (final s in DemoSeed.marketShops) {
        if (s.ownerId == ownerId) return s;
      }
      return null;
    }
    try {
      final row = await SupabaseConfig.client
          .from('market_shops')
          .select()
          .eq('owner_id', ownerId)
          .limit(1)
          .maybeSingle();
      return row == null ? null : MarketShop.fromJson(row);
    } catch (e) {
      debugPrint('[MarketRepo] fetchMyShop failed: $e');
      return null;
    }
  }

  /// Creates or updates the signed-in user's storefront. Returns the saved
  /// shop, or null when the write was rejected (RLS / validation).
  Future<MarketShop?> upsertMyShop(
    String ownerId,
    MarketShop shop,
  ) async {
    if (!_live) {
      final idx = DemoSeed.marketShops.indexWhere((s) => s.ownerId == ownerId);
      final saved = shop.copyWith(isVerified: true);
      if (idx >= 0) {
        DemoSeed.marketShops[idx] = saved;
      } else {
        DemoSeed.marketShops.add(saved);
      }
      return saved;
    }
    try {
      final res = await SupabaseConfig.client
          .from('market_shops')
          .upsert(<String, Object?>{
            'owner_id': ownerId,
            ...shop.toJson(),
          })
          .select()
          .single();
      return MarketShop.fromJson(res);
    } catch (e) {
      debugPrint('[MarketRepo] upsertMyShop failed: $e');
      return null;
    }
  }

  // ------------------------------------------------------------- listings

  /// All active gear listings (public feed), newest first.
  Future<List<MarketListing>> fetchListings({bool activeOnly = true}) async {
    if (!_live) {
      return DemoSeed.marketListings
          .where((l) => !activeOnly || l.isActive)
          .toList();
    }
    try {
      var q = SupabaseConfig.client.from('market_listings').select();
      if (activeOnly) q = q.eq('is_active', true);
      final res =
          await q.order('created_at', ascending: false).limit(200);
      return res.map<MarketListing>((e) => MarketListing.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[MarketRepo] fetchListings failed: $e');
      return DemoSeed.marketListings
          .where((l) => !activeOnly || l.isActive)
          .toList();
    }
  }

  /// A single listing by id (detail view).
  Future<MarketListing?> fetchListing(String id) async {
    if (!_live) {
      for (final l in DemoSeed.marketListings) {
        if (l.id == id) return l;
      }
      return null;
    }
    try {
      final row = await SupabaseConfig.client
          .from('market_listings')
          .select()
          .eq('id', id)
          .limit(1)
          .maybeSingle();
      return row == null ? null : MarketListing.fromJson(row);
    } catch (e) {
      debugPrint('[MarketRepo] fetchListing failed: $e');
      return null;
    }
  }

  /// The signed-in merchant's own inventory (all states, incl. inactive).
  Future<List<MarketListing>> fetchMyListings(String shopId) async {
    if (!_live) {
      return DemoSeed.marketListings
          .where((l) => l.shopId == shopId)
          .toList();
    }
    try {
      final res = await SupabaseConfig.client
          .from('market_listings')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      return res.map<MarketListing>((e) => MarketListing.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[MarketRepo] fetchMyListings failed: $e');
      return const [];
    }
  }

  /// Publishes a new gear listing. Returns the created row, or null when
  /// rejected (no shop / RLS).
  Future<MarketListing?> createListing(MarketListing listing) async {
    if (!_live) {
      DemoSeed.marketListings.insert(0, listing);
      return listing;
    }
    try {
      final res = await SupabaseConfig.client
          .from('market_listings')
          .insert(listing.toJson())
          .select()
          .single();
      return MarketListing.fromJson(res);
    } catch (e) {
      debugPrint('[MarketRepo] createListing failed: $e');
      return null;
    }
  }

  /// Thin patch (stock edits, activation toggle, price update).
  Future<bool> updateListing(String id, Map<String, Object?> patch) async {
    if (!_live) {
      final idx =
          DemoSeed.marketListings.indexWhere((l) => l.id == id);
      if (idx < 0) return false;
      final l = DemoSeed.marketListings[idx];
      DemoSeed.marketListings[idx] = MarketListing(
        id: l.id,
        shopId: l.shopId,
        title: (patch['title'] as String?) ?? l.title,
        category: (patch['category'] as String?) ?? l.category,
        pricePi: (patch['price_pi'] as num?)?.toDouble() ?? l.pricePi,
        condition: (patch['condition'] as String?) ?? l.condition,
        stockQuantity:
            (patch['stock_quantity'] as num?)?.toInt() ?? l.stockQuantity,
        mediaUrls: l.mediaUrls,
        isActive: (patch['is_active'] as bool?) ?? l.isActive,
        createdAt: l.createdAt,
      );
      return true;
    }
    try {
      await SupabaseConfig.client
          .from('market_listings')
          .update(patch)
          .eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[MarketRepo] updateListing failed: $e');
      return false;
    }
  }

  Future<bool> deleteListing(String id) async {
    if (!_live) {
      DemoSeed.marketListings.removeWhere((l) => l.id == id);
      return true;
    }
    try {
      await SupabaseConfig.client
          .from('market_listings')
          .delete()
          .eq('id', id);
      return true;
    } catch (e) {
      debugPrint('[MarketRepo] deleteListing failed: $e');
      return false;
    }
  }

  // ------------------------------------------------------------- my sales

  /// The signed-in merchant's settled sales, parsed from their own A2U payout
  /// receipts in `pi_payments` (RLS: `user_uid = verified_pi_uid()`), newest
  /// first. Each receipt carries gross/fee metadata stamped by
  /// `market-checkout` at settlement.
  Future<List<MarketSale>> fetchMySales({int limit = 50}) async {
    if (!_live) return List.of(DemoSeed.marketSales);
    try {
      final res = await SupabaseConfig.client
          .from('pi_payments')
          .select()
          .eq('product', 'market_merchant_payout')
          .order('created_at', ascending: false)
          .limit(limit);
      return res.map<MarketSale>((e) => MarketSale.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[MarketRepo] fetchMySales failed: $e');
      return const [];
    }
  }

  // ------------------------------------------------------------- checkout

  /// The signed-in buyer's completed PitchMarket orders with their fee-split
  /// breakdown, newest first (RLS: own receipts only, via `user_uid`).
  Future<List<MarketOrder>> fetchMyMarketOrders({int limit = 25}) async {
    if (!_live) return List.of(DemoSeed.marketOrders);
    try {
      final res = await SupabaseConfig.client
          .from('pi_payments')
          .select()
          .eq('product', MarketListing.purchaseProduct)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(limit);
      return res.map<MarketOrder>((e) => MarketOrder.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[MarketRepo] fetchMyMarketOrders failed: $e');
      return const [];
    }
  }

  /// Refetches a listing after checkout so stock reflects the server state.
  /// In live mode the authoritative decrement happened in `market-checkout`;
  /// here we only refresh the local view of the row.
  Future<MarketListing?> refreshAfterCheckout(String listingId) async {
    return fetchListing(listingId);
  }

  /// Simulates the server-side settlement (demo mode): splits the fee,
  /// decrements stock and deactivates at zero, mirroring `market-checkout`.
  Future<MarketCheckoutResult?> settleDemoCheckout({
    required String paymentId,
    required MarketListing listing,
    double feeRate = 0.05,
  }) async {
    final fee = (listing.pricePi * feeRate * 10000).round() / 10000;
    final merchantAmount =
        ((listing.pricePi - fee) * 10000).round() / 10000;
    final remaining = listing.stockQuantity > 0
        ? listing.stockQuantity - 1
        : 0;
    await updateListing(listing.id, <String, Object?>{
      'stock_quantity': remaining,
      if (remaining == 0) 'is_active': false,
    });
    final idx =
        DemoSeed.marketListings.indexWhere((l) => l.id == listing.id);
    DemoSeed.marketOrders.insert(
      0,
      MarketOrder.demo(
        paymentId: paymentId,
        listingTitle: listing.title,
        amountPi: listing.pricePi,
        merchantAmountPi: merchantAmount,
        platformFeePi: fee,
        createdAt: DateTime.now(),
      ),
    );
    // Mirror the merchant payout receipt so the demo seller dashboard shows
    // the sale too (mirrors the a2u_payout leg `market-checkout` writes).
    DemoSeed.marketSales.insert(
      0,
      MarketSale(
        payoutId: 'demo-payout-$paymentId',
        netAmountPi: merchantAmount,
        listingTitle: listing.title,
        listingId: listing.id,
        grossAmountPi: listing.pricePi,
        platformFeePi: fee,
        createdAt: DateTime.now(),
      ),
    );
    return MarketCheckoutResult(
      paymentId: paymentId,
      listingId: listing.id,
      remainingStock: idx >= 0 ? DemoSeed.marketListings[idx].stockQuantity : remaining,
      merchantAmount: merchantAmount,
      platformFee: fee,
      merchantPayoutId: 'demo-payout-$paymentId',
      demo: true,
    );
  }
}
