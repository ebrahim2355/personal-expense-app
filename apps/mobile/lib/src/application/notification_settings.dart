import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../notifications/notification_permissions.dart';

/// The two independent switches that decide whether a notification arrives.
final class NotificationSettings {
  const NotificationSettings({
    required this.systemEnabled,
    required this.householdActivityEnabled,
  });

  /// Whether Android will display this app's notifications at all. Owned by the
  /// runtime permission and by Android's own app settings, not by this app.
  final bool systemEnabled;

  /// Whether this device announces the other member's activity. Owned by the
  /// Settings toggle.
  final bool householdActivityEnabled;

  /// Notifications only actually reach the member when both are on.
  bool get willNotify => systemEnabled && householdActivityEnabled;
}

/// Owns the notification preferences and the one-time permission request.
///
/// Separate from the presenter because these are two different concerns: the
/// presenter talks to the platform, this decides when to and remembers what the
/// member chose.
final class NotificationSettingsController {
  NotificationSettingsController({
    required this._database,
    required this._permissions,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final AppDatabase _database;
  final NotificationPermissions _permissions;
  final DateTime Function() _clock;

  /// Asks for the notification permission unless Android is already showing
  /// this app's notifications.
  ///
  /// Gated on the platform's own answer rather than on a stored "already asked"
  /// flag. A flag cannot tell a real denial from an ask that never reached
  /// Android, so one failed ask would leave the member permanently unasked with
  /// no way back short of reinstalling — which is precisely what a
  /// resource-shrunk status icon did. Android shows its dialog only on the first
  /// ask of an install and answers instantly afterwards, so re-asking on a later
  /// launch costs a single platform call and never a second dialog.
  ///
  /// The timestamp records when the member first answered. It is written only
  /// once an answer has actually come back, and never rewritten.
  Future<void> ensureNotificationPermission() async {
    try {
      if (await _permissions.areNotificationsEnabled()) {
        return;
      }
      final answer = await _permissions.requestPermission();
      if (answer == null) {
        // Nothing reached Android, so nothing is recorded and the next launch
        // asks again.
        return;
      }
      final metadata = await _database.readSyncMetadata();
      if (metadata.notificationPermissionRequestedAt != null) {
        return;
      }
      await _write(
        SyncMetadataCompanion(
          notificationPermissionRequestedAt: Value<DateTime>(_clock()),
        ),
      );
    } on Object {
      // Startup, offline use and every existing screen must survive an
      // unavailable notification platform. A member who is never asked simply
      // gets no notifications.
    }
  }

  Future<NotificationSettings> read() async {
    final metadata = await _database.readSyncMetadata();
    return NotificationSettings(
      systemEnabled: await _permissions.areNotificationsEnabled(),
      householdActivityEnabled: metadata.householdActivityNotificationsEnabled,
    );
  }

  /// Re-reads Android's answer, for the button offered after a denial. Android
  /// will not re-show its dialog, so re-checking is the only truthful action
  /// available once a member has been to Android Settings and back.
  Future<bool> refreshSystemPermission() =>
      _permissions.areNotificationsEnabled();

  Stream<bool> watchHouseholdActivityEnabled() => _database
      .watchSyncMetadata()
      .map((row) => row.householdActivityNotificationsEnabled);

  Future<void> setHouseholdActivityEnabled(bool enabled) async {
    // Ensures the singleton exists before updating it.
    await _database.readSyncMetadata();
    await _write(
      SyncMetadataCompanion(
        householdActivityNotificationsEnabled: Value<bool>(enabled),
        updatedAt: Value<DateTime>(_clock()),
      ),
    );
  }

  Future<void> _write(SyncMetadataCompanion values) => (_database.update(
    _database.syncMetadata,
  )..where((row) => row.singletonId.equals(1))).write(values);
}
