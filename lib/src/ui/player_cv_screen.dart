import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/connection_request.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../state/auth_controller.dart';
import 'profiles_screen.dart' show CredibilityBar, requestConnection;
import 'radar_theme.dart';
import 'shell.dart';

/// Player Football CV portfolio — the deep-dive view scouts and clubs see.
///
/// Covers the spec's profile screen: athlete bio & position badges, highlight
/// reel links, verified credibility & career history, and secure contact /
/// trial-invite triggers routed through the consent-checked request flow.
class PlayerCvScreen extends ConsumerWidget {
  const PlayerCvScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isMe = session?.profileId == profile.id;
    final df = DateFormat('MMM yyyy');

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: Text(isMe ? 'My Football CV' : 'Football CV',
            style: const TextStyle(fontSize: 15)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          _AthleteHero(profile: profile, isMe: isMe),
          const SizedBox(height: 14),
          _VitalsGrid(profile: profile),
          const SizedBox(height: 14),
          _HighlightReel(profile: profile),
          const SizedBox(height: 14),
          _CredibilityHistory(profile: profile, df: df),
          const SizedBox(height: 14),
          _ContactActions(profile: profile, session: session, isMe: isMe),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero — identity & verified badges
// ---------------------------------------------------------------------------

class _AthleteHero extends StatelessWidget {
  const _AthleteHero({required this.profile, required this.isMe});

  final UserProfile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Row(children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: RadarTheme.pi.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(p.role.icon, color: RadarTheme.pi, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(p.bestName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                if (p.kycVerified) ...[
                  const SizedBox(width: 6),
                   Icon(Icons.verified,
                      size: 18, color: RadarTheme.radar),
                ],
              ]),
              const SizedBox(height: 4),
              Text(
                p.clubAffiliation != null && p.clubAffiliation!.isNotEmpty
                    ? 'Player · ${p.clubAffiliation}'
                    : 'Player · unaffiliated',
                style:
                     TextStyle(fontSize: 12.5, color: RadarTheme.textDim),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                const InfoPill(
                    icon: Icons.emoji_people_outlined, label: 'Athlete'),
                if (p.isMinor)
                   InfoPill(
                      icon: Icons.shield_outlined,
                      label: 'Safeguarded',
                      color: RadarTheme.gold),
                InfoPill(
                  icon: Icons.calendar_today_outlined,
                  label: 'On Radar since ${DateFormat('MMM yyyy').format(p.createdAt)}',
                ),
              ]),
            ],
          ),
        ),
        if (isMe)
          TextButton.icon(
            key: const ValueKey('cv-edit'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Vitals — positions, foot, age, height, base
// ---------------------------------------------------------------------------

class _VitalsGrid extends StatelessWidget {
  const _VitalsGrid({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final primary = p.positions.isNotEmpty ? p.positions.first : null;
    final secondary =
        p.positions.length > 1 ? p.positions.sublist(1) : const <String>[];
    final base = p.isMinor
        ? (p.geohashArea ??
            (p.city != null ? '${p.city} region' : 'Region withheld'))
        : [p.city, p.country].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    final cells = <(IconData, String, String)>[
      if (primary != null) (Icons.sports_soccer, primary, 'Primary position'),
      if (secondary.isNotEmpty)
        (Icons.alt_route, secondary.join(' · '), 'Secondary'),
      if (p.dominantFoot != null)
        (Icons.sports, p.dominantFoot![0].toUpperCase() + p.dominantFoot!.substring(1),
            'Dominant foot'),
      if (p.age != null) (Icons.cake_outlined, '~${p.age} yrs', 'Age band'),
      if (p.heightCm != null) (Icons.height, '${p.heightCm} cm', 'Height'),
      if (base.isNotEmpty)
        (Icons.location_on_outlined, base, p.isMinor ? 'Regional base (coarse)' : 'Regional base'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.badge_outlined, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Text('Athlete bio & positions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        if (cells.isEmpty)
           Text(
            'No vitals published yet. Players complete them from the My CV tab.',
            style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth > 480 ? 3 : 2;
            return Column(children: [
              for (var i = 0; i < cells.length; i += cols)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: i + cols < cells.length ? 12 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var j = i; j < (i + cols).clamp(0, cells.length); j++)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(cells[j].$1,
                                  size: 17, color: RadarTheme.info),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(cells[j].$2,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700)),
                                    Text(cells[j].$3,
                                        style:  TextStyle(
                                            fontSize: 11,
                                            color: RadarTheme.textDim)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ]);
          }),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Highlight reel — secure links with platform verification
// ---------------------------------------------------------------------------

class _HighlightReel extends StatelessWidget {
  const _HighlightReel({required this.profile});

  final UserProfile profile;

  static final _knownHosts = {
    'youtube.com': ('YouTube', RadarTheme.alert),
    'youtu.be': ('YouTube', RadarTheme.alert),
    'vimeo.com': ('Vimeo', RadarTheme.info),
    'minepi.com': ('Pi media', RadarTheme.pi),
    'drive.google.com': ('Drive', RadarTheme.gold),
  };

  (String, Color) _hostInfo(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    for (final entry in _knownHosts.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        return entry.value;
      }
    }
    return ('External link', RadarTheme.textDim);
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
           Icon(Icons.movie_outlined, size: 17, color: RadarTheme.radar),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Highlight reel',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          InfoPill(
              icon: Icons.play_circle_outline,
              label: '${p.videoShowcaseUrls.length} clips',
              color: RadarTheme.info),
        ]),
        const SizedBox(height: 12),
        if (p.videoShowcaseUrls.isEmpty)
           Text(
            'No footage published yet. Match clips, training highlights and '
            'skill reels live here.',
            style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
          )
        else
          for (var i = 0; i < p.videoShowcaseUrls.length; i++)
            _ClipTile(
              index: i + 1,
              url: p.videoShowcaseUrls[i],
              hostInfo: _hostInfo(p.videoShowcaseUrls[i]),
            ),
      ]),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({required this.index, required this.url, required this.hostInfo});

  final int index;
  final String url;
  final (String, Color) hostInfo;

  @override
  Widget build(BuildContext context) {
    final (host, color) = hostInfo;
    final title = Uri.tryParse(url)?.host ?? url;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text('$index',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                      fontSize: 11, color: RadarTheme.textDim)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Verified video platform',
          child: InfoPill(icon: Icons.link, label: host, color: color),
        ),
        IconButton(
          tooltip: 'Copy secure link',
          icon:  Icon(Icons.copy_outlined, size: 16,
              color: RadarTheme.textDim),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Link copied — $title')));
          },
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Credibility & history — verified timeline
// ---------------------------------------------------------------------------

class _CredibilityHistory extends StatelessWidget {
  const _CredibilityHistory({required this.profile, required this.df});

  final UserProfile profile;
  final DateFormat df;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final lines = (p.footballCv ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.workspace_premium_outlined,
              size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Expanded(
            child: Text('Verified credibility & history',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        CredibilityBar(score: p.credibilityScore),
        const SizedBox(height: 12),
        if (lines.isEmpty)
           Text(
            'No career history published yet — past clubs, academies and '
            'tournament appearances will appear here.',
            style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
          )
        else
          Column(children: [
            for (var i = 0; i < lines.length; i++)
              _TimelineRow(
                line: lines[i],
                isFirst: i == 0,
                isLast: i == lines.length - 1,
              ),
          ]),
      ]),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.line,
    required this.isFirst,
    required this.isLast,
  });

  final String line;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final verified = line.contains('·'); // "2023–2025 · Club — detail" style
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: verified ? RadarTheme.radar : RadarTheme.stroke,
              border: Border.all(
                  color: verified ? RadarTheme.radar : RadarTheme.textDim,
                  width: 1.5),
            ),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1.5,
                color: RadarTheme.stroke,
              ),
            ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Text(line,
                style:  TextStyle(
                    fontSize: 13, height: 1.4, color: RadarTheme.textPrimary)),
          ),
        ),
        Icon(
          verified ? Icons.verified_outlined : Icons.history,
          size: 14,
          color: verified ? RadarTheme.radar : RadarTheme.textDim,
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Direct contact & invite — authorized viewers only
// ---------------------------------------------------------------------------

class _ContactActions extends ConsumerWidget {
  const _ContactActions({required this.profile, required this.session, required this.isMe});

  final UserProfile profile;
  final RadarSession? session;
  final bool isMe;

  bool get _authorized {
    if (session == null || isMe) return false;
    final role = session!.role;
    return role == UserRole.scout ||
        role == UserRole.club ||
        role == UserRole.academy ||
        role == UserRole.agent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isMe) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Row(children: [
           Icon(Icons.visibility_outlined,
              size: 17, color: RadarTheme.radar),
          const SizedBox(width: 10),
           Expanded(
            child: Text(
              'This is how scouts and clubs see your portfolio. Edit it from the My CV tab.',
              style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('cv-preview-edit'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text('Edit CV'),
          ),
        ]),
      );
    }

    if (!_authorized) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child:  Row(children: [
          Icon(Icons.lock_outline, size: 17, color: RadarTheme.textDim),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Direct contact and trial invitations are reserved for verified '
              'scouts, clubs, academies and agents.',
              style: TextStyle(fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Row(children: [
          Icon(Icons.connect_without_contact, size: 17, color: RadarTheme.radar),
          SizedBox(width: 8),
          Text('Direct contact',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Requests land in ${profile.bestName}\'s inbox — guardian consent is '
          'enforced automatically where required.',
          style:  TextStyle(
              fontSize: 12.5, color: RadarTheme.textDim, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('cv-request-contact'),
              onPressed: () => requestConnection(context, ref, profile),
              icon: const Icon(Icons.mail_outline, size: 16),
              label: const Text('Request contact'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('cv-invite-trial'),
              onPressed: () => requestConnection(
                context,
                ref,
                profile,
                initialType: ConnectionType.trialInvite,
              ),
              icon: const Icon(Icons.how_to_reg, size: 16),
              label: const Text('Invite to trial'),
            ),
          ),
        ]),
      ]),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
      color: RadarTheme.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: RadarTheme.stroke),
    );
