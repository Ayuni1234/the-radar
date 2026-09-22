/// A user-filed content report (post, radar event or market listing).
///
/// Any signed-in user can file; reporters see only their own reports and
/// admins (profiles.is_admin) see all and own the status workflow. The
/// database enforces this through RLS (see 0004_feed_schedule_and_reports).
class ContentReport {
  ContentReport({
    required this.id,
    required this.reporterProfileId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.details,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String id;
  final String reporterProfileId;

  /// 'feed_post' | 'radar_event' | 'market_listing'
  final String targetType;
  final String targetId;
  final ContentReportReason reason;

  /// Optional free-text context from the reporter.
  final String? details;

  /// 'open' | 'reviewing' | 'resolved' | 'dismissed'
  final String status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  bool get isOpen => status == 'open' || status == 'reviewing';

  Map<String, Object?> toJson() => {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason.name,
        if (details != null && details!.trim().isNotEmpty)
          'details': details!.trim(),
      };

  factory ContentReport.fromJson(Map<String, Object?> json) {
    return ContentReport(
      id: (json['id'] ?? '').toString(),
      reporterProfileId: (json['reporter_profile_id'] ?? '').toString(),
      targetType: (json['target_type'] ?? 'feed_post').toString(),
      targetId: (json['target_id'] ?? '').toString(),
      reason: ContentReportReason.tryParse(json['reason']),
      details: json['details']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      reviewedAt: DateTime.tryParse(json['reviewed_at']?.toString() ?? '')
          ?.toLocal(),
      reviewedBy: json['reviewed_by']?.toString(),
    );
  }
}

/// Curated reason set — mirrors the DB check constraint exactly.
enum ContentReportReason {
  spam('Spam or scam'),
  abuse('Harassment or abuse'),
  inappropriateMedia('Inappropriate media'),
  misleading('Misleading or fake content'),
  minorSafety('Minor safety concern'),
  other('Something else');

  const ContentReportReason(this.label);
  final String label;

  static ContentReportReason tryParse(Object? raw) => values.firstWhere(
        (r) => r.name == raw.toString(),
        orElse: () => ContentReportReason.other,
      );
}
