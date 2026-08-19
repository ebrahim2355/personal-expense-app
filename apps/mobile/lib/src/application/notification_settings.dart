import 'package:drift/drift.dart';

import '../background/background_work_policy.dart';
import '../data/local/app_database.dart';
import '../notifications/notification_permissions.dart';

/// The two independent switches that decide whether a notification arrives, plus
/// the one that decides when.
final class NotificationSettings {
  const NotificationSettings({
    required this.systemEnabled,
    required this.householdActivityEnabled,
    required this.batteryExemptionGranted,
  });

  /// Whether Android will display this app's notifications at all. Owned by the
  /// runtime permission and by Android's own app settings, not by this app.
  final bool systemEnabled;

  /// Whether this device announces the other member's activity. Owned by the
  /// Settings toggle.
  final bool householdActivityEnabled;

  /// Whether Android is willing to run this app's background work on time.
  ///
  /// Deliberately absent from [willNotify]: this governs *when* a notification
  /// arrives, not whether it can be posted. Folding it in would make Settings
  /// report notifications as off when they are merely late, which is a different
  /// problem with a different fix.
  final bool batteryExemptionGranted;

  /// Notifications only actually reach the member when both are on.
  bool get willNotify => systemEnabled && householdActivityEnabled;
}

/// Owns the notification preferences and the two one-time platform asks.
///
/// Separate from the presenter because these are two different concerns: the
/// presenter talks to the platform, this decides when to and remembers what the
/// member chose.
///
/// The battery-optimization ask lives here rather than alongside the scheduler
/// because it is the same shape as the permission ask — check the live platform
/// answer, ask at most once, record it — and because it exists only to serve
/// notification timeliness. That is a deliberate widening of this class, not
/// drift.
final class NotificationSettingsController {
  NotificationSettingsController({
    required this._database,
    required this._permissions,
    required this._policy,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final AppDatabase _database;
  final NotificationPermissions _permissions;
  final BackgroundWorkPolicy _policy;
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

  /// Asks Android to exempt this app from battery optimization, at most once.
  ///
  /// Gated on the live platform answer first, so an install that already has the
  /// exemption is never nagged and one that was granted it outside the app
  /// self-heals. Unlike the notification dialog this one can be re-shown at will,
  /// so the stored timestamp exists to avoid pestering the member on every
  /// launch, not to ration a single chance.
  ///
  /// A dialog that never launched is not recorded. Recording it would spend the
  /// ask on something nobody saw — the same mistake that left the notification
  /// permission permanently unasked.
  Future<void> ensureBackgroundExemption() async {
    try {
      if (await _policy.isExemptFromBatteryOptimization()) {
        return;
      }
      final metadata = await _database.readSyncMetadata();
      if (metadata.batteryExemptionRequestedAt != null) {
        return;
      }
      if (!await _policy.requestBatteryExemption()) {
        return;
      }
      await _write(
        SyncMetadataCompanion(
          batteryExemptionRequestedAt: Value<DateTime>(_clock()),
        ),
      );
    } on Object {
      // Same contract as the permission ask: startup must survive a platform
      // that cannot answer. The cost is late notifications, which is where this
      // device already was.
    }
  }

  Future<NotificationSettings> read() async {
    final metadata = await _database.readSyncMetadata();
    return NotificationSettings(
      systemEnabled: await _permissions.areNotificationsEnabled(),
      householdActivityEnabled: metadata.householdActivityNotificationsEnabled,
      batteryExemptionGranted: await _policy.isExemptFromBatteryOptimization(),
    );
  }

  /// Shows Android's battery-optimization dialog on demand, for the Settings
  /// button. Reports whether a dialog appeared; the member's answer only shows up
  /// in a later [read].
  Future<bool> requestBatteryExemption() => _policy.requestBatteryExemption();

  /// Opens this app's page in Android Settings, for the states no dialog can fix.
  Future<bool> openAppSettings() => _policy.openAppSettings();

  /// When the background isolate last finished a run, or null when it never has.
  Stream<DateTime?> watchLastBackgroundSync() =>
      _database.watchSyncMetadata().map((row) => row.lastBackgroundSyncAt);

  /// When a push last woke this device, or null when none ever has.
  ///
  /// The one honest answer to "does push actually work on this phone". Separate
  /// from [watchLastBackgroundSync] because a poll that happens to land seconds
  /// after a change is indistinguishable from a push unless the two are counted
  /// apart.
  Stream<DateTime?> watchLastPushReceived() =>
      _database.watchSyncMetadata().map((row) => row.lastPushReceivedAt);

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
