/// A Pi-backed "Talent Watcher" bounty: a scout posts escrowed Pi for a
/// live tactical stream; a local videographer accepts and gets released
/// the escrow upon broadcast completion.
///
/// Lifecycle: open → funded (escrow paid) → accepted (streamer assigned)
/// → live → completed. Cancelled/disputed are terminal failure paths.
/// The state machine is enforced by the `enforce_bounty_lifecycle` trigger
/// and release is poster-only via the `release_bounty` SECURITY DEFINER RPC.
class StreamBounty {
  StreamBounty({
    required this.id,
    required this.posterProfileId,
    required this.posterName,
    required this.title,
    required this.brief,
    required this.areaName,
    required this.amountPi,
    required this.durationMinutes,
    required this.status,
    required this.createdAt,
    this.venueName,
    this.latitude,
    this.longitude,
    this.kickoffAt,
    this.streamerProfileId,
    this.streamerName,
    this.streamUrl,
    this.watchedMinutes = 0,
    this.completedAt,
  });

  final String id;
  final String posterProfileId;
  final String posterName;
  final String title;
  final String brief;

  /// Coarse area label (e.g. "Limbe — Omnisport Annex").
  final String areaName;
  final String? venueName;
  final double? latitude;
  final double? longitude;
  final double amountPi;

  /// Requested stream length in minutes (e.g. a 90-minute match).
  final int durationMinutes;
  final DateTime? kickoffAt;

  /// open | funded | accepted | live | completed | cancelled | disputed
  final String status;
  final String? streamerProfileId;
  final String? streamerName;

  /// The streamer's published link (Pi Media / YouTube live / external).
  final String? streamUrl;
  final int watchedMinutes;
  final DateTime? completedAt;
  final DateTime createdAt;

  bool get isFunded =>
      status == 'funded' || status == 'accepted' || status == 'live';
  bool get isOpen => status == 'open';
  bool get isLive => status == 'live';
  bool get isClosed =>
      status == 'completed' || status == 'cancelled' || status == 'disputed';

  String get statusLabel => switch (status) {
        'open' => 'Awaiting funding',
        'funded' => 'Funded · open to streamers',
        'accepted' => 'Streamer assigned',
        'live' => 'LIVE',
        'completed' => 'Paid out',
        'cancelled' => 'Cancelled',
        'disputed' => 'In review',
        _ => status,
      };

  StreamBounty copyWith({String? status, String? streamerProfileId, String? streamerName, String? streamUrl}) =>
      StreamBounty(
        id: id,
        posterProfileId: posterProfileId,
        posterName: posterName,
        title: title,
        brief: brief,
        areaName: areaName,
        amountPi: amountPi,
        durationMinutes: durationMinutes,
        status: status ?? this.status,
        createdAt: createdAt,
        venueName: venueName,
        latitude: latitude,
        longitude: longitude,
        kickoffAt: kickoffAt,
        streamerProfileId: streamerProfileId ?? this.streamerProfileId,
        streamerName: streamerName ?? this.streamerName,
        streamUrl: streamUrl ?? this.streamUrl,
        watchedMinutes: watchedMinutes,
        completedAt: completedAt,
      );

  factory StreamBounty.fromJson(Map<String, Object?> json) {
    String? str(Object? v) {
      final s = v?.toString();
      return (s == null || s.isEmpty) ? null : s;
    }

    return StreamBounty(
      id: (json['id'] ?? '').toString(),
      posterProfileId: (json['poster_profile_id'] ?? '').toString(),
      posterName: (json['poster_name'] ?? 'Unknown').toString(),
      title: (json['title'] ?? 'Bounty').toString(),
      brief: (json['brief'] ?? '').toString(),
      areaName: (json['area_name'] ?? 'Global').toString(),
      venueName: str(json['venue_name']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      amountPi: (json['amount_pi'] as num?)?.toDouble() ?? 0,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 90,
      kickoffAt:
          DateTime.tryParse(json['kickoff_at']?.toString() ?? '')?.toLocal(),
      status: (json['status'] ?? 'open').toString(),
      streamerProfileId: str(json['streamer_profile_id']),
      streamerName: str(json['streamer_name']),
      streamUrl: str(json['stream_url']),
      watchedMinutes: (json['watched_minutes'] as num?)?.toInt() ?? 0,
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? '')
          ?.toLocal(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}
