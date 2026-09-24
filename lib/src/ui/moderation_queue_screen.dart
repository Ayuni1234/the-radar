import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/content_report.dart';
import '../models/feed_post.dart';
import '../models/market.dart';
import '../models/radar_event.dart';
import '../state/auth_controller.dart';
import '../state/market_providers.dart' show marketListingsProvider;
import '../state/radar_providers.dart';
import 'radar_theme.dart';
import 'social_post_card.dart';

/// Admin-only moderation queue: every report RLS exposes to the viewer,
/// with the status workflow (open → reviewing → resolved/dismissed).
///
/// RLS is the authority — the client only ever narrows what the database
/// already filtered. Reported content is shown inline (post/event/listing
/// context) so a moderator can judge the report without hunting through
/// the app; decisions are stamped with reviewed_at server-side.
class ModerationQueueScreen extends ConsumerStatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  ConsumerState<ModerationQueueScreen> createState() =>
      _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends ConsumerState<ModerationQueueScreen> {
  /// 0 = active queue (open + reviewing), 1 = resolved, 2 = dismissed.
  int _bucket = 0;

  /// Rebuilds the header count when the provider ticks beneath the pinned
  /// app bar (same pattern as the feed screen's stat line).
  final ValueNotifier<int> _tick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    ref.listenManual(contentReportsProvider, (_, _) => _tick.value++);
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    // Belt-and-braces: the entry point is admin-gated too, but a deep link
    // from a non-admin account gets a clean no-access panel instead of a
    // queue that would (via RLS) only ever show their own reports.
    if (!(session?.isAdmin ?? false)) {
      return Scaffold(
        backgroundColor: RadarTheme.ink,
        appBar: AppBar(title: const Text('Moderation')),
        body:  SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gpp_bad_outlined, size: 44, color: RadarTheme.textDim),
                SizedBox(height: 12),
                Text('No moderation access',
                    style:
                        TextStyle(color: RadarTheme.textPrimary, fontSize: 16)),
                SizedBox(height: 6),
                Text(
                  'Admin accounts are provisioned by the Radar team.',
                  style: TextStyle(color: RadarTheme.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final reportsAsync = ref.watch(contentReportsProvider);
    final all = reportsAsync.value ?? const <ContentReport>[];
    final queue = _bucket == 0
        ? all
            .where((r) =>
                r.status == ContentReportStatus.open ||
                r.status == ContentReportStatus.reviewing)
            .toList()
        : all
            .where((r) =>
                r.status ==
                (_bucket == 1
                    ? ContentReportStatus.resolved
                    : ContentReportStatus.dismissed))
            .toList();

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: Row(children: [
          const Flexible(
            child: Text('MODERATION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    fontSize: 17)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: ValueListenableBuilder<int>(
              valueListenable: _tick,
              builder: (_, _, _) {
                final openCount = all
                    .where((r) =>
                        r.status == ContentReportStatus.open ||
                        r.status == ContentReportStatus.reviewing)
                    .length;
                return Text('$openCount awaiting review',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(
                        color: RadarTheme.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w500));
              },
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh queue',
            icon:  Icon(Icons.refresh, color: RadarTheme.textDim),
            onPressed: () =>
                ref.read(contentReportsProvider.notifier).refresh(),
          ),
        ]),
      ),
      body: SafeArea(
        child: reportsAsync.isLoading && all.isEmpty
            ? const Center(
                child: CircularProgressIndicator(strokeWidth: 2))
            : reportsAsync.hasError && all.isEmpty
                ? _Panel(
                    child: Text(
                      'Could not load the queue: ${reportsAsync.error}',
                      style:  TextStyle(color: RadarTheme.alert),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _BucketChip(
                              label: 'Queue',
                              count: all
                                  .where((r) =>
                                      r.status ==
                                          ContentReportStatus.open ||
                                      r.status ==
                                          ContentReportStatus.reviewing)
                                  .length,
                              selected: _bucket == 0,
                              onTap: () => setState(() => _bucket = 0),
                            ),
                            _BucketChip(
                              label: 'Resolved',
                              count: all
                                  .where((r) =>
                                      r.status ==
                                      ContentReportStatus.resolved)
                                  .length,
                              selected: _bucket == 1,
                              onTap: () => setState(() => _bucket = 1),
                            ),
                            _BucketChip(
                              label: 'Dismissed',
                              count: all
                                  .where((r) =>
                                      r.status ==
                                      ContentReportStatus.dismissed)
                                  .length,
                              selected: _bucket == 2,
                              onTap: () => setState(() => _bucket = 2),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: queue.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _bucket == 0
                                          ? Icons.verified_outlined
                                          : Icons.inbox_outlined,
                                      size: 44,
                                      color: RadarTheme.textDim,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _bucket == 0
                                          ? 'Queue is clear'
                                          : 'Nothing here yet',
                                      style:  TextStyle(
                                          color: RadarTheme.textPrimary,
                                          fontSize: 16),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _bucket == 0
                                          ? 'Every report has been reviewed.'
                                          : 'Closed reports land in this bucket.',
                                      style:  TextStyle(
                                          color: RadarTheme.textDim,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                color: RadarTheme.radar,
                                backgroundColor: RadarTheme.panel,
                                onRefresh: () => ref
                                    .read(contentReportsProvider.notifier)
                                    .refresh(),
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                                  itemCount: queue.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, i) => _ReportCard(
                                    report: queue[i],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ----------------------------------------------------------------- bucket chip

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

// ------------------------------------------------------------------ report card

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report});

  final ContentReport report;

  static const _reasonIcons = <ContentReportReason, IconData>{
    ContentReportReason.minorSafety: Icons.shield,
    ContentReportReason.abuse: Icons.warning_amber_rounded,
    ContentReportReason.inappropriateMedia: Icons.hide_image_outlined,
    ContentReportReason.misleading: Icons.fact_check_outlined,
    ContentReportReason.spam: Icons.block_outlined,
    ContentReportReason.other: Icons.flag_outlined,
  };

  Color _statusColor(ContentReportStatus s) => switch (s) {
        ContentReportStatus.open => RadarTheme.radar,
        ContentReportStatus.reviewing => RadarTheme.gold,
        _ => RadarTheme.textDim,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closed = !report.isOpen;
    final accent = _reasonIcons[report.reason] ?? Icons.flag_outlined;
    final age = _age(report.createdAt);

    return Opacity(
      opacity: closed ? 0.78 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: closed
                ? RadarTheme.stroke
                : _statusColor(report.status).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------- reason + status
            Row(children: [
              Icon(accent,
                  size: 18,
                  color: report.reason == ContentReportReason.minorSafety ||
                          report.reason == ContentReportReason.abuse
                      ? RadarTheme.alert
                      : RadarTheme.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(report.reason.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              _StatusChip(status: report.status),
              const SizedBox(width: 6),
              Text(age,
                  style:  TextStyle(
                      color: RadarTheme.textDim, fontSize: 11.5)),
            ]),
            const SizedBox(height: 10),

            // ------------------------------------------------- reporter note
            if (report.details != null && report.details!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: RadarTheme.panelHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                      left: BorderSide(color: RadarTheme.gold, width: 3)),
                ),
                child: Text('“${report.details}”',
                    style:  TextStyle(
                        color: RadarTheme.textPrimary,
                        fontSize: 12.5,
                        height: 1.4)),
              ),
              const SizedBox(height: 10),
            ],

            // ----------------------------------------------- reported content
            _TargetContext(report: report),
            const SizedBox(height: 10),

            // ------------------------------------------------------- metadata
            Text(
              'Filed ${DateFormat('d MMM · HH:mm').format(report.createdAt)}'
              '${report.reviewedAt != null ? '  ·  reviewed ${DateFormat('d MMM · HH:mm').format(report.reviewedAt!)}' : ''}',
              style:  TextStyle(color: RadarTheme.textDim, fontSize: 11),
            ),
            const SizedBox(height: 12),

            // -------------------------------------------------------- actions
            if (!closed)
              Row(children: [
                if (report.status == ContentReportStatus.open)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Start review',
                          style: TextStyle(fontSize: 12.5)),
                      onPressed: () => _setStatus(
                          context, ref, ContentReportStatus.reviewing),
                    ),
                  ),
                if (report.status == ContentReportStatus.open)
                  const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.block, size: 16),
                    label: const Text('Dismiss',
                        style: TextStyle(fontSize: 12.5)),
                    onPressed: () => _confirmClose(
                        context, ref, ContentReportStatus.dismissed),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: RadarTheme.radar),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Resolve',
                        style: TextStyle(fontSize: 12.5)),
                    onPressed: () => _confirmClose(
                        context, ref, ContentReportStatus.resolved),
                  ),
                ),
              ])
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.replay, size: 15),
                  label: const Text('Reopen review',
                      style: TextStyle(fontSize: 12)),
                  onPressed: () => _setStatus(
                      context, ref, ContentReportStatus.reviewing),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    ContentReportStatus status,
  ) async {
    final error = await ref
        .read(contentReportsProvider.notifier)
        .setStatus(report, status);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error != null ? RadarTheme.alert : RadarTheme.panelHigh,
      content: Text(error ?? 'Report marked “${status.label.toLowerCase()}”.'),
    ));
  }

  /// Resolve / dismiss are the consequential transitions (they close the
  /// report), so they get a confirmation; “start review” does not.
  Future<void> _confirmClose(
    BuildContext context,
    WidgetRef ref,
    ContentReportStatus status,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RadarTheme.panelHigh,
        title: Text(status == ContentReportStatus.resolved
            ? 'Resolve report?'
            : 'Dismiss report?'),
        content: Text(
          '${report.reason.label} — this closes the report. '
          'The reporter is never shown who reviewed it.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: status == ContentReportStatus.resolved
                  ? RadarTheme.radar
                  : RadarTheme.stroke,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(status.label),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _setStatus(context, ref, status);
  }

  String _age(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// ---------------------------------------------------------------- status chip

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ContentReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ContentReportStatus.open => RadarTheme.radar,
      ContentReportStatus.reviewing => RadarTheme.gold,
      ContentReportStatus.resolved => RadarTheme.info,
      ContentReportStatus.dismissed => RadarTheme.textDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(status.label,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

// ------------------------------------------------------------- target context

/// Inline view of the reported content so moderators judge in place —
/// with the full card for posts (same widget players see), summary rows
/// for events and listings.
class _TargetContext extends ConsumerWidget {
  const _TargetContext({required this.report});

  final ContentReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = report.targetId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RadarTheme.ink.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: switch (report.targetType) {
        'feed_post' => _post(context, ref, id),
        'radar_event' => _event(ref, id),
        'market_listing' => _listing(ref, id),
        _ =>  Text('Unknown target type',
            style: TextStyle(color: RadarTheme.textDim, fontSize: 12)),
      },
    );
  }

  static const _typeIcons = <String, IconData>{
    'feed_post': Icons.article_outlined,
    'radar_event': Icons.podcasts,
    'market_listing': Icons.storefront_outlined,
  };

  Widget _missing(String type, String id) {
    return Row(children: [
      Icon(_typeIcons[type] ?? Icons.help_outline,
          size: 16, color: RadarTheme.textDim),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '$type no longer available (deleted or out of view) — '
          'target $id',
          style:  TextStyle(color: RadarTheme.textDim, fontSize: 12),
        ),
      ),
    ]);
  }

  Widget _post(BuildContext context, WidgetRef ref, String id) {
    final posts = ref.watch(feedPostsProvider).value ?? const <FeedPost>[];
    FeedPost? post;
    for (final p in posts) {
      if (p.id == id) post = p;
    }
    final found = post;
    if (found == null) return _missing('Post', id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
           Icon(Icons.article_outlined, size: 15, color: RadarTheme.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${found.authorName} · ${found.kind.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(found.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(
                color: RadarTheme.textDim, fontSize: 12, height: 1.35)),
        // Own Material ancestor: the surrounding decorated Container would
        // otherwise swallow the tile's ink splashes (asserted in tests).
        Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: false,
              iconColor: RadarTheme.textDim,
              collapsedIconColor: RadarTheme.textDim,
              title:  Text('Show the full post',
                  style: TextStyle(color: RadarTheme.info, fontSize: 12.5)),
              children: [
                SocialPostCard(post: found),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _event(WidgetRef ref, String id) {
    final events = ref.watch(radarEventsProvider).value ?? const <RadarEvent>[];
    RadarEvent? event;
    for (final e in events) {
      if (e.id == id) event = e;
    }
    final found = event;
    if (found == null) return _missing('Event', id);
    return Row(children: [
      Icon(
        found.isLive ? Icons.podcasts : Icons.event_outlined,
        size: 16,
        color: found.isLive ? RadarTheme.radar : RadarTheme.info,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(found.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text(
              '${DateFormat('EEE d MMM · HH:mm').format(found.startsAt)}'
              ' · ${found.safeLocationLabel()}',
              style:  TextStyle(color: RadarTheme.textDim, fontSize: 11.5),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _listing(WidgetRef ref, String id) {
    final listings =
        ref.watch(marketListingsProvider).value ?? const <MarketListing>[];
    MarketListing? listing;
    for (final l in listings) {
      if (l.id == id) listing = l;
    }
    final found = listing;
    if (found == null) return _missing('Listing', id);
    return Row(children: [
       Icon(Icons.storefront_outlined,
          size: 16, color: RadarTheme.pi),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '${found.title} · ${found.pricePi.toStringAsFixed(found.pricePi.truncateToDouble() == found.pricePi ? 0 : 2)} π',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }
}

// -------------------------------------------------------------------- panel

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: child,
      ),
    );
  }
}
