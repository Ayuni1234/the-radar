import 'enums.dart';

/// A live football activity blip on the Radar map.
class RadarEvent {
  RadarEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.hostProfileId,
    required this.hostName,
    required this.latitude,
    required this.longitude,
    required this.startsAt,
    required this.endsAt,
    required this.precision,
    DateTime? createdAt,
    this.venueName,
    this.areaName,
    this.description,
    this.capacity,
    this.attendingCount = 0,
    this.minAge,
    this.maxAge,
    this.positionsRequired = const [],
    this.isMinorProtected = false,
    this.boostedUntil,
    this.bountyPi,
    this.updatedAt,
  });

  final String id;
  final RadarEventType type;
  final String title;
  final String hostProfileId;
  final String hostName;
  final double latitude;
  final double longitude;
  final DateTime startsAt;
  final DateTime endsAt;
  final GeoPrecision precision;
  late final DateTime createdAt = DateTime.now();

  /// Venue name — only shown when precision is exact.
  final String? venueName;

  /// Human-readable area label (e.g. "North London"). Always shown; for
  /// minor-protected events it is the ONLY location information exposed.
  final String? areaName;
  final String? description;
  final int? capacity;
  final int attendingCount;
  final int? minAge;
  final int? maxAge;

  /// Positions the host is looking for (empty = open to all).
  final List<String> positionsRequired;
  final bool isMinorProtected;
  final DateTime? boostedUntil;
  final double? bountyPi;
  final DateTime? updatedAt;

  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  bool get isUpcoming => DateTime.now().isBefore(startsAt);

  bool get isBoosted {
    final b = boostedUntil;
    return b != null && b.isAfter(DateTime.now());
  }

  /// The location string it is safe to render for the current viewer.
  String safeLocationLabel({bool viewerIsHost = false}) {
    if (precision == GeoPrecision.exact || viewerIsHost) {
      return venueName ?? areaName ?? 'Exact location shared privately';
    }
    return areaName ?? 'Approximate area';
  }

  /// Whether full coordinates may be sent to this viewer.
  bool exposesCoordinatesTo({bool viewerIsHost = false}) =>
      precision == GeoPrecision.exact || viewerIsHost;

  factory RadarEvent.fromJson(Map<String, Object?> json) {
    DateTime? date(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    List<String> stringList(Object? v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      return const [];
    }

    return RadarEvent(
      id: (json['id'] ?? '').toString(),
      type: RadarEventType.tryParse(json['event_type']?.toString()),
      title: (json['title'] ?? 'Untitled event').toString(),
      hostProfileId: (json['host_profile_id'] ?? '').toString(),
      hostName: (json['host_name'] ?? 'Unknown host').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      startsAt: date(json['starts_at']) ?? DateTime.now(),
      endsAt: date(json['ends_at']) ??
          (date(json['starts_at']) ?? DateTime.now()).add(const Duration(hours: 2)),
      precision: GeoPrecision.fromRaw(json['geo_precision']?.toString()),
      createdAt: date(json['created_at']) ?? DateTime.now(),
      venueName: json['venue_name']?.toString(),
      areaName: json['area_name']?.toString(),
      description: json['description']?.toString(),
      capacity: json['capacity'] as int?,
      attendingCount: (json['attending_count'] as num?)?.toInt() ?? 0,
      minAge: json['min_age'] as int?,
      maxAge: json['max_age'] as int?,
      positionsRequired: stringList(json['positions_required']),
      isMinorProtected:
          json['is_minor_protected'] as bool? ?? false,
      boostedUntil: date(json['boosted_until']),
      bountyPi: (json['bounty_pi'] as num?)?.toDouble(),
      updatedAt: date(json['updated_at']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'event_type': type.name,
        'title': title,
        'host_profile_id': hostProfileId,
        'host_name': hostName,
        'latitude': latitude,
        'longitude': longitude,
        'starts_at': startsAt.toIso8601String(),
        'ends_at': endsAt.toIso8601String(),
        'geo_precision': precision.storageValue,
        'venue_name': venueName,
        'area_name': areaName,
        'description': description,
        'capacity': capacity,
        'attending_count': attendingCount,
        'min_age': minAge,
        'max_age': maxAge,
        'positions_required': positionsRequired,
        'is_minor_protected': isMinorProtected,
        if (boostedUntil != null) 'boosted_until': boostedUntil!.toIso8601String(),
        if (bountyPi != null) 'bounty_pi': bountyPi,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  RadarEvent copyWith({
    String? id,
    RadarEventType? type,
    String? title,
    String? hostProfileId,
    String? hostName,
    double? latitude,
    double? longitude,
    DateTime? startsAt,
    DateTime? endsAt,
    GeoPrecision? precision,
    DateTime? createdAt,
    String? venueName,
    String? areaName,
    String? description,
    int? capacity,
    int? attendingCount,
    int? minAge,
    int? maxAge,
    List<String>? positionsRequired,
    bool? isMinorProtected,
    DateTime? boostedUntil,
    double? bountyPi,
    DateTime? updatedAt,
  }) =>
      RadarEvent(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        hostProfileId: hostProfileId ?? this.hostProfileId,
        hostName: hostName ?? this.hostName,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        precision: precision ?? this.precision,
        createdAt: createdAt ?? this.createdAt,
        venueName: venueName ?? this.venueName,
        areaName: areaName ?? this.areaName,
        description: description ?? this.description,
        capacity: capacity ?? this.capacity,
        attendingCount: attendingCount ?? this.attendingCount,
        minAge: minAge ?? this.minAge,
        maxAge: maxAge ?? this.maxAge,
        positionsRequired: positionsRequired ?? this.positionsRequired,
        isMinorProtected: isMinorProtected ?? this.isMinorProtected,
        boostedUntil: boostedUntil ?? this.boostedUntil,
        bountyPi: bountyPi ?? this.bountyPi,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
