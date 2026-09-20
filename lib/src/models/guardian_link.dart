import 'package:flutter/material.dart';

/// Guardian ↔ minor relationship and consent switches (Module 3).
///
/// A minor invites a guardian (their parent/guardian account on The Radar);
/// the guardian approves the link and then controls two independent
/// switches, both OFF by default:
///  - `consentConnections` — adults may send contact requests to the minor
///  - `consentEvents`      — the minor may be invited to / apply for events
///
/// These mirror `guardian_links` in supabase/schema.sql, where the same
/// rules are enforced by database triggers — the UI is a convenience, the
/// database is the gate.
enum GuardianLinkStatus {
  pending('Pending approval'),
  active('Active'),
  declined('Declined'),
  revoked('Revoked');

  const GuardianLinkStatus(this.label);
  final String label;

  static GuardianLinkStatus fromRaw(String? raw) =>
      GuardianLinkStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => GuardianLinkStatus.pending,
      );
}

/// One row of `guardian_links`.
class GuardianLink {
  const GuardianLink({
    required this.id,
    required this.minorProfile,
    required this.guardianProfile,
    required this.status,
    this.consentConnections = false,
    this.consentEvents = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String minorProfile;
  final String guardianProfile;
  final GuardianLinkStatus status;

  /// Guardian-controlled switches (only meaningful when active).
  final bool consentConnections;
  final bool consentEvents;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == GuardianLinkStatus.active;
  bool get isPending => status == GuardianLinkStatus.pending;

  factory GuardianLink.fromJson(Map<String, Object?> json) {
    DateTime? date(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return GuardianLink(
      id: (json['id'] ?? '').toString(),
      minorProfile: (json['minor_profile'] ?? '').toString(),
      guardianProfile: (json['guardian_profile'] ?? '').toString(),
      status: GuardianLinkStatus.fromRaw(json['status']?.toString()),
      consentConnections: json['consent_connections'] as bool? ?? false,
      consentEvents: json['consent_events'] as bool? ?? false,
      createdAt: date(json['created_at']),
      updatedAt: date(json['updated_at']),
    );
  }
}

/// Result of the `minor_consent_status` RPC — booleans only, no PII.
/// Used for friendly UX pre-checks; the authoritative gate is the
/// database trigger on `connection_requests`.
class MinorConsent {
  const MinorConsent({
    required this.isMinor,
    this.consentConnections = false,
    this.consentEvents = false,
  });

  final bool isMinor;
  final bool consentConnections;
  final bool consentEvents;

  /// Can an adult send a contact request to this profile?
  bool get allowsContact => !isMinor || consentConnections;

  /// Can this profile be invited to events / apply for them?
  bool get allowsEvents => !isMinor || consentEvents;

  factory MinorConsent.fromJson(Object? json) {
    if (json is Map) {
      return MinorConsent(
        isMinor: json['is_minor'] as bool? ?? false,
        consentConnections: json['consent_connections'] as bool? ?? false,
        consentEvents: json['consent_events'] as bool? ?? false,
      );
    }
    return const MinorConsent(isMinor: false);
  }
}

/// One row of the append-only `consent_audit_log` — every guardian
/// permission change, written by the database trigger, read participant-
/// scoped through the `read_consent_audit` SECURITY DEFINER function.
class ConsentAuditEntry {
  const ConsentAuditEntry({
    required this.minorProfile,
    this.guardianProfile,
    required this.action,
    required this.actorRole,
    this.createdAt,
  });

  final String minorProfile;
  final String? guardianProfile;
  final String action;

  /// 'minor' or 'guardian' — who performed the change.
  final String actorRole;
  final DateTime? createdAt;

  factory ConsentAuditEntry.fromJson(Map<String, Object?> json) {
    return ConsentAuditEntry(
      minorProfile: (json['minor_profile'] ?? '').toString(),
      guardianProfile: json['guardian_profile']?.toString(),
      action: (json['action'] ?? '').toString(),
      actorRole: (json['actor_role'] ?? 'minor').toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString())?.toLocal(),
    );
  }

  String get label => switch (action) {
        'link_pending' => 'Guardian link requested',
        'link_active' => 'Guardian link approved',
        'link_declined' => 'Guardian link declined',
        'link_revoked' => 'Guardian link revoked',
        'consent_connections_on' => 'Direct-contact consent granted',
        'consent_connections_off' => 'Direct-contact consent revoked',
        'consent_events_on' => 'Event-participation consent granted',
        'consent_events_off' => 'Event-participation consent revoked',
        _ => action,
      };

  (IconData, Color) get visual => switch (action) {
        'link_active' => (Icons.handshake_outlined, ConsentColors.radar),
        'link_pending' => (Icons.hourglass_top, ConsentColors.gold),
        'link_declined' || 'link_revoked' =>
          (Icons.link_off, ConsentColors.dim),
        'consent_connections_on' || 'consent_events_on' =>
          (Icons.check_circle_outline, ConsentColors.radar),
        _ => (Icons.remove_circle_outline, ConsentColors.alert),
      };
}

/// Color tokens kept in the model layer to avoid a UI import cycle.
abstract final class ConsentColors {
  static const Color radar = Color(0xFF3DFFA2);
  static const Color gold = Color(0xFFF5C043);
  static const Color alert = Color(0xFFFF6B6B);
  static const Color dim = Color(0xFF93A1B7);
}
