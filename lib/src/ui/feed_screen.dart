import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/enums.dart';
import '../models/feed_post.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'event_detail_screen.dart';
import '../../main.dart' show HomeShell;
import '../data/location_service.dart';
import 'radar_map_screen.dart';
import '../data/media_upload_service.dart';
import 'player_cv_screen.dart';
import 'radar_theme.dart';
import 'safeguarding_screen.dart';
import 'shell.dart';
import 'social_post_card.dart';

/// Social Feeds & Live Training Schedules — highlights, drills and tactical
/// sessions from players, academies and clubs, plus geotagged live pins and
/// scheduled open sessions discoverable with scout filters (position, age,
/// skill and radius from the viewer).
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  FeedPostKind? _kindFilter;
  final Set<String> _positionFilter = {};
  AgeBracket? _ageFilter;
  double? _radiusKm;
  double? _viewerLat;
  double? _viewerLon;
  int _scope = 0; // 0 = posts+sessions, 1 = posts only, 2 = sessions only

  /// Rebuilds the header stat line when providers tick beneath the sliver
  /// (Riverpod doesn't rebuild an ancestor SliverAppBar's title by itself).
  final ValueNotifier<int> _statsTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    ref.listenManual(radarEventsProvider, (_, _) => _statsTick.value++);
    ref.listenManual(streamBountiesProvider, (_, _) => _statsTick.value++);
  }

  @override
  void dispose() {
    _statsTick.dispose();
    super.dispose();
  }

  bool get _hasSessionFilters =>
      _positionFilter.isNotEmpty ||
      _ageFilter != null ||
      (_radiusKm != null && _radiusKm! > 0);

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(feedPostsProvider);
    final events = ref.watch(filteredEventsProvider);
    final auth = ref.watch(authProvider);
    final signedIn = auth.value is AuthSignedIn;

    // Apply feed-side filters (kind, scout filters, scope).
    final posts = _applyFilters(postsAsync.value ?? const <FeedPost>[]);

    // Live/scheduled sessions relevant to the feed (training + matches),
    // honouring the shared radar filter + our radius/age/position extras.
    final sessions = events
        .where((e) =>
            e.type == RadarEventType.trainingSession ||
            e.type == RadarEventType.match ||
            e.type == RadarEventType.trial)
        .where(_matchesScoutFilters)
        .toList();

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: RadarTheme.ink.withValues(alpha: 0.96),
              title: Row(children: [
                const Flexible(
                  child: Text('LIVE RADAR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: RadarTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                          fontSize: 17)),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _statsTick,
                    builder: (_, _, _) {
                      final liveCount = (ref.watch(radarEventsProvider).value ??
                              const <RadarEvent>[])
                          .where((e) => e.isLive)
                          .length;
                      final bountyCount = (ref.watch(streamBountiesProvider).value ??
                              const <StreamBounty>[])
                          .where((b) =>
                              b.status == 'funded' ||
                              b.status == 'accepted' ||
                              b.status == 'live')
                          .length;
                      return Text(
                        '$liveCount active · $bountyCount bounties',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: RadarTheme.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      );
                    },
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Open the Radar map',
                  icon: const Icon(Icons.travel_explore,
                      size: 21, color: RadarTheme.textDim),
                  onPressed: () => HomeShell.goTo(context, 1),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none,
                          color: RadarTheme.textDim),
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: RadarTheme.radar,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: RadarTheme.ink, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: RadarTheme.panelHigh,
                      content: Text(
                          'Notifications: new scout follows, bounty awards and '
                          'connection requests land here.'),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Safeguarding centre',
                  icon: const Icon(Icons.shield_outlined,
                      size: 21, color: RadarTheme.textDim),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SafeguardingScreen()),
                  ),
                ),
                IconButton(
                  tooltip: 'Filter feed',
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.tune, color: RadarTheme.textDim),
                      if (_kindFilter != null || _scope != 0 || _hasSessionFilters)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: RadarTheme.radar, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                  onPressed: _openFilterSheet,
                ),
              ]),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ComposerBar(
                      signedIn: signedIn,
                      onCompose: _openComposer,
                      onLivePin: _openLivePinDialog,
                    ),
                  ],
                ),
              ),
            ),
            if (posts.isEmpty && sessions.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dynamic_feed_outlined,
                          size: 44, color: RadarTheme.textDim),
                      SizedBox(height: 12),
                      Text('Nothing here yet',
                          style: TextStyle(
                              color: RadarTheme.textPrimary, fontSize: 16)),
                      SizedBox(height: 6),
                      Text(
                        'Post a highlight or drop a live pin to appear here.',
                        style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (_scope != 2 && posts.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: SectionHeader('Latest posts',
                      trailing: Text('${posts.length}',
                          style: const TextStyle(
                              color: RadarTheme.textDim, fontSize: 12))),
                ),
                SliverList.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SocialPostCard(
                      post: posts[i],
                      onOpenAuthor: () => _openAuthor(posts[i]),
                      onDelete: () => _confirmDelete(posts[i]),
                      onOpenMapDeepLink: () => _openPostOnRadar(posts[i]),
                    ),
                  ),
                ),
              ],
              if (_scope != 1 && sessions.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: SectionHeader('Live & scheduled sessions',
                      trailing: Text('${sessions.length}',
                          style: const TextStyle(
                              color: RadarTheme.textDim, fontSize: 12))),
                ),
                SliverList.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, i) {
                    final e = sessions[i];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _SessionCard(
                        event: e,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => EventDetailScreen(event: e))),
                      ),
                    );
                  },
                ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<FeedPost> _applyFilters(List<FeedPost> all) {
    var list = all;
    if (_kindFilter != null) {
      list = list.where((p) => p.kind == _kindFilter).toList();
    }
    return list;
  }

  bool _matchesScoutFilters(RadarEvent e) {
    if (_ageFilter != null && !_ageFilter!.matches(e.minAge, e.maxAge)) {
      return false;
    }
    if (_positionFilter.isNotEmpty) {
      final wanted = _positionFilter.map((p) => p.toLowerCase()).toSet();
      final have = e.positionsRequired.map((p) => p.toLowerCase()).toSet();
      if (wanted.intersection(have).isEmpty) return false;
    }
    if (_radiusKm != null &&
        _radiusKm! > 0 &&
        _viewerLat != null &&
        _viewerLon != null) {
      final d = distanceKm(
        lat1: _viewerLat!,
        lon1: _viewerLon!,
        lat2: e.latitude,
        lon2: e.longitude,
      );
      if (d > _radiusKm!) return false;
    }
    return true;
  }

  void _openAuthor(FeedPost post) {
    final profiles = ref.read(profilesProvider).value ?? const [];
    UserProfile? profile;
    for (final p in profiles) {
      if (p.id == post.authorProfileId) profile = p;
    }
    final author = profile;
    if (author == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerCvScreen(profile: author),
    ));
  }

  Future<void> _confirmDelete(FeedPost post) async {
    final session = ref.read(sessionProvider);
    if (session?.profileId != post.authorProfileId) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RadarTheme.panelHigh,
        title: const Text('Delete post?'),
        content: const Text('This removes the post from the public feed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RadarTheme.alert),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(feedPostsProvider.notifier).deletePost(post.id);
    }
  }

  Future<void> _openComposer() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposerSheet(),
    );
    if (result == true) {
      await ref.read(feedPostsProvider.notifier).refresh();
    }
  }

  /// Feed → Radar deep link: resolves the post's pin to the most specific
  /// coordinate available (the post's own GPS tag, else the linked session's
  /// real venue coordinates) and flies the live map to it.
  void _openPostOnRadar(FeedPost post) {
    double? lat = post.latitude;
    double? lon = post.longitude;
    String? venue = post.areaName;
    if (lat == null || lon == null) {
      // Fall back to the poster's live/scheduled session coordinates.
      final events = ref.read(radarEventsProvider).value ?? const <RadarEvent>[];
      for (final e in events) {
        if (e.hostProfileId != post.authorProfileId) continue;
        if (e.latitude == 0 && e.longitude == 0) continue;
        lat = e.latitude;
        lon = e.longitude;
        venue ??= e.safeLocationLabel();
        break;
      }
    }
    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            'This post has no map pin — open the player\'s schedule instead.'),
      ));
      return;
    }
    HomeShell.goTo(context, 1); // Radar tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RadarMapScreen.focusFromOutside(
        context,
        lat: lat!,
        lon: lon!,
        venue: venue,
      );
    });
  }

  Future<void> _openLivePinDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LivePinSheet(),
    );
    if (result == true) {
      ref.invalidate(radarEventsProvider);
    }
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RadarTheme.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FilterSheet(
        kindFilter: _kindFilter,
        scope: _scope,
        positionFilter: _positionFilter,
        ageFilter: _ageFilter,
        radiusKm: _radiusKm,
        hasViewer: _viewerLat != null,
        onApply: (kind, scope, positions, age, radius, useMyRegion) {
          setState(() {
            _kindFilter = kind;
            _scope = scope;
            _positionFilter
              ..clear()
              ..addAll(positions);
            _ageFilter = age;
            _radiusKm = radius;
            if (useMyRegion && radius != null && radius > 0) {
              // The viewer's position comes from their profile's regional
              // base mapped onto the radar layout (same projection the map
              // uses), so the radius filter works without GPS permissions.
              final session = ref.read(sessionProvider);
              _viewerLat = session?.viewerLatitude ?? 5.6037;
              _viewerLon = session?.viewerLongitude ?? -0.1870;
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- composer bar

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.signedIn,
    required this.onCompose,
    required this.onLivePin,
  });

  final bool signedIn;
  final VoidCallback onCompose;
  final VoidCallback onLivePin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer,
                  color: RadarTheme.radar, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signedIn
                      ? 'Share highlights, drills & tactical sessions'
                      : 'Sign in to post and drop live pins',
                  style: const TextStyle(
                      color: RadarTheme.textDim, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: signedIn ? onCompose : null,
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('New post'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: signedIn ? onLivePin : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: RadarTheme.radar),
                    foregroundColor: RadarTheme.radar,
                  ),
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Live pin'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------- session card

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.event, required this.onTap});

  final RadarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.E().add_jm();
    final isLive = event.isLive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isLive
                  ? RadarTheme.radar.withValues(alpha: 0.5)
                  : RadarTheme.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isLive
                    ? RadarTheme.radar.withValues(alpha: 0.15)
                    : RadarTheme.panelHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLive ? Icons.podcasts : Icons.schedule,
                color: isLive ? RadarTheme.radar : RadarTheme.textDim,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          event.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: RadarTheme.textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: RadarTheme.radar.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('LIVE',
                              style: TextStyle(
                                  color: RadarTheme.radar,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(event.startsAt)} · ${event.safeLocationLabel()}'
                    ' · ${event.attendingCount}${event.capacity != null ? '/${event.capacity}' : ''} in',
                    style: const TextStyle(
                        color: RadarTheme.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: RadarTheme.textDim),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- composer

class _ComposerSheet extends ConsumerStatefulWidget {
  const _ComposerSheet();

  @override
  ConsumerState<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends ConsumerState<_ComposerSheet> {
  final _bodyCtrl = TextEditingController();
  final _mediaCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  FeedPostKind _kind = FeedPostKind.highlight;
  bool _busy = false;
  bool _uploading = false;
  String? _uploadError;
  String? _uploadedPlatform;
  String? _uploadedMediaKind;
  int? _uploadedDurationSeconds;

  // Location tagging: precise GPS pin (lat/lon) captured via quick actions.
  bool _locating = false;
  double? _pinLat;
  double? _pinLon;
  String? _pinLabel;

  static const _platforms = {
    'youtube.com': 'YouTube',
    'youtu.be': 'YouTube',
    'vimeo.com': 'Vimeo',
    'pi.media': 'Pi Media',
    'drive.google.com': 'Drive',
  };

  /// 'Use Current Location' — fetches device GPS and pins the spot.
  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _pinLabel = null;
    });
    try {
      final fix = await LocationService.instance.getCurrent();
      if (!mounted) return;
      setState(() {
        _locating = false;
        _pinLat = fix.lat;
        _pinLon = fix.lon;
        _pinLabel =
            'GPS pin · ${fix.lat.toStringAsFixed(4)}, ${fix.lon.toStringAsFixed(4)}';
        if (_areaCtrl.text.trim().isEmpty) {
          _areaCtrl.text = 'My current spot';
        }
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _pinLabel = e.reason;
      });
    }
  }

  /// 'Tag Training Venue' — pick one of the poster's scheduled venues.
  Future<void> _tagTrainingVenue() async {
    final picked = await showModalBottomSheet<RadarEvent>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _VenuePickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pinLat = picked.latitude;
      _pinLon = picked.longitude;
      _pinLabel = 'Venue · ${picked.safeLocationLabel()}';
      _areaCtrl.text = picked.safeLocationLabel();
    });
  }

  String? get _platform {
    final url = _mediaCtrl.text.trim().toLowerCase();
    if (url.isEmpty) return null;
    for (final host in _platforms.keys) {
      if (url.contains(host)) return _platforms[host];
    }
    return 'External link';
  }

  Future<void> _uploadVideo() async {
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final res = await MediaUploadService.instance.pickAndUpload(video: true);
      if (!mounted) return;
      if (res == null) {
        setState(() => _uploading = false);
        return;
      }
      setState(() {
        _uploading = false;
        _mediaCtrl.text = res.publicUrl;
        _uploadedMediaKind = res.mediaKind;
        _uploadedDurationSeconds = res.durationSeconds;
        _uploadedPlatform = res.durationSeconds != null
            ? 'device video · ${res.durationSeconds! ~/ 60}:${(res.durationSeconds! % 60).toString().padLeft(2, '0')}'
            : 'device photo';
      });
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = e.reason;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = 'Upload failed — check your connection and retry.';
      });
    }
  }

  Future<void> _uploadImage() async {
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final res =
          await MediaUploadService.instance.pickAndUpload(video: false);
      if (!mounted) return;
      if (res == null) {
        setState(() => _uploading = false);
        return;
      }
      setState(() {
        _uploading = false;
        _mediaCtrl.text = res.publicUrl;
        _uploadedMediaKind = res.mediaKind;
        _uploadedDurationSeconds = null;
        _uploadedPlatform = 'device photo';
      });
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = e.reason;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = 'Upload failed — check your connection and retry.';
      });
    }
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _mediaCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_bodyCtrl.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(feedPostsProvider.notifier).createPost(
          kind: _kind,
          body: _bodyCtrl.text,
          mediaUrl: _mediaCtrl.text,
          mediaPlatform: _uploadedMediaKind != null ? _uploadedPlatform : _platform,
          mediaKind: _uploadedMediaKind,
          mediaDurationSeconds: _uploadedDurationSeconds,
          areaName: _areaCtrl.text,
          latitude: _pinLat,
          longitude: _pinLon,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHigh : RadarTheme.alert,
      content: Text(ok
          ? 'Posted to the feed'
          : 'Could not publish — queued for sync when back online'),
    ));
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final bottom = view.physicalSize.height /
        view.devicePixelRatio *
        MediaQuery.of(context).viewInsets.bottom /
        view.physicalSize.height;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom * view.physicalSize.height),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New post',
                style: TextStyle(
                    color: RadarTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in FeedPostKind.values)
                  ChoiceChip(
                    label: Text('${k.emoji} ${k.label}'),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bodyCtrl,
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: InputDecoration(
                hintText: _kind == FeedPostKind.highlight
                    ? 'Describe the clip — opponent, minute, what scouts should watch…'
                    : 'What happened at the session?',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mediaCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '…or paste a highlight link (YouTube / Vimeo)',
                prefixIcon: Icon(Icons.link, size: 20),
              ),
              onChanged: (_) => setState(() {
                // A hand-pasted link replaces any device upload metadata.
                _uploadedMediaKind = null;
                _uploadedDurationSeconds = null;
              }),
            ),
            const SizedBox(height: 10),
            // Device uploads: video is capped at 3 minutes so scouts can
            // review quick highlights before committing to a live session.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _uploading ? null : _uploadVideo,
                    icon: _uploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.videocam, size: 18),
                    label: const Text('Upload video ≤ 3 min',
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _uploading ? null : _uploadImage,
                    icon: const Icon(Icons.image, size: 18),
                    label: const Text('Upload photo',
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            if (_uploadedPlatform != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: RadarTheme.radar),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Media attached ($_uploadedPlatform) — it publishes '
                        'with your post',
                        style: const TextStyle(
                            fontSize: 12, color: RadarTheme.radar),
                      ),
                    ),
                  ],
                ),
              ),
            if (_uploadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _uploadError!,
                  style: const TextStyle(
                      fontSize: 12, color: RadarTheme.alert, height: 1.3),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _areaCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Area label, e.g. “Limbe — Omnisport Annex”',
                prefixIcon: Icon(Icons.place_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            // Quick actions: precise GPS pin or a known venue/time slot.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 17),
                    label: const Text('Use Current Location',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _tagTrainingVenue,
                    icon: const Icon(Icons.sports_soccer, size: 17),
                    label: const Text('Tag Training Venue',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
            if (_pinLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(
                    _pinLat != null ? Icons.location_on : Icons.info_outline,
                    size: 15,
                    color: _pinLat != null
                        ? RadarTheme.radar
                        : RadarTheme.textDim,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_pinLabel!,
                        style: const TextStyle(
                            fontSize: 12, color: RadarTheme.textDim)),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _bodyCtrl.text.trim().isEmpty || _busy ? null : _publish,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.publish, size: 18),
              label: const Text('Publish to feed'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- venue picker

/// 'Tag Training Venue' picker: established pitches and time slots from the
/// live radar — your own sessions first, then other hosts' real venues —
/// so a post can be pinned to a place scouts recognize on the map.
class _VenuePickerSheet extends ConsumerWidget {
  const _VenuePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];
    final df = DateFormat('EEE d MMM · HH:mm');
    final mine = events
        .where((e) => e.hostProfileId == session?.profileId)
        .toList()..sort(_slotSort);
    // Everything else with a real venue — established pitches to tag.
    final others = events
        .where((e) => e.hostProfileId != session?.profileId)
        .toList()..sort(_slotSort);

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.sports_soccer, color: RadarTheme.radar, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Tag a training venue or time slot',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15.5)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Picking a slot pins the post to that venue\'s exact spot on the '
            'live Radar map.',
            style: TextStyle(fontSize: 12, color: RadarTheme.textDim),
          ),
          const SizedBox(height: 12),
          if (mine.isEmpty && others.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No venues on the radar yet — drop a Live Pin first (radar '
                'icon in the header) and its venue will appear here.',
                style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (mine.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('YOUR TIME SLOTS',
                          style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: RadarTheme.textDim)),
                    ),
                  for (final e in mine.take(4)) _venueTile(context, e, df),
                  if (others.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 6),
                      child: Text('ESTABLISHED PITCHES ON THE RADAR',
                          style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: RadarTheme.textDim)),
                    ),
                  for (final e in others.take(6)) _venueTile(context, e, df),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static int _slotSort(RadarEvent a, RadarEvent b) {
    final now = DateTime.now();
    int rank(RadarEvent e) =>
        e.isLive ? 0 : (e.startsAt.isAfter(now) ? 1 : 2);
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return rank(a) == 2
        ? b.startsAt.compareTo(a.startsAt)
        : a.startsAt.compareTo(b.startsAt);
  }

  Widget _venueTile(BuildContext context, RadarEvent e, DateFormat df) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context, e),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(
                e.isLive ? Icons.podcasts : Icons.schedule,
                size: 17,
                color:
                    e.isLive ? RadarTheme.radar : RadarTheme.textDim,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(
                      '${df.format(e.startsAt)} · '
                          '${e.safeLocationLabel()}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: RadarTheme.textDim),
                    ),
                  ],
                ),
              ),
              if (e.isLive)
                const Text('LIVE',
                    style: TextStyle(
                        color: RadarTheme.radar,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- live pin

class _LivePinSheet extends ConsumerStatefulWidget {
  const _LivePinSheet();

  @override
  ConsumerState<_LivePinSheet> createState() => _LivePinSheetState();
}

class _LivePinSheetState extends ConsumerState<_LivePinSheet> {
  final _titleCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  RadarEventType _type = RadarEventType.trainingSession;
  TimeOfDay _time = TimeOfDay.now();
  Duration _duration = const Duration(hours: 2);
  bool _openNow = true;
  bool _involvesMinors = false;
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _venueCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  String _fmtDay(DateTime dt) => DateFormat('EEE d MMM · HH:mm').format(dt);

  Future<void> _drop() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _areaCtrl.text.trim().isEmpty ||
        _busy) {
      return;
    }
    setState(() => _busy = true);

    final session = ref.read(sessionProvider);
    final now = DateTime.now();
    final start = _openNow
        ? now
        : DateTime(now.year, now.month, now.day, _time.hour, _time.minute);
    final end = start.add(_duration);

    final event = RadarEvent(
      id: 'pin-${now.microsecondsSinceEpoch}',
      type: _type,
      title: _titleCtrl.text.trim(),
      hostProfileId: session?.profileId ?? 'demo-host',
      hostName: session?.username ?? 'Unknown host',
      latitude: session?.viewerLatitude ?? 5.6037,
      longitude: session?.viewerLongitude ?? -0.1870,
      startsAt: start,
      endsAt: end,
      precision: _involvesMinors
          ? GeoPrecision.approximate
          : GeoPrecision.exact,
      venueName:
          _venueCtrl.text.trim().isEmpty ? null : _venueCtrl.text.trim(),
      areaName: _areaCtrl.text.trim(),
      description: _openNow
          ? 'Live pin — session is happening right now.'
          : 'Scheduled open session — everyone welcome.',
      isMinorProtected: _involvesMinors,
    );

    final ok = await ref.read(radarEventsProvider.notifier).createEvent(event);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ok ? RadarTheme.panelHigh : RadarTheme.alert,
      content: Text(ok
          ? _openNow
              ? 'Live pin dropped — scouts see you on the radar now'
              : 'Session scheduled for ${_fmtDay(start)}'
          : 'Could not publish the pin — queued for sync'),
    ));
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.my_location, color: RadarTheme.radar, size: 20),
            const SizedBox(width: 8),
            const Text('Drop a live pin / schedule a session',
                style: TextStyle(
                    color: RadarTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Your pin appears on the global radar instantly. Minors are '
            'auto-fenced to a coarse area by the safety triggers.',
            style: TextStyle(color: RadarTheme.textDim, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Live now')),
              ButtonSegment(value: false, label: Text('Scheduled')),
            ],
            selected: {_openNow},
            onSelectionChanged: (s) => setState(() => _openNow = s.first),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in [
                RadarEventType.trainingSession,
                RadarEventType.match,
                RadarEventType.trial,
              ])
                ChoiceChip(
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: RadarTheme.textPrimary),
            decoration: const InputDecoration(
              hintText:
                  'e.g. “Tactical 11v11 Open Match @ Limbe Omnisport Annex”',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _venueCtrl,
            enabled: !_involvesMinors,
            style: TextStyle(
                color: _involvesMinors
                    ? RadarTheme.textDim
                    : RadarTheme.textPrimary),
            decoration: InputDecoration(
              hintText: _involvesMinors
                  ? 'Venue hidden for minor protection'
                  : 'Venue name (optional)',
              prefixIcon: const Icon(Icons.stadium_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _areaCtrl,
            style: const TextStyle(color: RadarTheme.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Area label, e.g. “Limbe — Omnisport Annex”',
              prefixIcon: Icon(Icons.place_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openNow
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _time,
                          );
                          if (picked != null) {
                            setState(() => _time = picked);
                          }
                        },
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(_openNow
                      ? 'Starting now'
                      : 'At ${_time.format(context)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showSlider(
                      context: context,
                    );
                    if (picked != null) {
                      setState(() => _duration = picked);
                    }
                  },
                  icon: const Icon(Icons.timelapse, size: 18),
                  label: Text(_duration.inHours == 0
                      ? '${_duration.inMinutes} min'
                      : '${_duration.inHours} h'),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: RadarTheme.gold,
            title: const Text('Involves minors / U-teams',
                style:
                    TextStyle(color: RadarTheme.textPrimary, fontSize: 14)),
            subtitle: const Text(
                'Location auto-locked to the coarse area label',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            value: _involvesMinors,
            onChanged: (v) => setState(() => _involvesMinors = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _drop,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_openNow ? Icons.podcasts : Icons.event_available,
                    size: 18),
            label: Text(_openNow ? 'Drop live pin' : 'Schedule session'),
          ),
        ],
      ),
    );
  }
}

Future<Duration?> showSlider({required BuildContext context}) async {
  double value = 2;
  final result = await showDialog<Duration>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: RadarTheme.panelHigh,
        title: const Text('Duration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: value,
              min: 0.5,
              max: 6,
              divisions: 11,
              label: value == value.roundToDouble()
                  ? '${value.toInt()} h'
                  : '${(value * 60).toInt()} min',
              onChanged: (v) => setState(() => value = v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  ctx,
                  Duration(
                      minutes: (value * 60).round())), // accept fractional
              child: const Text('Done')),
        ],
      ),
    ),
  );
  return result;
}

// ------------------------------------------------------------------ filter UI

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.kindFilter,
    required this.scope,
    required this.positionFilter,
    required this.ageFilter,
    required this.radiusKm,
    required this.hasViewer,
    required this.onApply,
  });

  final FeedPostKind? kindFilter;
  final int scope;
  final Set<String> positionFilter;
  final AgeBracket? ageFilter;
  final double? radiusKm;
  final bool hasViewer;
  final void Function(
    FeedPostKind? kind,
    int scope,
    Set<String> positions,
    AgeBracket? age,
    double? radius,
    bool useMyRegion,
  ) onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late FeedPostKind? _kind = widget.kindFilter;
  late int _scope = widget.scope;
  late final Set<String> _positions = Set.of(widget.positionFilter);
  late AgeBracket? _age = widget.ageFilter;
  late double? _radius = widget.radiusKm;
  late bool _useMyRegion = widget.hasViewer;

  static const _positionsList = [
    'GK', 'CB', 'LB', 'RB', 'CM', 'DM', 'AM', 'LW', 'RW', 'ST'
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Filter feed',
                style: TextStyle(
                    color: RadarTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            const Text('Post type',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All posts'),
                  selected: _kind == null,
                  onSelected: (_) => setState(() => _kind = null),
                ),
                for (final k in FeedPostKind.values)
                  ChoiceChip(
                    label: Text('${k.emoji} ${k.label}'),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Show',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Everything')),
                ButtonSegment(value: 1, label: Text('Posts')),
                ButtonSegment(value: 2, label: Text('Sessions')),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Scout filters (sessions)',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Position scouted',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _positionsList)
                  FilterChip(
                    label: Text(p,
                        style: const TextStyle(fontSize: 12)),
                    selected: _positions.contains(p),
                    onSelected: (on) => setState(() {
                      on ? _positions.add(p) : _positions.remove(p);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Age bracket',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Any'),
                  selected: _age == null,
                  onSelected: (_) => setState(() => _age = null),
                ),
                for (final b in AgeBracket.values)
                  ChoiceChip(
                    label: Text(b.label),
                    selected: _age == b,
                    onSelected: (_) => setState(() => _age = b),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: RadarTheme.radar,
              title: const Text('Radius from my regional base',
                  style: TextStyle(color: RadarTheme.textPrimary, fontSize: 14)),
              subtitle: Text(
                  _useMyRegion
                      ? 'Only sessions within the slider distance'
                      : 'Enable to filter by distance',
                  style: const TextStyle(
                      color: RadarTheme.textDim, fontSize: 12)),
              value: _useMyRegion,
              onChanged: (v) => setState(() {
                _useMyRegion = v;
                if (v && _radius == null) _radius = 50;
              }),
            ),
            if (_useMyRegion && _radius != null)
              Slider(
                value: _radius!,
                min: 5,
                max: 500,
                divisions: 49,
                label: '${_radius!.round()} km',
                onChanged: (v) => setState(() => _radius = v),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _kind = null;
                        _scope = 0;
                        _positions.clear();
                        _age = null;
                        _radius = null;
                        _useMyRegion = false;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => widget.onApply(_kind, _scope,
                        Set.of(_positions), _age, _radius, _useMyRegion),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
