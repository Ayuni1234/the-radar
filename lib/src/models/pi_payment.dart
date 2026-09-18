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
