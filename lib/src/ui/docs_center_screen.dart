import 'package:flutter/material.dart';

import 'radar_theme.dart';
import 'shell.dart';

/// About & Platform Documentation Center — guides, transparency reports
/// and legal documents for users, scouts and regulatory authorities.
class DocsCenterScreen extends StatelessWidget {
  const DocsCenterScreen({super.key});

  static final _topics = <(String, IconData, Color, List<DocSection>)>[
    (
      'Platform guide',
      Icons.map_outlined,
      RadarTheme.radar,
      [
        DocSection(
          title: 'Build your Football CV',
          steps: [
            'Sign in with Pi — your identity is verified server-side before a profile exists.',
            'Complete the three-step onboarding: role, region, then your display profile.',
            'Open the My CV tab: pick your primary and secondary positions, dominant foot, birth year and height.',
            'Write your career history one line per entry — use “2019–2022 · Club name — role” and each line gets a verified marker.',
            'Add highlight links (YouTube, Vimeo, Pi media, Drive). Viewers see platform-verified link cards; nothing runs in-app.',
            'Scouts and clubs reach you through consent-checked requests that land in your Inbox — accept the good ones.',
          ],
        ),
        DocSection(
          title: 'Host an event on the Radar',
          steps: [
            'Open the LIVE RADAR tab and tap the publish (pin) icon in the app bar.',
            'Classify the event — Trial, Match, Training Session or Tournament — and write a clear description of what scouts will evaluate.',
            'Select target age brackets. Choosing any under-18 bracket automatically flags the event minor-protected.',
            'Drop the pin and set the area label. Minor-protected events are fenced to that coarse label by the database — the venue name is stripped on insert, not just hidden.',
            'Set capacity and the positions you are scouting for. Publish — the event appears on the global feed and map immediately.',
            'Review applicants from the event page (“Full details & applicants”) or your Inbox; accept or decline inline.',
          ],
        ),
        DocSection(
          title: 'Connect with scouts & players',
          steps: [
            'Use Global Search or the directory to filter talent by position, age bracket, region, foot and credibility.',
            'Open a player profile and choose Request contact or Invite to trial — every request is consent-checked before sending.',
            'Track everything in the Inbox: Received requests accept/decline; Sent requests can be withdrawn while pending.',
            'Request cards show the counterparty\u2019s role, KYC and credibility so you know who you are talking to.',
          ],
        ),
        DocSection(
          title: 'Set up guardian safeguarding',
          steps: [
            'A minor invites their parent or guardian by Pi username from the Safety tab.',
            'The guardian approves the link — database triggers prevent a minor from self-approving or flipping switches.',
            'The guardian controls two switches, both off by default: direct-contact consent and event-participation consent.',
            'Every decision is written to an append-only audit log that neither side can edit.',
          ],
        ),
      ],
    ),
    (
      'Minor safety & geofencing',
      Icons.shield_outlined,
      RadarTheme.info,
      [
        DocSection(
          title: 'How geohash fencing works',
          steps: [
            'Every event and profile carries a precision flag: exact or approximate. Approximate rows expose only a coarse area label (for example “North London”) — never coordinates.',
            'The rule is enforced by PostgreSQL triggers that run on every insert and update, regardless of which client sent the data. A modified app cannot bypass them.',
            'For events: any minor-protected event — or any event hosted by a minor — is forced to approximate precision and its venue name is nulled before the row is stored.',
            'For profiles: minor accounts keep only a coarse area token (falling back to city). Downstream services resolve approximate labels to regional names only.',
            'Attendee-facing surfaces render the area label unless the viewer is the host and the row is exact.',
          ],
        ),
        DocSection(
          title: 'Parental consent workflows',
          steps: [
            'guardian_links connects a minor account to a verified guardian. Both switches — contact consent and event consent — default to denied.',
            'A database trigger blocks contact requests to a minor unless an active link carries contact consent; the guardian themselves is always allowed through.',
            'Trial invites and event applications involving minors are gated separately, fail-closed: if the consent check cannot be answered, access is denied.',
            'Consent history is append-only. Approvals, denials and switch changes are recorded with the acting role; no client holds write access to the log.',
          ],
        ),
        DocSection(
          title: 'Data minimisation',
          steps: [
            'Age is derived from birth year — the platform never stores a full date of birth.',
            'Minor profiles cannot leak precise location through search: directory cards omit the area token entirely for minors.',
            'Identity is single-source: a profile row can only ever be created or modified under the Pi identity it was provisioned for, enforced by row-level security.',
          ],
        ),
      ],
    ),
    (
      'Pi ecosystem & payments',
      Icons.currency_exchange,
      RadarTheme.pi,
      [
        DocSection(
          title: 'Verified authentication',
          steps: [
            'The Radar authenticates through the Pi SDK inside the Pi Browser — you approve the sign-in, we never see your passphrase.',
            'A server-side exchange with Pi\u2019s App Studio verifies the identity before any session or profile is created; the browser-supplied identity alone is worthless.',
            'Row-level security ties every profile to that verified identity (profile id equals the authenticated user id and the Pi uid claim).',
          ],
        ),
        DocSection(
          title: 'How payments and boosts operate',
          steps: [
            'Purchases use Pi\u2019s user-to-app flow: the wallet overlay opens, you approve, and the SDK hands the transaction to the platform.',
            'Server approval and completion verify each payment with the Pi Platform API using a platform key that never reaches the client.',
            'On verified completion the backend grants an entitlement (boost, spotlight, premium search or bounty) and stamps the boost window on the target event.',
            'Interrupted payments are recovered, not lost: completion looks the transaction up by id and finishes it once the on-chain txid exists.',
          ],
        ),
        DocSection(
          title: 'Tokenomics on The Radar',
          steps: [
            'Session Boost (2π, 48h) pins your event to the top of the regional radar and notifies matching scouts.',
            'Global Spotlight (8π, 7 days) places your event at the top of every discovery feed worldwide; Profile Spotlight (6π, 14 days) does the same for your CV in the directory.',
            'Premium Scouting Search (5π, 30 days) unlocks unlimited advanced filtering; Scouting Bounty (10π) posts a reward paid to scouts who attend and file a report.',
            'Boost state lives in the database, so visibility is computed from real entitlements — nothing is faked client-side.',
          ],
        ),
      ],
    ),
    (
      'Legal & compliance',
      Icons.gavel_outlined,
      RadarTheme.gold,
      [
        DocSection(
          title: 'Terms of service (summary)',
          steps: [
            'The Radar connects football talent with scouts, clubs and academies. Accounts are personal; verified identities are non-transferable.',
            'Event hosts are responsible for the accuracy of their listings and for supervising minors in the physical world — the platform safeguards data, not venues.',
            'Paid products (boosts, spotlights, bounties) are final once the on-chain transaction completes, except where local law requires otherwise.',
            'Abuse — harassment, misrepresentation, falsified credentials — ends in account termination without refund of consumed boosts.',
          ],
        ),
        DocSection(
          title: 'Privacy policy (summary)',
          steps: [
            'We store what you publish: profile fields you fill in, events you host, requests you send. Nothing else is collected beyond the Pi identity required to operate.',
            'Minors get the strictest profile automatically: coarse location only, guardian-controlled visibility, no full date of birth anywhere in the database.',
            'You can export everything tied to your account as JSON from Account settings, and terminate your account at any time — deletion is enforced by database policy.',
            'Safeguarding records (guardian links and consent history) are retained after account deletion because protecting minors outranks the right to erasure.',
          ],
        ),
        DocSection(
          title: 'Open-source attributions',
          steps: [
            'Flutter and Material — Google, BSD-3-Clause.',
            'Riverpod — flutter_riverpod authors, MIT.',
            'Supabase client stack (supabase_flutter, gotrue, realtime_client, functions_client) — Supabase, Apache-2.0.',
            'connectivity_plus — fluttercommunity contributors, BSD-3-Clause. Intl — Dart project, BSD-3-Clause.',
            'Pi Platform SDK — Pi Network, used under the Pi developer terms.',
          ],
        ),
        DocSection(
          title: 'Regulatory contacts',
          steps: [
            'Minor-safety enquiries and law-enforcement requests: use the Safety tab in-app to reach the platform team with your credentials.',
            'Data-protection requests (access, correction, erasure) can be self-served from Account settings; escalations follow the same in-app route.',
          ],
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: const Text('Documentation center'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: InfoPill(
                icon: Icons.verified_outlined,
                label: 'The Radar',
                color: RadarTheme.radar,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          const Text(
            'About The Radar',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
           Text(
            'The Radar is a global football scouting platform: players publish '
            'verified CVs, organisers host trials and matches, and scouts find '
            'the next generation — with Pi Network identity and payments, and '
            'minor safety enforced in the database, not promised in the app.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: RadarTheme.textDim),
          ),
          const SizedBox(height: 16),
          for (final (title, icon, color, sections) in _topics)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _open(context, title, icon, color, sections),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: RadarTheme.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: RadarTheme.stroke),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, size: 20, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '${sections.length} article${sections.length == 1 ? '' : 's'} · ${sections.fold<int>(0, (n, s) => n + s.steps.length)} steps',
                            style:  TextStyle(
                                fontSize: 12, color: RadarTheme.textDim),
                          ),
                        ],
                      ),
                    ),
                     Icon(Icons.chevron_right,
                        size: 18, color: RadarTheme.textDim),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 10),
           Center(
            child: Text(
              'Documentation reflects the platform as built — every mechanism '
              'described here is enforced in code or in the database today.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _open(BuildContext context, String title, IconData icon, Color color,
      List<DocSection> sections) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _DocTopicPage(
        title: title,
        icon: icon,
        color: color,
        sections: sections,
      ),
    ));
  }
}

/// One article inside a topic.
class DocSection {
  const DocSection({required this.title, required this.steps});

  final String title;
  final List<String> steps;
}

class _DocTopicPage extends StatelessWidget {
  const _DocTopicPage({
    required this.title,
    required this.icon,
    required this.color,
    required this.sections,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<DocSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 15))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: RadarTheme.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: RadarTheme.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(icon, size: 17, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(section.title,
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    for (var i = 0; i < section.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(top: 1),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.withValues(alpha: 0.14),
                              ),
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: color)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(section.steps[i],
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.5)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
