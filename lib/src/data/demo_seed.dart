import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/feed_post.dart';
import '../models/radar_event.dart';
import '../models/user_profile.dart';

/// Offline dataset used when Supabase is not configured (demo mode).
class DemoSeed {
  static final List<UserProfile> profiles = <UserProfile>[
    UserProfile(
      id: 'demo-player-1',
      piUid: 'pi-uid-demo-1',
      username: 'leftboot_lucas',
      role: UserRole.player,
      credibilityScore: 62,
      kycVerified: true,
      createdAt: DateTime(2026, 1, 12),
      displayName: 'Lucas "Left Boot" Moreau',
      bio: 'Left winger. Two footed, quick over 30m. Looking for trials in Europe.',
      country: 'France',
      city: 'Lyon',
      positions: ['LW', 'ST'],
      footballCv: 'U16–U19 Lyon regional league. 21 goals last season. '
          'District select team 2025. Full match footage available.',
      videoShowcaseUrls: [
        'https://youtube.com/watch?v=demo-lucas-goals',
        'https://youtube.com/watch?v=demo-lucas-assists',
      ],
      clubAffiliation: 'AS Lyon District',
      isMinor: false,
      geohashArea: 'Lyon — 7e arrondissement',
      rating: 4.2,
    ),
    UserProfile(
      id: 'demo-scout-1',
      piUid: 'pi-uid-demo-2',
      username: 'eye4talent',
      role: UserRole.scout,
      credibilityScore: 88,
      kycVerified: true,
      createdAt: DateTime(2025, 11, 2),
      displayName: 'Marta Segura',
      bio: 'Former La Liga analyst. Scouting Iberia & West Africa.',
      country: 'Spain',
      city: 'Valencia',
      positions: const [],
      footballCv: '12 years club scouting. ex-Valencia CF youth analyst. '
          'UEFA B licence. Specialism: wide attackers, U15–U23.',
      videoShowcaseUrls: const [],
      clubAffiliation: 'Independent',
      geohashArea: 'Valencia — Ruzafa',
      rating: 4.9,
    ),
    UserProfile(
      id: 'demo-club-1',
      piUid: 'pi-uid-demo-3',
      username: 'fc_atlas_academy',
      role: UserRole.club,
      credibilityScore: 91,
      kycVerified: true,
      createdAt: DateTime(2025, 9, 20),
      displayName: 'FC Atlas',
      bio: 'Tier-2 professional club. First team & academy intakes every season.',
      country: 'Morocco',
      city: 'Casablanca',
      geohashArea: 'Casablanca — Ain Diab',
      rating: 4.7,
    ),
    UserProfile(
      id: 'demo-academy-1',
      piUid: 'pi-uid-demo-4',
      username: 'goldencoast_fc',
      role: UserRole.academy,
      credibilityScore: 84,
      kycVerified: true,
      createdAt: DateTime(2025, 10, 15),
      displayName: 'Golden Coast Academy',
      bio: 'Development academy, ages 10–18. Trials every quarter.',
      country: 'Ghana',
      city: 'Accra',
      geohashArea: 'Accra — Airport Residential',
      rating: 4.5,
    ),
    UserProfile(
      id: 'demo-agent-1',
      piUid: 'pi-uid-demo-5',
      username: 'bridge_the_gap',
      role: UserRole.agent,
      credibilityScore: 71,
      kycVerified: true,
      createdAt: DateTime(2026, 2, 3),
      displayName: 'Kofi Mensah',
      bio: 'FIFA-licensed agent. West Africa ↔ Europe placements.',
      country: 'Ghana',
      city: 'Accra',
      geohashArea: 'Accra — Osu',
      rating: 4.1,
    ),
    UserProfile(
      id: 'demo-parent-1',
      piUid: 'pi-uid-demo-6',
      username: 'proud_rugby_dad',
      role: UserRole.parent,
      credibilityScore: 45,
      kycVerified: true,
      createdAt: DateTime(2026, 3, 8),
      displayName: 'David O.',
      bio: 'Parent of a U14 goalkeeper. Managing showcase schedule.',
      country: 'England',
      city: 'Manchester',
      geohashArea: 'Manchester — Didsbury',
      rating: 4.0,
    ),
    UserProfile(
      id: 'demo-player-minor',
      piUid: 'pi-uid-demo-7',
      username: 'young_keeper_2012',
      role: UserRole.player,
      credibilityScore: 30,
      kycVerified: false,
      createdAt: DateTime(2026, 4, 1),
      displayName: 'Z. Okafor (U14)',
      bio: 'U14 goalkeeper. Profiles of minors are location-masked.',
      country: 'England',
      city: 'Manchester',
      positions: ['GK'],
      footballCv: 'District U13 squad. Penalties saved: 4 in 6 shootouts.',
      videoShowcaseUrls: ['https://youtube.com/watch?v=demo-young-keeper'],
      clubAffiliation: 'Manchester Youth League',
      isMinor: true,
      geohashArea: 'South Manchester area',
      rating: 0,
    ),
  ];

  static final List<RadarEvent> events = <RadarEvent>[
    RadarEvent(
      id: 'demo-event-1',
      type: RadarEventType.trial,
      title: 'Open trials — U18 & U21',
      hostProfileId: 'demo-academy-1',
      hostName: 'Golden Coast Academy',
      latitude: 5.6210,
      longitude: -0.1730,
      startsAt: DateTime.now().add(const Duration(days: 3, hours: 4)),
      endsAt: DateTime.now().add(const Duration(days: 3, hours: 8)),
      precision: GeoPrecision.exact,
      venueName: 'Accra Sports Stadium, Pitch 2',
      areaName: 'Accra — Cantonments',
      description:
          'Open field trials. Bring boots, shin pads and water. Scouts from 4 clubs attending.',
      capacity: 120,
      attendingCount: 87,
      minAge: 16,
      maxAge: 21,
      isMinorProtected: false,
      bountyPi: 5.0,
    ),
    RadarEvent(
      id: 'demo-event-2',
      type: RadarEventType.match,
      title: 'League fixture — Atlas U19 vs rivals',
      hostProfileId: 'demo-club-1',
      hostName: 'FC Atlas',
      latitude: 33.5936,
      longitude: -7.6323,
      startsAt: DateTime.now().add(const Duration(hours: 26)),
      endsAt: DateTime.now().add(const Duration(hours: 28)),
      precision: GeoPrecision.exact,
      venueName: 'Stade Père Jégo',
      areaName: 'Casablanca — Maarif',
      description: 'Top-of-table U19 clash. Registered scouts get pitch-side access.',
      capacity: 40,
      attendingCount: 22,
      minAge: 0,
      maxAge: 19,
      isMinorProtected: true,
      bountyPi: null,
    ),
    RadarEvent(
      id: 'demo-event-3',
      type: RadarEventType.trainingSession,
      title: 'Morning technical session (invite)',
      hostProfileId: 'demo-scout-1',
      hostName: 'Marta Segura',
      latitude: 39.4699,
      longitude: -0.3763,
      startsAt: DateTime.now().add(const Duration(hours: 14)),
      endsAt: DateTime.now().add(const Duration(hours: 16)),
      precision: GeoPrecision.approximate,
      venueName: null,
      areaName: 'Valencia — Turia river beds',
      description: 'Small-group technical work. Exact venue shared after registration.',
      capacity: 16,
      attendingCount: 9,
      isMinorProtected: false,
    ),
    RadarEvent(
      id: 'demo-event-4',
      type: RadarEventType.tournament,
      title: 'Easter Invitational Cup (U14)',
      hostProfileId: 'demo-parent-1',
      hostName: 'Manchester Youth League',
      latitude: 53.4167,
      longitude: -2.2500,
      startsAt: DateTime.now().add(const Duration(days: 9, hours: 2)),
      endsAt: DateTime.now().add(const Duration(days: 10, hours: 4)),
      precision: GeoPrecision.approximate,
      venueName: null,
      areaName: 'South Manchester area',
      description: 'U14 invitational. Exact venues hidden — approximate area only.',
      capacity: 24,
      attendingCount: 18,
      minAge: 13,
      maxAge: 14,
      isMinorProtected: true,
    ),
    RadarEvent(
      id: 'demo-event-5',
      type: RadarEventType.match,
      title: 'Friendly — Lyon select vs Bourg',
      hostProfileId: 'demo-player-1',
      hostName: 'AS Lyon District',
      latitude: 45.7485,
      longitude: 4.8500,
      startsAt: DateTime.now().add(const Duration(hours: 5)),
      endsAt: DateTime.now().add(const Duration(hours: 7)),
      precision: GeoPrecision.exact,
      venueName: 'Stade des Brotteaux',
      areaName: 'Lyon — 6e arrondissement',
      description: 'Open friendly, scouts welcome. Lucas starting up front.',
      capacity: 60,
      attendingCount: 31,
      isMinorProtected: false,
    ),
  ];

  // -- Demo P2P requests (scoped to the signed-in demo user) ----------------

  static final List<ConnectionRequest> _demoRequests = <ConnectionRequest>[];
  static String? _demoRequestsFor;

  /// Returns demo requests involving [profileId], generating a plausible
  /// mixed inbox (received + sent, pending + resolved) on first call.
  static List<ConnectionRequest> requestsFor(String profileId) {
    if (_demoRequestsFor != profileId) {
      _demoRequestsFor = profileId;
      _demoRequests
        ..clear()
        ..addAll([
          ConnectionRequest(
            id: 'demo-req-1',
            fromProfile: 'demo-academy-1',
            toProfile: profileId,
            type: ConnectionType.trialInvite,
            status: ConnectionStatus.pending,
            eventId: 'demo-event-1',
            message:
                'We watched your clips — impressive left foot. Join our U21 '
                'trial block next week?',
            createdAt: DateTime.now().subtract(const Duration(hours: 5)),
            fromName: 'Golden Coast Academy',
            eventTitle: 'Open trials — U18 & U21',
          ),
          ConnectionRequest(
            id: 'demo-req-2',
            fromProfile: 'demo-club-1',
            toProfile: profileId,
            type: ConnectionType.contact,
            status: ConnectionStatus.pending,
            message: 'Scouting coordinator at Valencia Youth. Open to a chat?',
            createdAt: DateTime.now().subtract(const Duration(hours: 26)),
            fromName: 'Valencia Youth SC',
          ),
          ConnectionRequest(
            id: 'demo-req-3',
            fromProfile: 'demo-agent-1',
            toProfile: profileId,
            type: ConnectionType.contact,
            status: ConnectionStatus.declined,
            message: 'Representing players in Ligue 2 — interested?',
            createdAt: DateTime.now().subtract(const Duration(days: 4)),
            fromName: 'Marc Dupont (Agent)',
          ),
          ConnectionRequest(
            id: 'demo-req-4',
            fromProfile: profileId,
            toProfile: 'demo-player-1',
            type: ConnectionType.contact,
            status: ConnectionStatus.accepted,
            message: 'Saw your game vs Lyon — great engine in midfield.',
            createdAt: DateTime.now().subtract(const Duration(days: 2)),
            toName: 'Leftboot Lucas',
          ),
          ConnectionRequest(
            id: 'demo-req-5',
            fromProfile: profileId,
            toProfile: 'demo-academy-1',
            type: ConnectionType.trialApplication,
            status: ConnectionStatus.pending,
            eventId: 'demo-event-1',
            message: 'Applying as a winger — 3 seasons of regional football.',
            createdAt: DateTime.now().subtract(const Duration(hours: 9)),
            toName: 'Golden Coast Academy',
            eventTitle: 'Open trials — U18 & U21',
          ),
        ]);
    }
    return List.of(_demoRequests);
  }

  /// Diagnostics: restores the demo stores to their seeded state.
  static void resetDemoStores() {
    _demoRequestsFor = null;
    _demoRequests.clear();
    feedPosts
      ..clear()
      ..addAll(_seedFeedPosts());
  }

  /// Applies a status change to a demo request in place; true if found.
  static bool respondToDemoRequest(String id, ConnectionStatus status) {
    for (var i = 0; i < _demoRequests.length; i++) {
      final r = _demoRequests[i];
      if (r.id == id) {
        _demoRequests[i] = ConnectionRequest(
          id: r.id,
          fromProfile: r.fromProfile,
          toProfile: r.toProfile,
          type: r.type,
          status: status,
          eventId: r.eventId,
          message: r.message,
          createdAt: r.createdAt,
          updatedAt: DateTime.now(),
          fromName: r.fromName,
          toName: r.toName,
          eventTitle: r.eventTitle,
        );
        return true;
      }
    }
    return false;
  }

  // ------------------------------------------------------------- feed posts

  static final List<FeedPost> feedPosts = _seedFeedPosts();

  static List<FeedPost> _seedFeedPosts() => <FeedPost>[
        FeedPost(
          id: 'demo-feed-1',
          authorProfileId: 'demo-academy-1',
          authorName: 'Golden Coast Academy',
          authorRole: 'academy',
          kind: FeedPostKind.highlight,
          body:
              'Match highlights from last weekend\'s 4-1 win — full reel on our channel. Watch the #7 solo goal at 03:12.',
          mediaUrl: 'https://youtube.com/watch?v=demo-academy-reel',
          mediaPlatform: 'YouTube',
          areaName: 'Accra — Cantonments',
          latitude: 5.6210,
          longitude: -0.1730,
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        FeedPost(
          id: 'demo-feed-2',
          authorProfileId: 'demo-player-1',
          authorName: 'leftboot_lucas',
          authorRole: 'player',
          kind: FeedPostKind.drill,
          body:
              'Sunday drilling session open to visitors — wall passes, first-touch ladders and 30 mins of small-sided games. Bring a ball.',
          areaName: 'Valencia — Turia river beds',
          latitude: 39.4699,
          longitude: -0.3763,
          createdAt: DateTime.now().subtract(const Duration(hours: 19)),
        ),
        FeedPost(
          id: 'demo-feed-3',
          authorProfileId: 'demo-club-1',
          authorName: 'FC Atlas',
          authorRole: 'club',
          kind: FeedPostKind.tactical,
          body:
              'Open tactical session on Thursday: pressing traps in a 4-4-2 diamond, followed by an 11v11. Scouts welcome pitch-side.',
          mediaUrl: 'https://vimeo.com/demo-atlas-tactics',
          mediaPlatform: 'Vimeo',
          areaName: 'Casablanca — Maarif',
          latitude: 33.5936,
          longitude: -7.6323,
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        FeedPost(
          id: 'demo-feed-4',
          authorProfileId: 'demo-player-minor',
          authorName: 'Z. Okafor (U14)',
          authorRole: 'player',
          kind: FeedPostKind.general,
          body:
              'Trained with the district keeper coach today — six penalty saves in the shootout drill. Looking forward to the next fixture.',
          areaName: 'South Manchester area',
          isMinorPoster: true,
          createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 4)),
        ),
      ];
}
