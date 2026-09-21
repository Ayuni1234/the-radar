import '../analytics/tracking_session.dart';
import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/feed_post.dart';
import '../models/market.dart';
import '../models/market_order.dart';
import '../models/market_sales.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
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
    streamBounties
      ..clear()
      ..addAll(_seedBounties());
    marketShops
      ..clear()
      ..addAll(_seedMarketShops());
    marketListings
      ..clear()
      ..addAll(_seedMarketListings());
    marketOrders.clear();
    marketSales.clear();
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

  // ------------------------------------------------------------- stream bounties

  // ------------------------------------------------------------- pitch market

  /// Demo merchant storefronts (offline exploration of The PitchMarket).
  static final List<MarketShop> marketShops = _seedMarketShops();

  /// Demo gear listings (offline exploration of The PitchMarket).
  static final List<MarketListing> marketListings = _seedMarketListings();

  /// Demo buyer orders (fee-split receipts). Empty until the user runs a
  /// demo checkout, mirroring a fresh wallet's empty order history.
  static final List<MarketOrder> marketOrders = <MarketOrder>[];

  /// Demo merchant payout receipts (sales ledger for the seller dashboard).
  static final List<MarketSale> marketSales = <MarketSale>[];

  static final List<StreamBounty> streamBounties = _seedBounties();

  static List<StreamBounty> _seedBounties() => <StreamBounty>[
        StreamBounty(
          id: 'demo-bounty-1',
          posterProfileId: 'demo-scout-1',
          posterName: 'Marta Segura',
          title:
              '90-min tactical stream of Player #7 — Thursday showcase match',
          brief:
              'Offering 50 Pi for a stable 90-minute tactical stream focusing on '
                  'Player #7 (RW). Wide angle from the halfway line, phone gimbal '
                  'if available. Kickoff Thursday 16:00 local.',
          areaName: 'Limbe — Omnisport Annex',
          venueName: 'Omnisport Annex Stadium, main pitch',
          latitude: 4.0227,
          longitude: 9.1992,
          amountPi: 50,
          durationMinutes: 90,
          kickoffAt: DateTime.now().add(const Duration(days: 2, hours: 5)),
          status: 'funded',
          createdAt: DateTime.now().subtract(const Duration(hours: 7)),
        ),
        StreamBounty(
          id: 'demo-bounty-2',
          posterProfileId: 'demo-agent-1',
          posterName: 'D. Ferreira',
          title: 'Full match stream — Sunday league derby',
          brief:
              'Need both goals plus buildup play on film. 60–90 minutes, stable '
                  '4G upload. Payment released when the broadcast completes.',
          areaName: 'Accra — Cantonments',
          latitude: 5.6210,
          longitude: -0.1730,
          amountPi: 35,
          durationMinutes: 80,
          kickoffAt: DateTime.now().add(const Duration(days: 1, hours: 9)),
          status: 'open',
          createdAt: DateTime.now().subtract(const Duration(hours: 22)),
        ),
        StreamBounty(
          id: 'demo-bounty-3',
          posterProfileId: 'demo-club-1',
          posterName: 'FC Atlas',
          title: 'U19 league fixture — pitch-side tactical cam',
          brief: 'Completed and paid. Thank you to the local videographer!',
          areaName: 'Casablanca — Maarif',
          latitude: 33.5936,
          longitude: -7.6323,
          amountPi: 60,
          durationMinutes: 90,
          status: 'completed',
          streamerProfileId: 'demo-player-1',
          streamerName: 'leftboot_lucas',
          watchedMinutes: 94,
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
          completedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];

  // ------------------------------------------------------------- pitch market

  static List<MarketShop> _seedMarketShops() => <MarketShop>[
        MarketShop(
          id: 'demo-shop-1',
          ownerId: 'demo-agent-1',
          shopName: 'Accra Creator Depot',
          description:
              'Pro streaming gear for West-African creators. Same-day pickup '
              'in Osu, delivery across Greater Accra. Every unit tested '
              'on-camera.',
          piUid: 'pi-uid-demo-5',
          locationArea: 'Accra — Osu',
          isVerified: true,
          createdAt: DateTime(2026, 5, 14),
        ),
        MarketShop(
          id: 'demo-shop-2',
          ownerId: 'demo-scout-1',
          shopName: 'Valencia Pitch-Side Tech',
          description:
              'Gimbals, tripods and lapel mics for pitch-side streaming. '
              'Ex-rental units, serviced yearly.',
          piUid: 'pi-uid-demo-2',
          locationArea: 'Valencia — Ruzafa',
          isVerified: true,
          createdAt: DateTime(2026, 6, 30),
        ),
      ];

  static List<MarketListing> _seedMarketListings() => <MarketListing>[
        MarketListing(
          id: 'demo-listing-1',
          shopId: 'demo-shop-1',
          title: 'DJI Osmo Mobile 6 Gimbal',
          category: 'gimbal',
          pricePi: 45,
          condition: 'brand_new',
          stockQuantity: 3,
          mediaUrls: <String>['https://images.pi-radar.demo/osmo6-1.jpg'],
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        MarketListing(
          id: 'demo-listing-2',
          shopId: 'demo-shop-1',
          title: 'Rode Wireless GO II (dual channel)',
          category: 'audio',
          pricePi: 38.5,
          condition: 'like_new',
          stockQuantity: 1,
          mediaUrls: const <String>[],
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        MarketListing(
          id: 'demo-listing-3',
          shopId: 'demo-shop-2',
          title: 'Manfrotto Befree GT Pro Tripod',
          category: 'tripod',
          pricePi: 29,
          condition: 'good',
          stockQuantity: 5,
          mediaUrls: const <String>[],
          createdAt: DateTime.now().subtract(const Duration(days: 8)),
        ),
        MarketListing(
          id: 'demo-listing-4',
          shopId: 'demo-shop-2',
          title: 'Pixel 8 Pro — streaming spare (256 GB)',
          category: 'phone',
          pricePi: 320,
          condition: 'like_new',
          stockQuantity: 1,
          mediaUrls: const <String>[],
          createdAt: DateTime.now().subtract(const Duration(days: 12)),
        ),
        MarketListing(
          id: 'demo-listing-5',
          shopId: 'demo-shop-1',
          title: 'Godox SL60W key light + softbox',
          category: 'lighting',
          pricePi: 52.75,
          condition: 'brand_new',
          stockQuantity: 2,
          mediaUrls: const <String>[],
          createdAt: DateTime.now().subtract(const Duration(days: 15)),
        ),
      ];

  // --------------------------------------------------------- tracking sessions

  /// Deterministic AI-tracking session for the completed demo bounty —
  /// powers the Match Analytics preview in demo mode.
  static final trackingSessions = <String, TrackingSession>{
    'demo-bounty-3': TrackingSession.synthetic(
      id: 'demo-track-1',
      bountyId: 'demo-bounty-3',
      playerLabel: 'Player #9 (ST) — Atlas U19',
      seed: 11,
    ),
    'demo-bounty-1': TrackingSession.synthetic(
      id: 'demo-track-2',
      bountyId: 'demo-bounty-1',
      playerLabel: 'Player #7 (RW) — Limbe showcase',
      seed: 7,
      durationMin: 45,
    ),
  };
}
