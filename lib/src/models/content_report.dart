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

  final ContentReportStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  bool get isOpen => status == ContentReportStatus.open ||
      status == ContentReportStatus.reviewing;

  ContentReport copyWith({
    ContentReportStatus? status,
    DateTime? reviewedAt,
    String? reviewedBy,
  }) =>
      ContentReport(
        id: id,
        reporterProfileId: reporterProfileId,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        details: details,
        status: status ?? this.status,
        createdAt: createdAt,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        reviewedBy: reviewedBy ?? this.reviewedBy,
      );

  Map<String, Object?> toJson() => {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason.db,
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
      status: ContentReportStatus.tryParse(json['status']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      reviewedAt: DateTime.tryParse(json['reviewed_at']?.toString() ?? '')
          ?.toLocal(),
      reviewedBy: json['reviewed_by']?.toString(),
    );
  }
}

/// Report lifecycle — mirrors the DB check constraint exactly.
enum ContentReportStatus {
  open('Open', 'Just filed, waiting for first look'),
  reviewing('Reviewing', 'A moderator is on it'),
  resolved('Resolved', 'Action was taken'),
  dismissed('Dismissed', 'Closed with no action needed');

  const ContentReportStatus(this.label, this.hint);
  final String label;
  final String hint;

  static ContentReportStatus tryParse(Object? raw) => values.firstWhere(
        (s) => s.name == raw.toString(),
        orElse: () => ContentReportStatus.open,
      );
}

/// Curated reason set — mirrors the DB check constraint exactly. The
/// snake-case [db] token is what travels to Postgres (the constraint lists
/// 'inappropriate_media'/'minor_safety', which cannot be Dart enum names).
enum ContentReportReason {
  spam('Spam or scam', 'spam'),
  abuse('Harassment or abuse', 'abuse'),
  inappropriateMedia('Inappropriate media', 'inappropriate_media'),
  misleading('Misleading or fake content', 'misleading'),
  minorSafety('Minor safety concern', 'minor_safety'),
  other('Something else', 'other');

  const ContentReportReason(this.label, this.db);
  final String label;

  /// The wire/DB token — the exact string in the check constraint.
  final String db;

  static ContentReportReason tryParse(Object? raw) {
    final s = raw.toString();
    return values.firstWhere(
      (r) => r.db == s || r.name == s,
      orElse: () => ContentReportReason.other,
    );
  }
}
