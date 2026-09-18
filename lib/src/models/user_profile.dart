import 'enums.dart';

/// A person or organisation profile on The Radar.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.piUid,
    required this.username,
    required this.role,
    required this.credibilityScore,
    required this.kycVerified,
    required this.createdAt,
    this.displayName,
    this.bio,
    this.country,
    this.city,
    this.positions = const [],
    this.footballCv,
    this.videoShowcaseUrls = const [],
    this.clubAffiliation,
    this.isMinor = false,
    this.geohashArea,
    this.rating = 0,
    this.avatarUrl,
    this.updatedAt,
  });

  final String id;
  final String piUid;
  final String username;
  final UserRole role;
  final double credibilityScore;
  final bool kycVerified;
  final DateTime createdAt;

  final String? displayName;
  final String? bio;
  final String? country;
  final String? city;

  /// Playing positions (players): GK, CB, LB, RB, CM, DM, AM, LW, RW, ST.
  final List<String> positions;

  /// Free-text football CV / career history.
  final String? footballCv;

  /// Links to video showcases (YouTube, Pi media, etc.).
  final List<String> videoShowcaseUrls;

  final String? clubAffiliation;

  /// Safeguarding flag — minors get location masking everywhere.
  final bool isMinor;

  /// Coarse area token (e.g. city district) used instead of coordinates
  /// for approximate locations.
  final String? geohashArea;

  final double rating;
  final String? avatarUrl;
  final DateTime? updatedAt;

  bool get isScout => role == UserRole.scout;
  bool get isVerifiedRole =>
      role == UserRole.scout || role == UserRole.club || role == UserRole.academy;

  String get bestName => displayName?.isNotEmpty == true ? displayName! : username;

  factory UserProfile.fromJson(Map<String, Object?> json) {
    List<String> stringList(Object? v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String && v.isNotEmpty) return v.split(',').map((e) => e.trim()).toList();
      return const [];
    }

    return UserProfile(
      id: (json['id'] ?? '').toString(),
      piUid: (json['pi_uid'] ?? '').toString(),
      username: (json['username'] ?? 'anonymous').toString(),
      role: UserRole.tryParse(json['role']?.toString()) ?? UserRole.player,
      credibilityScore: (json['credibility_score'] as num?)?.toDouble() ?? 0,
      kycVerified: json['kyc_verified'] as bool? ?? false,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      displayName: json['display_name']?.toString(),
      bio: json['bio']?.toString(),
      country: json['country']?.toString(),
      city: json['city']?.toString(),
      positions: stringList(json['positions']),
      footballCv: json['football_cv']?.toString(),
      videoShowcaseUrls: stringList(json['video_showcase_urls']),
      clubAffiliation: json['club_affiliation']?.toString(),
      isMinor: json['is_minor'] as bool? ?? false,
      geohashArea: json['geohash_area']?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      avatarUrl: json['avatar_url']?.toString(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString())?.toLocal(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'pi_uid': piUid,
        'username': username,
        'role': role.name,
        'credibility_score': credibilityScore,
        'kyc_verified': kycVerified,
        if (displayName != null) 'display_name': displayName,
        if (bio != null) 'bio': bio,
        if (country != null) 'country': country,
        if (city != null) 'city': city,
        'positions': positions,
        if (footballCv != null) 'football_cv': footballCv,
        'video_showcase_urls': videoShowcaseUrls,
        if (clubAffiliation != null) 'club_affiliation': clubAffiliation,
        'is_minor': isMinor,
        if (geohashArea != null) 'geohash_area': geohashArea,
        'rating': rating,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  UserProfile copyWith({
    String? id,
    String? piUid,
    String? username,
    UserRole? role,
    double? credibilityScore,
    bool? kycVerified,
    DateTime? createdAt,
    String? displayName,
    String? bio,
    String? country,
    String? city,
    List<String>? positions,
    String? footballCv,
    List<String>? videoShowcaseUrls,
    String? clubAffiliation,
    bool? isMinor,
    String? geohashArea,
    double? rating,
    String? avatarUrl,
    DateTime? updatedAt,
  }) =>
      UserProfile(
        id: id ?? this.id,
        piUid: piUid ?? this.piUid,
        username: username ?? this.username,
        role: role ?? this.role,
        credibilityScore: credibilityScore ?? this.credibilityScore,
        kycVerified: kycVerified ?? this.kycVerified,
        createdAt: createdAt ?? this.createdAt,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        country: country ?? this.country,
        city: city ?? this.city,
        positions: positions ?? this.positions,
        footballCv: footballCv ?? this.footballCv,
        videoShowcaseUrls: videoShowcaseUrls ?? this.videoShowcaseUrls,
        clubAffiliation: clubAffiliation ?? this.clubAffiliation,
        isMinor: isMinor ?? this.isMinor,
        geohashArea: geohashArea ?? this.geohashArea,
        rating: rating ?? this.rating,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
