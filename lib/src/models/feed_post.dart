import 'dart:math' as math;

/// Kind of feed post in the social feed.
enum FeedPostKind {
  highlight('Highlight', '🎬'),
  drill('Training drill', '🏃'),
  tactical('Tactical session', '🧠'),
  general('Post', '📣');

  const FeedPostKind(this.label, this.emoji);
  final String label;
  final String emoji;

  static FeedPostKind tryParse(Object? raw) => values.firstWhere(
        (k) => k.name == raw.toString(),
        orElse: () => FeedPostKind.general,
      );
}

/// One post in the social feed: match highlights, training drills or
/// tactical sessions uploaded by players, academies and clubs.
///
/// Posts by minor-posters are fenced at the database level: coordinates are
/// nulled and only a coarse area label survives (see
/// `enforce_feed_post_privacy` trigger in supabase/schema.sql).
class FeedPost {
  FeedPost({
    required this.id,
    required this.authorProfileId,
    required this.authorName,
    required this.authorRole,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.mediaUrl,
    this.mediaPlatform,
    this.mediaKind,
    this.mediaDurationSeconds,
    this.areaName,
    this.latitude,
    this.longitude,
    this.scheduledAt,
    this.isMinorPoster = false,
  });

  final String id;
  final String authorProfileId;
  final String authorName;
  final String authorRole;
  final FeedPostKind kind;
  final String body;
  final DateTime createdAt;

  /// Secure highlight link (YouTube / Vimeo / Pi Media / Drive).
  final String? mediaUrl;

  /// Recognized host of [mediaUrl], e.g. 'YouTube'.
  final String? mediaPlatform;

  /// 'link' (external embed), 'device_video' or 'device_photo' (uploads).
  final String? mediaKind;

  /// Device-video length in seconds — always ≤ 180 (the 3-minute cap).
  final int? mediaDurationSeconds;

  /// Coarse area label — the only location a post is allowed to show.
  final String? areaName;
  final double? latitude;
  final double? longitude;

  /// Optional training/match schedule attached to the post — rendered on
  /// the card's Calendar pill and as a countdown chip on the media hero.
  final DateTime? scheduledAt;

  final bool isMinorPoster;

  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get hasLocation => latitude != null && longitude != null;

  /// True when the post carries an upcoming training/match schedule.
  bool get hasSchedule =>
      scheduledAt != null && scheduledAt!.isAfter(DateTime.now());

  /// True when [mediaUrl] is a device-uploaded video (≤ 3 min highlight).
  bool get isDeviceVideo => mediaKind == 'device_video';

  Map<String, Object?> toJson() => {
        'author_profile_id': authorProfileId,
        'author_name': authorName,
        'author_role': authorRole,
        'kind': kind.name,
        'body': body,
        'media_url': (mediaUrl?.isEmpty ?? true) ? null : mediaUrl,
        'media_platform':
            (mediaPlatform?.isEmpty ?? true) ? null : mediaPlatform,
        'media_kind': mediaKind,
        'media_duration_s': mediaDurationSeconds,
        'area_name': (areaName?.isEmpty ?? true) ? null : areaName,
        'latitude': latitude,
        'longitude': longitude,
        'scheduled_at': scheduledAt?.toIso8601String(),
      };

  factory FeedPost.fromJson(Map<String, Object?> json) {
    String? str(Object? v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return FeedPost(
      id: (json['id'] ?? '').toString(),
      authorProfileId: (json['author_profile_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'Unknown').toString(),
      authorRole: (json['author_role'] ?? 'player').toString(),
      kind: FeedPostKind.tryParse(json['kind']),
      body: (json['body'] ?? '').toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      mediaUrl: str(json['media_url']),
      mediaPlatform: str(json['media_platform']),
      mediaKind: str(json['media_kind']),
      mediaDurationSeconds: (json['media_duration_s'] as num?)?.toInt(),
      areaName: str(json['area_name']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      scheduledAt: DateTime.tryParse(json['scheduled_at']?.toString() ?? '')
          ?.toLocal(),
      isMinorPoster: json['is_minor_poster'] as bool? ?? false,
    );
  }
}

/// Haversine distance between two coordinates, in kilometres.
double distanceKm({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}
