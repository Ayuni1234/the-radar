import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app_brand.dart';
import '../diagnostics/diagnostics.dart';
import '../models/enums.dart';
import '../models/content_report.dart';
import '../models/feed_post.dart';
import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/radar_providers.dart';
import 'event_detail_screen.dart';
import '../../main.dart' show HomeShell;
import '../data/location_service.dart';
import '../data/radar_repository.dart';
import 'next_training_overlay.dart';
import 'player_live_session_screen.dart';
import 'radar_map_screen.dart';
import 'bounty_board_screen.dart';
import '../data/media_upload_service.dart';
import '../state/theme_controller.dart';
import 'player_cv_screen.dart';
import 'radar_theme.dart';
import 'media_viewer.dart';
import 'sheet_scaffold.dart';
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
    final activeSessions = sessions.where((event) => event.isLive).length;
    final openGigs = (ref.watch(streamBountiesProvider).value ??
            const <StreamBounty>[])
        .where((bounty) =>
            bounty.status == 'open' ||
            bounty.status == 'funded' ||
            bounty.status == 'accepted' ||
            bounty.status == 'live')
        .length;

    // Reels-first: posts play as full-bleed vertical reels (the
    // hackathon mockup's Reels screen). The discovery body below is what
    // the tab shows while there is nothing to page through: a filter that
    // excludes every post, a session-only scope, or an empty feed.
    if (posts.isNotEmpty) {
      return Scaffold(
        backgroundColor: RadarTheme.ink,
        body: _buildReels(posts, signedIn),
      );
    }

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [              SliverAppBar(
              pinned: true,
              backgroundColor: RadarTheme.ink.withValues(alpha: 0.96),
              title: Row(children: [
                 Flexible(
                  child: Text(AppBrand.name,
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
                        style:  TextStyle(
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
                  icon:  Icon(Icons.travel_explore,
                      size: 21, color: RadarTheme.textDim),
                  onPressed: () => HomeShell.goTo(context, 1),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                       Icon(Icons.notifications_none,
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
                     SnackBar(
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
                  icon:  Icon(Icons.shield_outlined,
                      size: 21, color: RadarTheme.textDim),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const SafeguardingScreen()),
                  ),
                ),
                const _ThemeHeaderToggle(),
                IconButton(
                  tooltip: 'Filter feed',
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                       Icon(Icons.tune, color: RadarTheme.textDim),
                      if (_kindFilter != null || _scope != 0 || _hasSessionFilters)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration:  BoxDecoration(
                                color: RadarTheme.radar, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                  onPressed: _openFilterSheet,
                ),
              ]),
            ),
            // Floating "Next Live Training" overlay card (hackathon mockup):
            // pitch + start time + real-time countdown + GO TO PROFILE /
            // WATCH LIVE deep-link CTA straight into the player's live
            // GPS session broadcast.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: NextTrainingOverlay(
                  onOpenProfile: _openPlayerSession,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _DiscoveryHero(
                  activeSessions: activeSessions,
                  openGigs: openGigs,
                  eventCount: events.length,
                  onExplore: () => HomeShell.goTo(context, 1),
                  onGigs: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BountyBoardScreen(),
                    ),
                  ),
                ),
              ),
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
               SliverFillRemaining(
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
              if (_scope != 1 && sessions.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: SectionHeader('Live & scheduled sessions',
                      trailing: Text('${sessions.length}',
                          style:  TextStyle(
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

  // ------------------------------------------------------------------ reels

  /// Full-bleed vertical reels — the hackathon mockup's Reels screen: one
  /// post per page, its media edge to edge, with the overlay card carrying
  /// the caption, hashtags, the posting player and their next live session.
  Widget _buildReels(List<FeedPost> posts, bool signedIn) {
    return PageView.builder(
      // Restart at the top whenever the number of reels changes (a filter
      // applied, the feed refreshed) instead of leaving the pager past its
      // end.
      key: ValueKey('reels-${posts.length}'),
      scrollDirection: Axis.vertical,
      itemCount: posts.length,
      itemBuilder: (context, i) => _reel(posts[i], posts, signedIn),
    );
  }

  Widget _reel(FeedPost post, List<FeedPost> posts, bool signedIn) {
    final author = _authorOf(post);
    final training = _trainingFor(post, author);
    final size = MediaQuery.sizeOf(context);
    // Short viewports (landscape phones, small browser windows) drop the
    // overlay's optional lines instead of overflowing the card.
    final compact = size.height < 700;
    final veryCompact = size.height < 560;

    // Phone-shaped reel: on a desktop window the media keeps a phone's
    // width (centred) instead of stretching edge to edge.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Edge-to-edge media — the mockup's full-bleed photo.
            PostMediaSurface(
              post: post,
              heroTag: 'media-hero-${post.id}',
              onTap: () => _openViewer(post, posts),
            ),
            // Legibility scrims: the media runs under the header and the
            // caption/card stack at the bottom.
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB308060F), Color(0x0008060F)],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: veryCompact ? 300 : (compact ? 370 : 450),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE608060F), Color(0x0008060F)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 4,
              top: 4,
              child: _reelHeader(post, size.width),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 10,
              child: _reelOverlay(
                post,
                author,
                training,
                compact: compact,
                veryCompact: veryCompact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reels header — the mockup's floating chrome: the mark + wordmark on the
  /// left, notifications / compose / overflow on the right. The discovery
  /// tools (sessions, filters, map, safeguarding, theme) live in the overflow
  /// menu so the media keeps the frame's full width.
  Widget _reelHeader(FeedPost post, double width) {
    final ownPost = ref.read(sessionProvider)?.profileId == post.authorProfileId;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadarMark(size: 24),
                  const SizedBox(width: 8),
                  Text(
                    AppBrand.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      letterSpacing: 2.2,
                      shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _reelIcon(
          icon: Icons.notifications_none,
          tooltip: 'Notifications',
          onPressed: _showNotifications,
        ),
        _reelIcon(
          icon: Icons.edit_note,
          tooltip: 'New post',
          onPressed: _openComposer,
        ),
        PopupMenuButton<_ReelMenuAction>(
          tooltip: 'More',
          iconSize: 22,
          icon: const Icon(Icons.more_vert, color: Colors.white, size: 22),
          padding: const EdgeInsets.only(left: 4, right: 8),
          onSelected: (action) => _onReelMenu(action, post, ownPost),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _ReelMenuAction.sessions,
              child: Text('Live & scheduled sessions'),
            ),
            const PopupMenuItem(
              value: _ReelMenuAction.filter,
              child: Text('Filter feed'),
            ),
            if (post.hasLocation)
              const PopupMenuItem(
                value: _ReelMenuAction.postOnMap,
                child: Text('View post on the Radar map'),
              ),
            const PopupMenuItem(
              value: _ReelMenuAction.map,
              child: Text('Open the Radar map'),
            ),
            const PopupMenuItem(
              value: _ReelMenuAction.theme,
              child: Text('Switch light / dark theme'),
            ),
            const PopupMenuItem(
              value: _ReelMenuAction.safety,
              child: Text('Safeguarding centre'),
            ),
            if (!ownPost)
              const PopupMenuItem(
                value: _ReelMenuAction.report,
                child: Text('Report post'),
              ),
            if (ownPost)
              const PopupMenuItem(
                value: _ReelMenuAction.delete,
                child: Text('Delete post'),
              ),
          ],
        ),
      ],
    );
  }

  /// Overlay header icon: white on a soft dark disc so it stays legible over
  /// bright media.
  Widget _reelIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 22,
        color: Colors.white,
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
      ),
    );
  }

  void _onReelMenu(_ReelMenuAction action, FeedPost post, bool ownPost) {
    switch (action) {
      case _ReelMenuAction.sessions:
        _openSessionsSheet();
      case _ReelMenuAction.filter:
        _openFilterSheet();
      case _ReelMenuAction.postOnMap:
        _openPostOnRadar(post);
      case _ReelMenuAction.map:
        HomeShell.goTo(context, 1);
      case _ReelMenuAction.theme:
        final next = ref.read(themeModeProvider.notifier).toggle();
        RadarTheme.current = next == RadarBrightness.dark
            ? RadarPalette.dark
            : RadarPalette.light;
        persistThemePreference(next);
      case _ReelMenuAction.safety:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SafeguardingScreen(),
        ));
      case _ReelMenuAction.report:
        _openReportSheet(post);
      case _ReelMenuAction.delete:
        _confirmDelete(post);
    }
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RadarTheme.panelHigh,
      content: const Text('Notifications: new scout follows, bounty awards '
          'and connection requests land here.'),
    ));
  }

  /// The overlay stack for one reel, mockup-shaped: the caption and hashtag
  /// line sit straight on the media, and a translucent card underneath carries
  /// the posting player and their next live session.
  Widget _reelOverlay(
    FeedPost post,
    UserProfile? author,
    NextTrainingInfo? training, {
    bool compact = false,
    bool veryCompact = false,
  }) {
    final title = post.body.split('\n').first.trim();
    final area = (post.areaName ?? '').trim();
    // Inline hashtags, mockup-style — "#PiScout #Talent" under the caption
    // rather than the old boxed chips.
    final tags = '#${AppBrand.nameTitleCase.replaceAll(' ', '')} '
        '#${post.kind.label.replaceAll(' ', '')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? post.kind.label : title,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  shadows: [Shadow(color: Color(0xAA000000), blurRadius: 12)],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tags,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFCBB9FF),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Color(0xAA000000), blurRadius: 12)],
                ),
              ),
              if (area.isNotEmpty && !veryCompact) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 12, color: Color(0xCCFFFFFF)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            // Translucent violet panel, the mockup's "Joung Pame" card.
            color: const Color(0xFF221A3C).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reelAuthorRow(post, author, showBio: !compact),
              const SizedBox(height: 11),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.10),
              ),
              const SizedBox(height: 11),
              if (training != null)
                NextTrainingOverlayCard(
                  flat: true,
                  info: training,
                  onGoToProfile: () =>
                      _openPlayerSession(training.event.hostProfileId),
                  onWatchLive: () =>
                      _openPlayerSession(training.event.hostProfileId),
                )
              else ...[
                // No session on the radar for this player yet: keep the
                // mockup's training block shape and point the CTA at their
                // profile.
                const Text(
                  'Next Live Training Info:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'No session scheduled yet',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                TrainingCtaButton(
                  label: 'GO TO PROFILE',
                  icon: Icons.person,
                  onPressed: () => _openAuthor(post),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Player row, mockup-shaped: avatar, name with the blue tick, then
  /// "Age: 28" / "Position: Player" / "Bio: …" lines.
  Widget _reelAuthorRow(
    FeedPost post,
    UserProfile? author, {
    bool showBio = true,
  }) {
    final positions = author?.positions ?? const <String>[];
    final roleLabel = positions.isNotEmpty
        ? positions.join(' · ')
        : (post.authorRole.isNotEmpty ? _capitalize(post.authorRole) : '');
    final bio = (author?.bio ?? '').trim();
    final avatarUrl = (author?.avatarUrl ?? '').trim();

    return InkWell(
      onTap: () => _openAuthor(post),
      borderRadius: BorderRadius.circular(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  RadarTheme.radar.withValues(alpha: 0.6),
                  RadarTheme.pi.withValues(alpha: 0.6),
                ],
              ),
            ),
            padding: const EdgeInsets.all(1.6),
            child: ClipOval(
              child: avatarUrl.isEmpty
                  ? const ColoredBox(
                      color: Color(0xFF2B2149),
                      child: Icon(Icons.person, size: 19, color: Colors.white70),
                    )
                  : Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFF2B2149),
                        child:
                            Icon(Icons.person, size: 19, color: Colors.white70),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author?.bestName ?? post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (author?.kycVerified ?? false) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified,
                          size: 13, color: Color(0xFF4CC3FF)),
                    ],
                  ],
                ),
                if (author?.age != null)
                  _reelMeta('Age', '${author!.age}'),
                if (roleLabel.isNotEmpty)
                  // Players get the mockup's "Position"; everyone else on the
                  // feed (academies, clubs, scouts) is labelled by role.
                  _reelMeta(positions.isNotEmpty ? 'Position' : 'Role', roleLabel),
                if (showBio && bio.isNotEmpty)
                  _reelMeta('Bio', bio, maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One "Label: value" line of the reel card's player block — mockup
  /// typography: muted, one line each, truncating instead of wrapping.
  Widget _reelMeta(String label, String value, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label: $value',
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 11.5,
          height: 1.3,
        ),
      ),
    );
  }

  String _capitalize(String value) => value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';

  /// The reel's training line: the posting player's own next (or live)
  /// session when they have one, else the next session on the radar at all.
  NextTrainingInfo? _trainingFor(FeedPost post, UserProfile? author) {
    final events = ref.read(radarEventsProvider).value ?? const <RadarEvent>[];
    RadarEvent? mine;
    for (final e in events) {
      if (e.hostProfileId != post.authorProfileId) continue;
      if (!(e.isLive || e.isUpcoming)) continue;
      if (mine == null || e.startsAt.isBefore(mine.startsAt)) mine = e;
    }
    if (mine != null) {
      return NextTrainingInfo(
        event: mine,
        playerName: author?.bestName ?? post.authorName,
      );
    }
    return resolveNextTraining(events);
  }

  UserProfile? _authorOf(FeedPost post) {
    final profiles = ref.read(profilesProvider).value ?? const <UserProfile>[];
    for (final p in profiles) {
      if (p.id == post.authorProfileId) return p;
    }
    return null;
  }

  /// Reel → full-screen gallery: every device photo and video poster in the
  /// feed, opening on the tapped one. Link-only reels have nothing to zoom.
  void _openViewer(FeedPost post, List<FeedPost> posts) {
    final gallery = <ViewerMedia>[];
    for (final p in posts) {
      final url = p.isDevicePhoto
          ? p.mediaUrl
          : p.isDeviceVideo
              ? p.mediaPosterUrl
              : null;
      if (url == null || url.isEmpty) continue;
      gallery.add(ViewerMedia(
        imageUrl: url,
        authorName: p.authorName,
        postId: p.id,
      ));
    }
    final initial = gallery.indexWhere((m) => m.postId == post.id);
    if (initial < 0) return;
    showMediaViewer(
      context,
      media: gallery,
      initialIndex: initial,
      heroTag: 'media-hero-${post.id}',
    );
  }

  /// The Reels tab keeps the feed's session list one tap away, so the
  /// discovery flow the old scrolling feed offered is still reachable.
  void _openSessionsSheet() {
    final events = ref.read(filteredEventsProvider)
        .where((e) =>
            e.type == RadarEventType.trainingSession ||
            e.type == RadarEventType.match ||
            e.type == RadarEventType.trial)
        .where(_matchesScoutFilters)
        .toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (sheetBodyContext, controller) => Container(
          decoration: BoxDecoration(
            color: RadarTheme.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: RadarTheme.stroke),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'Live & scheduled sessions',
                style: TextStyle(
                  color: RadarTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (events.isEmpty)
                Text(
                  'No sessions match your filters right now.',
                  style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
                )
              else
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SessionCard(
                      event: event,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => EventDetailScreen(event: event),
                        ));
                      },
                    ),
                  ),
            ],
          ),
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
    if (author == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Player profile not available in this session.'),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerCvScreen(profile: author),
    ));
  }

  /// Reels deep link: "GO TO PROFILE / WATCH LIVE" — opens the player's
  /// profile with the LIVE Session Info tab (countdown, GPS broadcast
  /// mini-map, watch-live navigation and set-bounty actions). Falls back
  /// to the CV screen when the host has no live/scheduled sessions.
  void _openPlayerSession(String hostProfileId) {
    final profiles = ref.read(profilesProvider).value ?? const [];
    UserProfile? profile;
    for (final p in profiles) {
      if (p.id == hostProfileId) profile = p;
    }
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Player profile not available in this session.'),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerLiveSessionScreen(profile: profile!),
    ));
  }

  Future<void> _confirmDelete(FeedPost post) async {
    final session = ref.read(sessionProvider);
    if (session != null && session.profileId != post.authorProfileId) {
      await _openReportSheet(post);
      return;
    }
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

  /// Report-content flow: reason picker + optional details, filed against
  /// the post through content_reports (RLS: reporter = self).
  Future<void> _openReportSheet(FeedPost post) async {
    final result = await openReportSheet(context,
        targetLabel: '${post.authorName}\'s ${post.kind.label.toLowerCase()} post');
    if (result == null || !mounted) return;
    final (reason, details) = result;
    final session = ref.read(sessionProvider);
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.alert,
        content: Text('Sign in to report content.'),
      ));
      return;
    }
    final (id, error) = await RadarRepository.instance.createContentReport(
      targetType: 'feed_post',
      targetId: post.id,
      reason: reason,
      details: details,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error != null ? RadarTheme.alert : RadarTheme.panelHigh,
      content: Text(error ??
          'Report received — our moderation team will review it. Thank you.'),
    ));
    if (id != null) {
      Diagnostics.instance.log('moderation', 'report filed: $id ($reason)');
    }
  }

  Future<void> _openComposer() async {
    if (await openPostComposer(context)) {
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
      backgroundColor: Colors.transparent,
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

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({
    required this.activeSessions,
    required this.openGigs,
    required this.eventCount,
    required this.onExplore,
    required this.onGigs,
  });

  final int activeSessions;
  final int openGigs;
  final int eventCount;
  final VoidCallback onExplore;
  final VoidCallback onGigs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RadarTheme.radar.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RadarTheme.radar.withValues(alpha: 0.16),
            RadarTheme.panel,
            RadarTheme.panelHigh.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Both the badge and its label flex so the mark beside them
              // always has room on a narrow phone.
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: RadarTheme.radar.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.radar, size: 14, color: RadarTheme.radar),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('GLOBAL TALENT NETWORK',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: RadarTheme.radar,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1)),
                    ),
                  ]),
                ),
              ),
              const Spacer(),
              const RadarMark(size: 38),
            ],
          ),
          const SizedBox(height: 16),
          Text('Talent is everywhere.',
              style: TextStyle(
                  color: RadarTheme.textPrimary,
                  fontSize: 25,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Find the next breakthrough on pitches around the world.',
              style: TextStyle(
                  color: RadarTheme.textDim, fontSize: 13, height: 1.4)),
          const SizedBox(height: 18),
          Row(children: [
            _HeroStat(value: '$activeSessions', label: 'LIVE NOW',
                icon: Icons.sensors, color: RadarTheme.radar),
            const SizedBox(width: 18),
            _HeroStat(value: '$eventCount', label: 'SESSIONS',
                icon: Icons.sports_soccer, color: RadarTheme.info),
            const SizedBox(width: 18),
            _HeroStat(value: '$openGigs', label: 'OPEN GIGS',
                icon: Icons.workspace_premium, color: RadarTheme.gold),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onExplore,
                icon: const Icon(Icons.travel_explore, size: 17),
                label: const Text('Explore Radar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onGigs,
                icon: const Icon(Icons.videocam_outlined, size: 17),
                label: const Text('Record & earn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RadarTheme.gold,
                  side: BorderSide(color: RadarTheme.gold.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(
                color: RadarTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: RadarTheme.textDim,
                    fontSize: 8.5,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
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
               Icon(Icons.sports_soccer,
                  color: RadarTheme.radar, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signedIn
                      ? 'Share highlights, drills & tactical sessions'
                      : 'Sign in to post and drop live pins',
                  style:  TextStyle(
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
                    side:  BorderSide(color: RadarTheme.radar),
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
                          style:  TextStyle(
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
                          child:  Text('LIVE',
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
                    style:  TextStyle(
                        color: RadarTheme.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
             Icon(Icons.chevron_right, color: RadarTheme.textDim),
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
  final _linkCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  FeedPostKind _kind = FeedPostKind.highlight;
  bool _busy = false;

  /// True while the pick/prepare step runs (probe + byte read).
  bool _uploading = false;
  String? _uploadError;

  /// Staged device media — validated and read with preview bytes, uploaded
  /// to Supabase Storage when the post publishes.
  PickedMedia? _pickedMedia;

  /// Optional training/match schedule attached to the post — feeds the
  /// card's Calendar pill and the countdown chip on the media hero.
  DateTime? _schedule;

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
      // Graceful degradation — GPS can stall indoors or under canopy; never
      // hard-block the composer. Fall back to a live coarse label from the
      // regional base ("near Douala") so the post still carries an honest,
      // useful location.
      final session = ref.read(sessionProvider);
      final isMinor = session?.isMinor ?? false;
      final lat = session?.viewerLatitude;
      final lon = session?.viewerLongitude;
      // Privacy masking mirrors the database trigger (enforce_feed_post_privacy):
      // minors keep only their static onboarding region as coarse text —
      // no coordinates and no live fix-derived labels. Adults get the
      // city-level live label ("near Douala · 18 km away").
      final liveLabel = isMinor ? null : coarseFixLabel(lat, lon);
      final region = (session?.regionLabel ?? '').trim();
      final fallback =
          liveLabel ?? (region.isNotEmpty ? region : 'Limbe, Cameroon');
      setState(() {
        _locating = false;
        if (_pinLat == null && !isMinor && lat != null && lon != null) {
          _pinLat = lat;
          _pinLon = lon;
        }
        _pinLabel = _pinLat == null
            ? '$e — tagged $fallback instead.'
            : 'Approximate location · $fallback — GPS fix unavailable ($e)';
        if (_areaCtrl.text.trim().isEmpty) {
          _areaCtrl.text = fallback;
        }
      });
    }
  }

  /// Training Schedule — date first, then time. `null` clears it.
  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final initial = _schedule ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _schedule =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
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
    final url = _linkCtrl.text.trim().toLowerCase();
    if (url.isEmpty) return null;
    for (final host in _platforms.keys) {
      if (url.contains(host)) return _platforms[host];
    }
    return 'External link';
  }

  /// Device media selection — validates the pick and captures a real
  /// preview (the image itself, or a poster frame probed from the video).
  /// The actual Supabase Storage upload happens at publish time so a lost
  /// connection can never leave a published draft pointing at a missing
  /// file.
  Future<void> _pickMedia({required bool video}) async {
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final picked = await MediaUploadService.instance.pick(video: video);
      if (!mounted) return;
      if (picked == null) {
        setState(() => _uploading = false);
        return;
      }
      setState(() {
        _uploading = false;
        _pickedMedia = picked;
        // One media per post: a device upload replaces a pasted link.
        _linkCtrl.clear();
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
        _uploadError =
            'Could not prepare the media — pick it again and retry.';
      });
    }
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _linkCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_bodyCtrl.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);

    // Upload the staged device media first — a failure keeps the composer
    // open with the draft intact so the user can read the reason and retry.
    String mediaUrl = '';
    String? mediaPlatform;
    String? mediaKind;
    int? mediaDuration;
    String? mediaPoster;
    final picked = _pickedMedia;
    if (picked != null) {
      try {
        final res = await MediaUploadService.instance.upload(picked);
        mediaUrl = res.publicUrl;
        mediaKind = res.mediaKind;
        mediaDuration = res.durationSeconds;
        mediaPoster = res.posterUrl;
        mediaPlatform = res.durationSeconds != null
            ? 'device video · ${res.durationSeconds! ~/ 60}:${(res.durationSeconds! % 60).toString().padLeft(2, '0')}'
            : 'device photo';
      } on MediaUploadRetryableException catch (e) {
        // Transport is down — queue the whole publish (media + post) in the
        // outbox; it replays automatically when connectivity returns.
        if (!mounted) return;
        final outcome = await ref.read(feedPostsProvider.notifier).createPost(
              kind: _kind,
              body: _bodyCtrl.text,
              mediaPlatform: _platform,
              areaName: _areaCtrl.text,
              latitude: _pinLat,
              longitude: _pinLon,
              scheduledAt: _schedule,
              pendingMedia: e.pending,
            );
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: RadarTheme.panelHigh,
          content: Text(
              '${outcome.message ?? 'Saved offline'} — media and post will '
              'upload automatically when you are back online'),
        ));
        Navigator.pop(context, false);
        return;
      } on MediaUploadException catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _uploadError = e.reason;
        });
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _uploadError = 'Upload failed — check your connection and retry.';
        });
        return;
      }
    }

    final outcome = await ref.read(feedPostsProvider.notifier).createPost(
          kind: _kind,
          body: _bodyCtrl.text,
          mediaUrl: mediaUrl,
          mediaPlatform: mediaKind != null ? mediaPlatform : _platform,
          mediaKind: mediaKind,
          mediaDurationSeconds: mediaDuration,
          mediaPosterUrl: mediaPoster,
          areaName: _areaCtrl.text,
          latitude: _pinLat,
          longitude: _pinLon,
          scheduledAt: _schedule,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: outcome.success
          ? RadarTheme.panelHigh
          : RadarTheme.alert,
      content: Text(outcome.success
          ? 'Posted to the feed'
          : outcome.queued
              ? '${outcome.message ?? 'Publish failed'} — saved and will retry automatically'
              : 'Could not publish: ${outcome.message ?? 'unknown error'}'),
      action: outcome.success || outcome.queued
          ? null
          : SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () { _publish(); }),
    ));
    if (outcome.success || outcome.queued) {
      Navigator.pop(context, outcome.success);
    }
    // Hard-rejected publishes keep the composer open (draft intact) so the
    // user can read the reason and retry or edit.
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'New post',
      showClose: false,
      footer: FilledButton.icon(
        onPressed: _bodyCtrl.text.trim().isEmpty || _busy || _uploading
            ? null
            : _publish,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.publish, size: 18),
        label: const Text('Publish to feed'),
      ),
      children: [
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
              style:  TextStyle(color: RadarTheme.textPrimary),
              decoration: InputDecoration(
                hintText: _kind == FeedPostKind.highlight
                    ? 'Describe the clip — opponent, minute, what scouts should watch…'
                    : 'What happened at the session?',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkCtrl,
              style:  TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '…or paste a highlight link (YouTube / Vimeo)',
                prefixIcon: Icon(Icons.link, size: 20),
              ),
              onChanged: (_) => setState(() {
                // A hand-pasted link replaces any staged device upload.
                if (_linkCtrl.text.trim().isNotEmpty) _pickedMedia = null;
              }),
            ),
            const SizedBox(height: 10),
            // Device uploads: video is capped at 3 minutes so scouts can
            // review quick highlights before committing to a live session.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _busy || _uploading ? null : () => _pickMedia(video: true),
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
                    onPressed: _busy || _uploading
                        ? null
                        : () => _pickMedia(video: false),
                    icon: const Icon(Icons.image, size: 18),
                    label: const Text('Upload photo',
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            if (_pickedMedia != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MediaPreviewCard(
                  media: _pickedMedia!,
                  onRemove: _busy || _uploading
                      ? null
                      : () => setState(() => _pickedMedia = null),
                ),
              ),
            if (_uploadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _uploadError!,
                  style:  TextStyle(
                      fontSize: 12, color: RadarTheme.alert, height: 1.3),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _areaCtrl,
              style:  TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Area label, e.g. “Limbe — Omnisport Annex”',
                prefixIcon: Icon(Icons.place_outlined, size: 20),
              ),
            ),
            if (ref.watch(authProvider).value is AuthSignedIn &&
                (ref.watch(authProvider).value as AuthSignedIn)
                    .session
                    .isMinor)
               Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Protected account: the map pin stays private — your post '
                  'shows the area label only.',
                  style: TextStyle(fontSize: 11.5, color: RadarTheme.gold),
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
                        style:  TextStyle(
                            fontSize: 12, color: RadarTheme.textDim)),
                  ),
                ]),
              ),
            const SizedBox(height: 14),
            // Training Schedule — the dedicated date & time section for
            // upcoming sessions/matches, saved onto the post itself.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RadarTheme.panelHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _schedule != null
                      ? RadarTheme.gold.withValues(alpha: 0.55)
                      : RadarTheme.stroke,
                ),
              ),
              child: Row(children: [
                Icon(
                  Icons.event_available,
                  size: 20,
                  color: _schedule != null
                      ? RadarTheme.gold
                      : RadarTheme.textDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Training Schedule',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      Text(
                        _schedule == null
                            ? 'Add a date & time for scouts to plan around'
                            : DateFormat('EEE d MMM · HH:mm')
                                .format(_schedule!),
                        style: TextStyle(
                            fontSize: 11.5,
                            color: _schedule != null
                                ? RadarTheme.gold
                                : RadarTheme.textDim),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickSchedule,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                  label: Text(_schedule == null ? 'Set' : 'Change',
                      style: const TextStyle(fontSize: 12)),
                ),
                if (_schedule != null)
                  IconButton(
                    tooltip: 'Clear schedule',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _schedule = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ]),
            ),
      ],
    );
  }
}

/// Compact dark/light switch for the feed header: sun in dark mode (tap
/// for light), moon in light mode. Persists across sessions.
class _ThemeHeaderToggle extends ConsumerWidget {
  const _ThemeHeaderToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == RadarBrightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 21,
        color: RadarTheme.textDim,
      ),
      onPressed: () async {
        final next = ref.read(themeModeProvider.notifier).toggle();
        RadarTheme.current = next == RadarBrightness.dark
            ? RadarPalette.dark
            : RadarPalette.light;
        await persistThemePreference(next);
      },
    );
  }
}

/// Public composer entry point — opens the New Post sheet. Exposed for
/// tests and reuse outside [FeedScreen]. Returns true when a post was
/// published.
Future<bool> openPostComposer(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ComposerSheet(),
  );
  return result == true;
}

// ---------------------------------------------------------------- media preview

/// Visual preview card for a staged device upload — shows the actual image
/// (or the video's probed poster frame) instead of a raw storage URL. The
/// file itself uploads to Supabase Storage when the post publishes. Public
/// so the composer tests can drive it directly.
class MediaPreviewCard extends StatelessWidget {
  const MediaPreviewCard({super.key, required this.media, this.onRemove});

  final PickedMedia media;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final preview = media.previewBytes;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 96,
              height: 64,
              color: const Color(0xFF0C241A),
              child: preview != null
                  ? Image.memory(preview,
                      width: 96, height: 64, fit: BoxFit.cover, gaplessPlayback: true)
                  : Icon(
                      media.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      size: 28,
                      color: RadarTheme.textDim,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.isVideo
                      ? (media.durationSeconds != null
                          ? 'Video · ${(media.durationSeconds! / 60).floor()}:${(media.durationSeconds! % 60).toString().padLeft(2, '0')}'
                          : 'Video')
                      : 'Photo',
                  style:  TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: RadarTheme.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  media.isVideo
                      ? 'Poster preview — uploads with your post'
                      : 'Uploads with your post',
                  style:  TextStyle(
                      fontSize: 11.5, color: RadarTheme.textDim),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove media',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            color: RadarTheme.textDim,
          ),
        ],
      ),
    );
  }
}

/// Public report-sheet entry point — returns the filed report, or null
/// when the sheet was dismissed. Exposed for tests and reuse.
Future<(ContentReportReason, String)?> openReportSheet(
  BuildContext context, {
  required String targetLabel,
}) async {
  return showModalBottomSheet<(ContentReportReason, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(targetLabel: targetLabel),
  );
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

    return SheetScaffold(
      title: 'Tag a training venue or time slot',
      icon: Icons.sports_soccer,
      floating: true,
      subtitle: 'Picking a slot pins the post to that venue\'s exact spot on '
          'the live Radar map.',
      children: [
          if (mine.isEmpty && others.isEmpty)
             Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No venues on the radar yet — drop a Live Pin first (radar '
                'icon in the header) and its venue will appear here.',
                style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim),
              ),
            )
          else ...[
            if (mine.isNotEmpty)
               Padding(
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
               Padding(
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
      ],
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
                      style:  TextStyle(
                          fontSize: 11,
                          color: RadarTheme.textDim),
                    ),
                  ],
                ),
              ),
              if (e.isLive)
                 Text('LIVE',
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

    final outcome =
        await ref.read(radarEventsProvider.notifier).createEvent(event);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: outcome.success
          ? RadarTheme.panelHigh
          : RadarTheme.alert,
      content: Text(outcome.success
          ? _openNow
              ? 'Live pin dropped — scouts see you on the radar now'
              : 'Session scheduled for ${_fmtDay(start)}'
          : outcome.queued
              ? '${outcome.message ?? 'Pin not published'} — saved and will retry automatically'
              : 'Could not publish the pin: ${outcome.message ?? 'unknown error'}'),
      action: outcome.success || outcome.queued
          ? null
          : SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () { _drop(); }),
    ));
    if (outcome.success || outcome.queued) {
      Navigator.pop(context, outcome.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Drop a live pin / schedule a session',
      icon: Icons.my_location,
      showClose: false,
      footer: FilledButton.icon(
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
      children: [
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
            style:  TextStyle(color: RadarTheme.textPrimary),
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
            style:  TextStyle(color: RadarTheme.textPrimary),
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
            title:  Text('Involves minors / U-teams',
                style:
                    TextStyle(color: RadarTheme.textPrimary, fontSize: 14)),
            subtitle:  Text(
                'Location auto-locked to the coarse area label',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            value: _involvesMinors,
            onChanged: (v) => setState(() => _involvesMinors = v),
          ),
      ],
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
    return SheetScaffold(
      title: 'Filter feed',
      showClose: false,
      footer: Row(
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
      children: [
             Text('Post type',
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
             Text('Show',
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
             Text('Scout filters (sessions)',
                style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
             Text('Position scouted',
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
             Text('Age bracket',
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
              title:  Text('Radius from my regional base',
                  style: TextStyle(color: RadarTheme.textPrimary, fontSize: 14)),
              subtitle: Text(
                  _useMyRegion
                      ? 'Only sessions within the slider distance'
                      : 'Enable to filter by distance',
                  style:  TextStyle(
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
          ],
    );
  }
}

/// Reason picker for the report-content flow. Returns
/// `(reason, detailsText)` — the details text is already trimmed and may
/// be empty — or null if dismissed.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetLabel});

  final String targetLabel;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ContentReportReason? _reason;
  final _detailsCtrl = TextEditingController();

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Report ${widget.targetLabel}',
      icon: Icons.flag_outlined,
      iconColor: RadarTheme.gold,
      floating: true,
      subtitle:
          'Tell us what is wrong. Reports go to the moderation team; '
          'the reported account is not told who filed it.',
      footer: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor:
              _reason == null ? RadarTheme.stroke : RadarTheme.radar,
        ),
        onPressed: _reason == null
            ? null
            : () => Navigator.pop(context, (_reason!, _detailsCtrl.text.trim())),
        icon: const Icon(Icons.send_outlined, size: 16),
        label: const Text('Send report'),
      ),
      children: [
          for (final reason in ContentReportReason.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _reason = reason),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _reason == reason
                        ? RadarTheme.gold.withValues(alpha: 0.10)
                        : RadarTheme.panelHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _reason == reason
                          ? RadarTheme.gold.withValues(alpha: 0.5)
                          : RadarTheme.stroke,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      _reason == reason
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 16,
                      color: _reason == reason
                          ? RadarTheme.gold
                          : RadarTheme.textDim,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(reason.label,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _detailsCtrl,
            maxLines: 2,
            maxLength: 400,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Optional details for the moderators…',
              counterText: '',
              isDense: true,
            ),
          ),
      ],
    );
  }
}

/// Actions in the Reels header's overflow menu — the discovery tools that
/// no longer have a scrolling feed to live in.
enum _ReelMenuAction {
  sessions,
  filter,
  postOnMap,
  map,
  theme,
  safety,
  report,
  delete,
}
