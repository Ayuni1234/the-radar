/// Buyer order history for The PitchMarket — a completed gear purchase as
/// recorded in `pi_payments` by `market-checkout` (or the demo settle).
///
/// One receipt row = one order. The fee split lives in the receipt's
/// `metadata` (merchant_amount / platform_fee) so the buyer can audit
/// exactly where their Pi went: merchant payout vs platform maintenance.
library;

import 'market.dart';

/// A completed PitchMarket purchase (mirrors one `pi_payments` row whose
/// `metadata.product = 'market_gear_purchase'`).
class MarketOrder {
  const MarketOrder({
    required this.paymentId,
    required this.amountPi,
    required this.listingTitle,
    required this.createdAt,
    this.txid,
    this.product = MarketListing.purchaseProduct,
    this.shopId,
    this.merchantAmountPi,
    this.platformFeePi,
    this.merchantPayoutId,
  });

  /// The buyer's Pi payment identifier (`pi_payments.identifier`).
  final String paymentId;

  /// Full price the buyer paid (equals merchant share + fee).
  final double amountPi;
  final String listingTitle;

  /// The merchant shop, when the settlement recorded it.
  final String? shopId;

  /// Core amount routed to the merchant's verified pi_uid (null when the
  /// receipt predates the split metadata).
  final double? merchantAmountPi;

  /// Platform maintenance cut kept by the treasury wallet.
  final double? platformFeePi;

  /// Receipt product — `market_gear_purchase` for buyer orders.
  final String product;

  /// Pi payment id of the merchant A2U payout leg, when settled.
  final String? merchantPayoutId;

  final String? txid;
  final DateTime createdAt;

  bool get isSettled => merchantAmountPi != null || platformFeePi != null;

  /// Renders the split the way the wallet ledger shows money movement.
  /// e.g. `42.75 π merchant · 2.25 π fee (5%)` or `45.00 π total`.
  String get splitLabel {
    if (!isSettled) return '${amountPi.toStringAsFixed(2)} π total';
    final pct = amountPi > 0
        ? (platformFeePi! / amountPi * 100).toStringAsFixed(0)
        : '0';
    return '${merchantAmountPi!.toStringAsFixed(2)} π merchant · '
        '${platformFeePi!.toStringAsFixed(2)} π fee ($pct%)';
  }

  factory MarketOrder.fromJson(Map<String, Object?> json) {
    final meta = json['metadata'] is Map
        ? (json['metadata'] as Map).map(
            (k, v) => MapEntry(k.toString(), v),
          )
        : const <String, Object?>{};

    return MarketOrder(
      paymentId: (json['identifier'] ?? json['id'] ?? '').toString(),
      amountPi: (json['amount'] as num?)?.toDouble() ?? 0,
      product: (json['product'] ?? '').toString(),
      listingTitle:
          (meta['listing_title'] ?? json['memo'] ?? 'PitchMarket purchase')
              .toString(),
      shopId: meta['shop_id']?.toString(),
      merchantAmountPi: (meta['merchant_amount'] as num?)?.toDouble(),
      platformFeePi: (meta['platform_fee'] as num?)?.toDouble(),
      merchantPayoutId: meta['merchant_payout_id']?.toString(),
      txid: json['txid']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }

  /// Demo orders are synthesized locally so offline sessions can explore
  /// the order history too (paymentId = 'demo-pay-…', txid absent).
  factory MarketOrder.demo({
    required String paymentId,
    required String listingTitle,
    required double amountPi,
    required double merchantAmountPi,
    required double platformFeePi,
    required DateTime createdAt,
  }) =>
      MarketOrder(
        paymentId: paymentId,
        amountPi: amountPi,
        listingTitle: listingTitle,
        shopId: 'demo-shop',
        merchantAmountPi: merchantAmountPi,
        platformFeePi: platformFeePi,
        merchantPayoutId: 'demo-payout-$paymentId',
        product: MarketListing.purchaseProduct,
        createdAt: createdAt,
      );
}
