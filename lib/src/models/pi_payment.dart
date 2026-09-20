/// A Pi payment recorded on The Radar's backend (mirrors the Pi PaymentDTO).
class PiPayment {
  const PiPayment({
    required this.id,
    required this.piUid,
    required this.amount,
    required this.memo,
    required this.product,
    required this.status,
    required this.createdAt,
    this.txid,
    this.metadata = const {},
  });

  final String id;
  final String piUid;
  final double amount;
  final String memo;

  /// Which Radar product this paid for — e.g. 'premium_search_30d'.
  final String product;

  /// 'created' | 'approved' | 'completed' | 'cancelled' | 'error'
  final String status;
  final DateTime createdAt;
  final String? txid;
  final Map<String, Object?> metadata;

  factory PiPayment.fromJson(Map<String, Object?> json) => PiPayment(
        id: (json['identifier'] ?? json['id'] ?? '').toString(),
        piUid: (json['user_uid'] ?? json['pi_uid'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        memo: (json['memo'] ?? '').toString(),
        product: (json['product'] ?? '').toString(),
        status: (json['status'] ?? 'created').toString(),
        createdAt:
            DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
        txid: json['txid']?.toString(),
        metadata: json['metadata'] is Map
            ? (json['metadata'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : const {},
      );
}

/// A granted entitlement (boost, premium access, bounty) from `entitlements`.
class Entitlement {
  const Entitlement({
    required this.id,
    required this.userUid,
    required this.product,
    this.referenceId,
    this.grantedAt,
    this.expiresAt,
  });

  final String id;
  final String userUid;
  final String product;

  /// The boosted event id / bounty target, when the entitlement is scoped.
  final String? referenceId;
  final DateTime? grantedAt;
  final DateTime? expiresAt;

  bool get isActive {
    final now = DateTime.now();
    final g = grantedAt ?? now;
    if (now.isBefore(g)) return false;
    final e = expiresAt;
    return e == null || e.isAfter(now);
  }

  /// Remaining boost time, rounded for display.
  String get remainingLabel {
    if (!isActive) return 'expired';
    final e = expiresAt;
    if (e == null) return 'no expiry';
    final d = e.difference(DateTime.now());
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h left';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m left';
    return '${d.inMinutes}m left';
  }

  String get productLabel => switch (product) {
        'premium_search_30d' => 'Premium scouting search',
        'session_boost_48h' => 'Session boost',
        'event_spotlight_7d' => 'Global spotlight (event)',
        'profile_spotlight_14d' => 'Profile spotlight',
        'scouting_bounty' => 'Scouting bounty',
        _ => product,
      };

  factory Entitlement.fromJson(Map<String, Object?> json) => Entitlement(
        id: (json['id'] ?? '').toString(),
        userUid: (json['user_uid'] ?? '').toString(),
        product: (json['product'] ?? '').toString(),
        referenceId: json['reference_id']?.toString(),
        grantedAt:
            DateTime.tryParse((json['granted_at'] ?? '').toString())?.toLocal(),
        expiresAt:
            DateTime.tryParse((json['expires_at'] ?? '').toString())?.toLocal(),
      );
}
