import 'package:flutter/material.dart';

/// Standard football positions used by player CVs and event requirements.
const List<String> kFootballPositions = <String>[
  'GK', 'CB', 'LB', 'RB', 'DM', 'CM', 'AM', 'LW', 'RW', 'ST',
];

/// Platform roles supported by The Radar.
enum UserRole {
  player('Player'),
  scout('Verified Scout'),
  club('Club'),
  academy('Academy'),
  agent('Agent'),
  parent('Parent');

  const UserRole(this.label);
  final String label;

  IconData get icon {
    switch (this) {
      case UserRole.player:
        return Icons.sports_soccer;
      case UserRole.scout:
        return Icons.travel_explore;
      case UserRole.club:
        return Icons.account_balance;
      case UserRole.academy:
        return Icons.school;
      case UserRole.agent:
        return Icons.workspace_premium;
      case UserRole.parent:
        return Icons.family_restroom;
    }
  }

  static UserRole? tryParse(String? raw) {
    if (raw == null) return null;
    for (final r in UserRole.values) {
      if (r.name == raw.toLowerCase()) return r;
    }
    return null;
  }
}

/// What kind of football activity a radar blip represents.
enum RadarEventType {
  trainingSession('Training Session'),
  match('Match'),
  trial('Trial'),
  tournament('Tournament');

  const RadarEventType(this.label);
  final String label;

  IconData get icon {
    switch (this) {
      case RadarEventType.trainingSession:
        return Icons.fitness_center;
      case RadarEventType.match:
        return Icons.sports_soccer;
      case RadarEventType.trial:
        return Icons.how_to_reg;
      case RadarEventType.tournament:
        return Icons.emoji_events;
    }
  }

  static RadarEventType tryParse(String? raw) {
    if (raw == null) return RadarEventType.trainingSession;
    for (final t in RadarEventType.values) {
      if (t.name == raw.toLowerCase()) return t;
    }
    return RadarEventType.trainingSession;
  }
}

/// How precisely an event or profile location is exposed.
enum GeoPrecision {
  /// Full coordinates — adults / non-sensitive events only.
  exact('Exact location'),

  /// Neighbourhood-level naming, no coordinates (default for minors).
  approximate('Approximate area');

  const GeoPrecision(this.label);
  final String label;

  static GeoPrecision fromRaw(String? raw) =>
      raw == 'exact' ? GeoPrecision.exact : GeoPrecision.approximate;

  String get storageValue => this == GeoPrecision.exact ? 'exact' : 'approximate';
}
