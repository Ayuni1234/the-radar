/// Merchant sales summary for The PitchMarket — the seller side of the
/// fee-split ledger.
///
/// The merchant's own payout receipts (`pi_payments` rows with
/// `metadata.product = 'market_merchant_payout'`, readable via RLS
/// `user_uid = verified_pi_uid()`) carry `gross_amount` / `platform_fee` /
/// `listing_title` metadata stamped by `market-checkout` at settlement, so
/// the seller can reconstruct units sold, gross Pi earned, fees paid and
/// net payout without any cross-user read access.
library;

/// One settled sale, parsed from the merchant's A2U payout receipt.
class MarketSale {
  const MarketSale({
    required this.payoutId,
    required this.netAmountPi,
    required this.listingTitle,
    required this.createdAt,
    this.grossAmountPi,
    this.platformFeePi,
    this.listingId,
  });

  /// Pi payment id of the A2U payout leg (`pi_payments.identifier`).
  final String payoutId;

  /// Amount actually paid out to the merchant's wallet.
  final double netAmountPi;

  /// Gear title from the settlement metadata (falls back to the memo).
  final String listingTitle;

  final String? listingId;

  /// Full price the buyer paid, when the receipt carries the split.
  final double? grossAmountPi;

  /// Platform maintenance cut captured at settlement.
  final double? platformFeePi;

  final DateTime createdAt;

  /// True when the receipt carries the split metadata stamped by
  /// `market-checkout` (older/manual payout legs may not have it).
  bool get hasSplit => grossAmountPi != null && platformFeePi != null;

  factory MarketSale.fromJson(Map<String, Object?> json) {
    final meta = json['metadata'] is Map
        ? (json['metadata'] as Map).map(
            (k, v) => MapEntry(k.toString(), v),
          )
        : const <String, Object?>{};

    return MarketSale(
      payoutId: (json['identifier'] ?? json['id'] ?? '').toString(),
      netAmountPi: (json['amount'] as num?)?.toDouble() ?? 0,
      listingTitle: (meta['listing_title'] ?? json['memo'] ?? 'Sale')
          .toString()
          // Strip the `PitchMarket sale: ` prefix from the payout memo.
          .replaceFirst(RegExp(r'^PitchMarket sale: ', caseSensitive: false), ''),
      listingId: meta['listing_id']?.toString(),
      grossAmountPi: (meta['gross_amount'] as num?)?.toDouble(),
      platformFeePi: (meta['platform_fee'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// Aggregated seller economics over a set of settled payout receipts.
class MarketSalesSummary {
  const MarketSalesSummary({
    required this.sales,
    required this.unitsSold,
    required this.grossPi,
    required this.feesPi,
    required this.netPi,
  });

  /// Newest-first settled payout receipts (the raw material).
  final List<MarketSale> sales;

  final int unitsSold;
  final double grossPi;
  final double feesPi;
  final double netPi;

  /// Average maintenance fee as a percent of gross (0 when no data).
  double get effectiveFeeRate => grossPi > 0 ? feesPi / grossPi : 0;

  static MarketSalesSummary of(List<MarketSale> sales) {
    var gross = 0.0;
    var fees = 0.0;
    var net = 0.0;
    for (final s in sales) {
      if (s.hasSplit) {
        gross += s.grossAmountPi!;
        fees += s.platformFeePi!;
      }
      net += s.netAmountPi;
    }
    return MarketSalesSummary(
      sales: sales,
      unitsSold: sales.length,
      // Rounding guards float accumulation drift in the display totals.
      grossPi: (gross * 10000).round() / 10000,
      feesPi: (fees * 10000).round() / 10000,
      netPi: (net * 10000).round() / 10000,
    );
  }
}
