import '../remote/api_models.dart';

/// Announced by every repository after a local write commits, so the sync
/// triggers can push the outbox without knowing which entity changed.
final class LocalMutationEvent {
  const LocalMutationEvent(this.entityType, this.entityId);

  final SyncEntityType entityType;
  final String entityId;
}

enum OutboxStatus { pending, inFlight, needsAttention }

extension OutboxStatusStorage on OutboxStatus {
  String get storedName => switch (this) {
    OutboxStatus.pending => 'PENDING',
    OutboxStatus.inFlight => 'IN_FLIGHT',
    OutboxStatus.needsAttention => 'NEEDS_ATTENTION',
  };

  static OutboxStatus parse(String value) => switch (value) {
    'PENDING' => OutboxStatus.pending,
    'IN_FLIGHT' => OutboxStatus.inFlight,
    'NEEDS_ATTENTION' => OutboxStatus.needsAttention,
    _ => throw FormatException('Unknown outbox status: $value'),
  };
}
