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
    this.dominantFoot,
    this.birthYear,
    this.heightCm,
    this.footballCv,
    this.videoShowcaseUrls = const [],
    this.clubAffiliation,
    this.isMinor = false,
    this.isAdmin = false,
    this.geohashArea,
    this.rating = 0,
    this.avatarUrl,
    this.updatedAt,
    this.onboardedAt,
    this.isPublic = true,
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

  /// Player vitals: preferred foot, birth year (age band derivable), height.
  final String? dominantFoot; // 'left' | 'right'
  final int? birthYear;
  final int? heightCm;

  /// Free-text football CV / career history.
  final String? footballCv;

  /// Links to video showcases (YouTube, Pi media, etc.).
  final List<String> videoShowcaseUrls;

  final String? clubAffiliation;

  /// Safeguarding flag — minors get location masking everywhere.
  final bool isMinor;

  /// Moderation capability (profiles.is_admin). Granted only by operator
  /// SQL — the app never writes this column; [toJson] omits it so a stolen
  /// client payload cannot escalate privileges.
  final bool isAdmin;

  /// Coarse area token (e.g. city district) used instead of coordinates
  /// for approximate locations.
  final String? geohashArea;

  final double rating;
  final String? avatarUrl;
  final DateTime? updatedAt;

  /// When the guided onboarding (role → region → profile) was completed.
  /// Null means the user has not been onboarded yet.
  final DateTime? onboardedAt;

  /// Whether the profile appears in the public directory and search.
  /// Private profiles stay functional for their owner but are hidden from
  /// other users' listings.
  final bool isPublic;

  bool get needsOnboarding => onboardedAt == null;

  /// Approximate age from birth year (privacy-friendly: no full DOB stored).
  int? get age {
    final y = birthYear;
    return y == null || y <= 1900 || y > DateTime.now().year
        ? null
        : DateTime.now().year - y;
  }

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
      dominantFoot: json['dominant_foot']?.toString(),
      birthYear: json['birth_year'] as int?,
      heightCm: json['height_cm'] as int?,
      footballCv: json['football_cv']?.toString(),
      videoShowcaseUrls: stringList(json['video_showcase_urls']),
      clubAffiliation: json['club_affiliation']?.toString(),
      isMinor: json['is_minor'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      geohashArea: json['geohash_area']?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      avatarUrl: json['avatar_url']?.toString(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString())?.toLocal(),
      onboardedAt: DateTime.tryParse((json['onboarded_at'] ?? '').toString())?.toLocal(),
      isPublic: json['is_public'] as bool? ?? true,
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
        if (dominantFoot != null) 'dominant_foot': dominantFoot,
        if (birthYear != null) 'birth_year': birthYear,
        if (heightCm != null) 'height_cm': heightCm,
        if (footballCv != null) 'football_cv': footballCv,
        'video_showcase_urls': videoShowcaseUrls,
        if (clubAffiliation != null) 'club_affiliation': clubAffiliation,
        'is_minor': isMinor,
        // is_admin deliberately absent — operator-SQL-only capability.
        if (geohashArea != null) 'geohash_area': geohashArea,
        'rating': rating,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (onboardedAt != null) 'onboarded_at': onboardedAt!.toIso8601String(),
        'is_public': isPublic,
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
    String? dominantFoot,
    int? birthYear,
    int? heightCm,
    String? footballCv,
    List<String>? videoShowcaseUrls,
    String? clubAffiliation,
    bool? isMinor,
    bool? isAdmin,
    String? geohashArea,
    double? rating,
    String? avatarUrl,
    DateTime? updatedAt,
    DateTime? onboardedAt,
    bool? isPublic,
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
        dominantFoot: dominantFoot ?? this.dominantFoot,
        birthYear: birthYear ?? this.birthYear,
        heightCm: heightCm ?? this.heightCm,
        footballCv: footballCv ?? this.footballCv,
        videoShowcaseUrls: videoShowcaseUrls ?? this.videoShowcaseUrls,
        clubAffiliation: clubAffiliation ?? this.clubAffiliation,
        isMinor: isMinor ?? this.isMinor,
        isAdmin: isAdmin ?? this.isAdmin,
        geohashArea: geohashArea ?? this.geohashArea,
        rating: rating ?? this.rating,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        updatedAt: updatedAt ?? this.updatedAt,
        onboardedAt: onboardedAt ?? this.onboardedAt,
        isPublic: isPublic ?? this.isPublic,
      );
}
