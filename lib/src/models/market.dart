/// PitchMarket models — merchant shops and gear listings for the P2P
/// streaming-equipment marketplace (paid in Pi, split via `market-checkout`).
///
/// Mirrors `public.market_shops` / `public.market_listings`
/// (supabase/migrations/0001_pitch_market.sql).
library;

/// The gear categories a listing can belong to.
const List<String> kMarketCategories = <String>[
  'phone',
  'gimbal',
  'tripod',
  'audio',
  'lighting',
  'accessory',
];

/// Human labels + icons for the gear categories (kept UI-free).
String marketCategoryLabel(String category) => switch (category) {
      'phone' => 'Phone',
      'gimbal' => 'Gimbal',
      'tripod' => 'Tripod',
      'audio' => 'Audio',
      'lighting' => 'Lighting',
      'accessory' => 'Accessory',
      _ => category,
    };

/// The condition grades a listing can declare.
const List<String> kMarketConditions = <String>['brand_new', 'like_new', 'good'];

String marketConditionLabel(String condition) => switch (condition) {
      'brand_new' => 'Brand new',
      'like_new' => 'Like new',
      'good' => 'Good',
      _ => condition,
    };

/// A merchant storefront on The PitchMarket.
class MarketShop {
  const MarketShop({
    required this.id,
    required this.ownerId,
    required this.shopName,
    required this.piUid,
    required this.locationArea,
    required this.createdAt,
    this.description,
    this.isVerified = false,
  });

  final String id;
  final String ownerId;
  final String shopName;
  final String? description;

  /// Vendor's verified Pi account — the A2U payout destination.
  final String piUid;
  final String locationArea;
  final bool isVerified;
  final DateTime createdAt;

  MarketShop copyWith({
    String? shopName,
    String? description,
    String? piUid,
    String? locationArea,
    bool? isVerified,
  }) =>
      MarketShop(
        id: id,
        ownerId: ownerId,
        shopName: shopName ?? this.shopName,
        description: description ?? this.description,
        piUid: piUid ?? this.piUid,
        locationArea: locationArea ?? this.locationArea,
        isVerified: isVerified ?? this.isVerified,
        createdAt: createdAt,
      );

  factory MarketShop.fromJson(Map<String, Object?> json) {
    String? str(Object? v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return MarketShop(
      id: (json['id'] ?? '').toString(),
      ownerId: (json['owner_id'] ?? '').toString(),
      shopName: (json['shop_name'] ?? 'Unnamed shop').toString(),
      description: str(json['description']),
      piUid: (json['pi_uid'] ?? '').toString(),
      locationArea: (json['location_area'] ?? 'Unknown area').toString(),
      isVerified: json['is_verified'] == true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'shop_name': shopName,
        'description': description,
        'pi_uid': piUid,
        'location_area': locationArea,
        'is_verified': isVerified,
      };
}

/// A piece of pro streaming gear for outright Pi purchase.
class MarketListing {
  const MarketListing({
    required this.id,
    required this.shopId,
    required this.title,
    required this.category,
    required this.pricePi,
    required this.condition,
    required this.stockQuantity,
    required this.createdAt,
    this.mediaUrls = const <String>[],
    this.isActive = true,
  });

  final String id;
  final String shopId;
  final String title;
  final String category;
  final double pricePi;
  final String condition;
  final int stockQuantity;
  final List<String> mediaUrls;
  final bool isActive;
  final DateTime createdAt;

  bool get inStock => isActive && stockQuantity > 0;

  /// True when the buyer's payment is settled by `market-checkout`
  /// (merchant A2U payout + treasury fee) — used for the receipt flow.
  static const String purchaseProduct = 'market_gear_purchase';

  MarketListing copyWith({
    String? title,
    String? category,
    double? pricePi,
    String? condition,
    int? stockQuantity,
    List<String>? mediaUrls,
    bool? isActive,
  }) =>
      MarketListing(
        id: id,
        shopId: shopId,
        title: title ?? this.title,
        category: category ?? this.category,
        pricePi: pricePi ?? this.pricePi,
        condition: condition ?? this.condition,
        stockQuantity: stockQuantity ?? this.stockQuantity,
        mediaUrls: mediaUrls ?? this.mediaUrls,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  factory MarketListing.fromJson(Map<String, Object?> json) => MarketListing(
        id: (json['id'] ?? '').toString(),
        shopId: (json['shop_id'] ?? '').toString(),
        title: (json['title'] ?? 'Gear').toString(),
        category: (json['category'] ?? 'accessory').toString(),
        pricePi: (json['price_pi'] as num?)?.toDouble() ?? 0,
        condition: (json['condition'] ?? 'good').toString(),
        stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
        mediaUrls: json['media_urls'] is List
            ? (json['media_urls'] as List)
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
            : const <String>[],
        isActive: json['is_active'] != false,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'category': category,
        'price_pi': pricePi,
        'condition': condition,
        'stock_quantity': stockQuantity,
        'media_urls': mediaUrls,
        'is_active': isActive,
      };

  /// Feed/search filter view model.
  static bool matchesQuery(MarketListing l, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return '${l.title} ${l.category} ${l.condition}'.toLowerCase().contains(q);
  }
}
