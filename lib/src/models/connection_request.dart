/// A P2P scouting connection between two profiles (Module 4).
///
/// Types:
/// - `contact` — a scout/club/agent requests direct contact with a player.
/// - `trial_invite` — an organizer invites a player to one of their events.
/// - `trial_application` — a player applies to an open scouting event.
enum ConnectionType {
  contact('Contact request'),
  trialInvite('Trial invite'),
  trialApplication('Trial application');

  const ConnectionType(this.label);
  final String label;

  static ConnectionType fromRaw(String? raw) =>
      ConnectionType.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => ConnectionType.contact,
      );
}

enum ConnectionStatus {
  pending('Pending'),
  accepted('Accepted'),
  declined('Declined'),
  withdrawn('Withdrawn');

  const ConnectionStatus(this.label);
  final String label;

  static ConnectionStatus fromRaw(String? raw) =>
      ConnectionStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => ConnectionStatus.pending,
      );
}

/// One row of `connection_requests`.
class ConnectionRequest {
  const ConnectionRequest({
    required this.id,
    required this.fromProfile,
    required this.toProfile,
    required this.type,
    required this.status,
    this.eventId,
    this.message,
    this.createdAt,
    this.updatedAt,
    // Denormalized display fields (from a joined profile fetch).
    this.fromName,
    this.toName,
    this.eventTitle,
  });

  final String id;
  final String fromProfile;
  final String toProfile;
  final ConnectionType type;
  final ConnectionStatus status;
  final String? eventId;
  final String? message;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display helpers (populated when requests are fetched with joins).
  final String? fromName;
  final String? toName;
  final String? eventTitle;

  bool get isPending => status == ConnectionStatus.pending;

  factory ConnectionRequest.fromJson(Map<String, Object?> json) {
    DateTime? date(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    final from = json['profiles'] is Map
        ? (json['profiles'] as Map)
        : json['from_profile_obj'] is Map
            ? (json['from_profile_obj'] as Map)
            : null;

    // Supabase embedded-resource shape: profiles!connection_requests_from_profile_fkey
    final fromObj = json['from_profile_obj'] ?? json['profiles'];
    final toObj = json['to_profile_obj'];

    return ConnectionRequest(
      id: (json['id'] ?? '').toString(),
      fromProfile: (json['from_profile'] ?? '').toString(),
      toProfile: (json['to_profile'] ?? '').toString(),
      type: ConnectionType.fromRaw(json['request_type']?.toString()),
      status: ConnectionStatus.fromRaw(json['status']?.toString()),
      eventId: json['event_id']?.toString(),
      message: json['message']?.toString(),
      createdAt: date(json['created_at']),
      updatedAt: date(json['updated_at']),
      fromName: fromObj is Map
          ? ((fromObj['display_name'] ?? fromObj['username']) ?? 'Unknown')
              .toString()
          : from is Map
              ? ((from['display_name'] ?? from['username']) ?? 'Unknown')
                  .toString()
              : null,
      toName: toObj is Map
          ? ((toObj['display_name'] ?? toObj['username']) ?? 'Unknown')
              .toString()
          : null,
      eventTitle: json['event_title']?.toString(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'from_profile': fromProfile,
        'to_profile': toProfile,
        'request_type': type.name,
        'status': status.name,
        if (eventId != null) 'event_id': eventId,
        if (message != null) 'message': message,
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };
}
