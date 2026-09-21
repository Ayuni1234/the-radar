/// Result of a publish attempt (feed post, radar pin, event).
///
/// Replaces the old `bool` contract that conflated three very different
/// endings — which is how every server rejection used to be mislabeled as
/// "offline — queued for sync".
class PublishOutcome {
  const PublishOutcome._({
    required this.success,
    required this.queued,
    this.message,
  });

  /// The write reached the backend and was accepted.
  static const PublishOutcome ok = PublishOutcome._(success: true, queued: false);

  /// The backend rejected the write (validation, RLS, schema, permissions).
  /// Retrying without changing something will fail identically, so these
  /// are surfaced with the server's reason instead of being queued.
  factory PublishOutcome.rejected(String reason) =>
      PublishOutcome._(success: false, queued: false, message: reason);

  /// The write could not reach the backend (offline / transport failure).
  /// It has been stored in the outbox and will replay automatically.
  factory PublishOutcome.queued(String reason) =>
      PublishOutcome._(success: false, queued: true, message: reason);

  /// Local precondition failed (e.g. no signed-in profile).
  factory PublishOutcome.blocked(String reason) =>
      PublishOutcome._(success: false, queued: false, message: reason);

  final bool success;
  final bool queued;

  /// Human-readable detail — empty on success.
  final String? message;

  String get detail {
    final m = message?.trim() ?? '';
    if (m.isEmpty) return '';
    return queued ? '$m — saved for retry when you are back online' : m;
  }
}
