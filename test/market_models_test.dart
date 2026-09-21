import 'package:flutter_test/flutter_test.dart';
import 'package:the_radar/src/models/market.dart';
import 'package:the_radar/src/models/market_order.dart';
import 'package:the_radar/src/models/market_sales.dart';

void main() {
  group('MarketShop', () {
    test('parses a Supabase row', () {
      final shop = MarketShop.fromJson(<String, Object?>{
        'id': 'shop-1',
        'owner_id': 'owner-1',
        'shop_name': 'Accra Creator Depot',
        'description': 'Pro streaming gear.',
        'pi_uid': 'pi-uid-1',
        'location_area': 'Accra — Osu',
        'is_verified': true,
        'created_at': '2026-05-14T10:00:00Z',
      });

      expect(shop.id, 'shop-1');
      expect(shop.ownerId, 'owner-1');
      expect(shop.shopName, 'Accra Creator Depot');
      expect(shop.description, 'Pro streaming gear.');
      expect(shop.piUid, 'pi-uid-1');
      expect(shop.locationArea, 'Accra — Osu');
      expect(shop.isVerified, isTrue);
      expect(shop.createdAt.year, 2026);
    });

    test('tolerates missing optional fields', () {
      final shop = MarketShop.fromJson(<String, Object?>{
        'id': 'shop-2',
        'owner_id': 'owner-2',
        'shop_name': 'Minimal Shop',
        'pi_uid': 'pi-uid-2',
        'location_area': 'Somewhere',
      });

      expect(shop.description, isNull);
      expect(shop.isVerified, isFalse);
    });

    test('toJson carries the writable fields', () {
      final shop = MarketShop(
        id: 'shop-3',
        ownerId: 'owner-3',
        shopName: 'Round Trip',
        piUid: 'pi-uid-3',
        locationArea: 'Accra',
        isVerified: false,
        createdAt: DateTime(2026, 6, 1),
      );
      final json = shop.toJson();
      expect(json['shop_name'], 'Round Trip');
      expect(json['pi_uid'], 'pi-uid-3');
      expect(json['location_area'], 'Accra');
      expect(json['is_verified'], isFalse);
      // owner_id is supplied by the repository (auth.uid()), not the model.
      expect(json.containsKey('owner_id'), isFalse);
    });
  });

  group('MarketListing', () {
    final base = <String, Object?>{
      'id': 'listing-1',
      'shop_id': 'shop-1',
      'title': 'DJI Osmo Mobile 6 Gimbal',
      'category': 'gimbal',
      'price_pi': 45.0,
      'condition': 'brand_new',
      'stock_quantity': 3,
      'media_urls': <String>['https://a.example/1.jpg'],
      'is_active': true,
      'created_at': '2026-09-01T08:00:00Z',
    };

    test('parses a Supabase row', () {
      final l = MarketListing.fromJson(base);
      expect(l.id, 'listing-1');
      expect(l.category, 'gimbal');
      expect(l.pricePi, 45.0);
      expect(l.condition, 'brand_new');
      expect(l.stockQuantity, 3);
      expect(l.mediaUrls, hasLength(1));
      expect(l.inStock, isTrue);
    });

    test('inStock is false when stock is zero or inactive', () {
      final soldOut = MarketListing.fromJson(<String, Object?>{...base, 'stock_quantity': 0});
      final inactive = MarketListing.fromJson(<String, Object?>{...base, 'is_active': false});
      expect(soldOut.inStock, isFalse);
      expect(inactive.inStock, isFalse);
    });

    test('labels resolve for categories and conditions', () {
      expect(marketCategoryLabel('gimbal'), 'Gimbal');
      expect(marketCategoryLabel('lighting'), 'Lighting');
      expect(marketCategoryLabel('weird'), 'weird');
      expect(marketConditionLabel('brand_new'), 'Brand new');
      expect(marketConditionLabel('good'), 'Good');
    });

    test('matchesQuery hits title, category and condition', () {
      final l = MarketListing.fromJson(base);
      expect(MarketListing.matchesQuery(l, 'osmo'), isTrue);
      expect(MarketListing.matchesQuery(l, 'GIMBAL'), isTrue);
      expect(MarketListing.matchesQuery(l, 'brand'), isTrue);
      expect(MarketListing.matchesQuery(l, 'microwave'), isFalse);
      expect(MarketListing.matchesQuery(l, ''), isTrue);
    });
  });

  group('MarketOrder', () {
    // A settled receipt as `market-checkout` writes it: product on the
    // column, split + settlement markers in metadata.
    final receipt = <String, Object?>{
      'identifier': 'pay-123',
      'user_uid': 'buyer-uid',
      'amount': 45.0,
      'memo': 'PitchMarket — DJI Osmo Mobile 6 Gimbal',
      'product': 'market_gear_purchase',
      'status': 'completed',
      'txid': 'abc123def456',
      'created_at': '2026-09-20T14:30:00Z',
      'metadata': <String, Object?>{
        'product': 'market_gear_purchase',
        'reference_id': 'listing-1',
        'market_settled': true,
        'listing_title': 'DJI Osmo Mobile 6 Gimbal',
        'shop_id': 'shop-1',
        'merchant_pi_uid': 'merchant-uid',
        'merchant_amount': 42.75,
        'platform_fee': 2.25,
        'merchant_payout_id': 'payout-9',
      },
    };

    test('parses a settled pi_payments receipt with the fee split', () {
      final o = MarketOrder.fromJson(receipt);
      expect(o.paymentId, 'pay-123');
      expect(o.amountPi, 45.0);
      expect(o.product, 'market_gear_purchase');
      expect(o.listingTitle, 'DJI Osmo Mobile 6 Gimbal');
      expect(o.shopId, 'shop-1');
      expect(o.merchantAmountPi, 42.75);
      expect(o.platformFeePi, 2.25);
      expect(o.merchantPayoutId, 'payout-9');
      expect(o.isSettled, isTrue);
      expect(o.createdAt.year, 2026);
    });

    test('split math is auditable: merchant share + fee == total', () {
      final o = MarketOrder.fromJson(receipt);
      expect(o.merchantAmountPi! + o.platformFeePi!, closeTo(o.amountPi, 0.0001));
    });

    test('splitLabel renders merchant share, fee and fee percent', () {
      expect(
        MarketOrder.fromJson(receipt).splitLabel,
        '42.75 π merchant · 2.25 π fee (5%)',
      );
    });

    test('unsettled receipts fall back to memo and total', () {
      final o = MarketOrder.fromJson(<String, Object?>{
        ...receipt,
        'metadata': <String, Object?>{'product': 'market_gear_purchase'},
      });
      expect(o.isSettled, isFalse);
      expect(o.merchantAmountPi, isNull);
      expect(o.listingTitle, contains('DJI Osmo')); // falls back to memo
      expect(o.splitLabel, '45.00 π total');
    });

    test('tolerates a missing metadata map', () {
      final o = MarketOrder.fromJson(<String, Object?>{...receipt}
        ..remove('metadata'));
      expect(o.isSettled, isFalse);
      expect(o.listingTitle, contains('DJI Osmo'));
    });

    test('demo factory mirrors the split shape', () {
      final o = MarketOrder.demo(
        paymentId: 'demo-pay-1',
        listingTitle: 'Rode Wireless GO II',
        amountPi: 38.5,
        merchantAmountPi: 36.575,
        platformFeePi: 1.925,
        createdAt: DateTime(2026, 9, 21),
      );
      expect(o.product, 'market_gear_purchase');
      expect(o.merchantPayoutId, 'demo-payout-demo-pay-1');
      expect(o.merchantAmountPi! + o.platformFeePi!, closeTo(38.5, 0.0001));
      expect(o.splitLabel, contains('36.58 π merchant'));
    });
  });

  group('MarketSale / MarketSalesSummary', () {
    // A merchant payout leg as `market-checkout` writes it.
    Map<String, Object?> payout({
      required String id,
      required double net,
      required double gross,
      required double fee,
      String title = 'DJI Osmo Mobile 6 Gimbal',
    }) =>
        <String, Object?>{
          'identifier': id,
          'user_uid': 'merchant-uid',
          'amount': net,
          'memo': 'PitchMarket sale: $title',
          'product': 'market_merchant_payout',
          'status': 'approved',
          'created_at': '2026-09-20T15:00:00Z',
          'metadata': <String, Object?>{
            'product': 'market_merchant_payout',
            'direction': 'a2u_payout',
            'listing_title': title,
            'gross_amount': gross,
            'platform_fee': fee,
          },
        };

    test('parses a payout receipt with the split metadata', () {
      final s = MarketSale.fromJson(
          payout(id: 'payout-1', net: 42.75, gross: 45.0, fee: 2.25));
      expect(s.payoutId, 'payout-1');
      expect(s.netAmountPi, 42.75);
      expect(s.grossAmountPi, 45.0);
      expect(s.platformFeePi, 2.25);
      expect(s.listingTitle, 'DJI Osmo Mobile 6 Gimbal');
      expect(s.hasSplit, isTrue);
      expect(s.createdAt.year, 2026);
    });

    test('memo fallback strips the payout prefix', () {
      final s = MarketSale.fromJson(<String, Object?>{
        'identifier': 'payout-2',
        'amount': 10.0,
        'memo': 'PitchMarket sale: Rode Wireless GO II',
      });
      expect(s.listingTitle, 'Rode Wireless GO II');
      expect(s.hasSplit, isFalse);
    });

    test('aggregates units, gross, fees and net across sales', () {
      final summary = MarketSalesSummary.of([
        MarketSale.fromJson(
            payout(id: 'a', net: 42.75, gross: 45.0, fee: 2.25)),
        MarketSale.fromJson(
            payout(id: 'b', net: 36.575, gross: 38.5, fee: 1.925,
                title: 'Rode Wireless GO II')),
        MarketSale.fromJson(
            payout(id: 'c', net: 27.55, gross: 29.0, fee: 1.45,
                title: 'Manfrotto Befree GT Pro')),
      ]);
      expect(summary.unitsSold, 3);
      expect(summary.grossPi, closeTo(112.5, 0.0001));
      expect(summary.feesPi, closeTo(5.625, 0.0001));
      expect(summary.netPi, closeTo(106.875, 0.0001));
      // Accounting identity: gross − fees == net.
      expect(summary.grossPi - summary.feesPi, closeTo(summary.netPi, 0.0001));
      expect(summary.effectiveFeeRate, closeTo(0.05, 0.0001));
    });

    test('payout legs without split metadata still count toward net', () {
      final withSplit = MarketSale.fromJson(
          payout(id: 'a', net: 42.75, gross: 45.0, fee: 2.25));
      final legacy = MarketSale.fromJson(<String, Object?>{
        'identifier': 'legacy',
        'amount': 10.0,
        'memo': 'PitchMarket sale: legacy unit',
      });
      final summary = MarketSalesSummary.of([withSplit, legacy]);
      expect(summary.unitsSold, 2);
      expect(summary.netPi, closeTo(52.75, 0.0001));
      expect(summary.grossPi, 45.0); // legacy leg has no gross metadata
    });

    test('empty ledger yields a zeroed summary', () {
      final s = MarketSalesSummary.of(const []);
      expect(s.unitsSold, 0);
      expect(s.grossPi, 0);
      expect(s.feesPi, 0);
      expect(s.netPi, 0);
      expect(s.effectiveFeeRate, 0);
    });
  });
}
