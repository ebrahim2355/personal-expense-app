import '../data/remote/api_models.dart';
import '../domain/expense.dart';

/// One piece of the other member's activity, ready to be announced.
///
/// Built from a change the server attributed to the other member and that
/// actually altered local state. Carrying the snapshot rather than pre-rendered
/// strings keeps the wording decisions in one pure place
/// (`activity_notification_text.dart`) and lets a test assert on the change
/// itself.
final class HouseholdActivity {
  const HouseholdActivity({
    required this.actor,
    required this.operation,
    required this.snapshot,
  });

  /// The member who made the change. Never this device's own member.
  final HouseholdMember actor;
  final ChangeOperation operation;
  final EntitySnapshotDto snapshot;

  SyncEntityType get entityType => snapshot.entityType;

  /// Identifies the notification this activity replaces or creates. Derived from
  /// the entity and its server version so re-applying the same change — a
  /// retried page, a resumed sync — cannot post twice.
  String get dedupeKey => '${snapshot.entityId}:${snapshot.version}';
}

/// Announces the other member's activity to whoever is watching the device.
///
/// [SyncCoordinator] depends on this interface rather than on
/// `flutter_local_notifications` so the sync path stays unit-testable, and so a
/// coordinator built without a notifier stays completely silent.
abstract interface class HouseholdActivityNotifier {
  /// Posts every activity in one synced batch.
  ///
  /// Called only after the transaction that applied the batch has committed, so
  /// an implementation may assume the local database already agrees with what it
  /// is about to announce. Must never throw: a failure to notify is not a reason
  /// to fail a sync that already succeeded.
  Future<void> announce(List<HouseholdActivity> activities);
}
