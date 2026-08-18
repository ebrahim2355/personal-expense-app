import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/notification_settings.dart';
import 'package:houseexpenses/src/background/background_work_policy.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/notifications/notification_permissions.dart';

import 'support/fakes.dart'
    show FakeBackgroundWorkPolicy, FakeNotificationPermissions;

/// A platform that cannot answer at all, which is what an unavailable plugin
/// looks like from here.
final class _ThrowingPermissions implements NotificationPermissions {
  @override
  Future<bool> areNotificationsEnabled() async =>
      throw StateError('no notification platform');

  @override
  Future<bool?> requestPermission() async =>
      throw StateError('no notification platform');
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  NotificationSettingsController controllerWith(
    NotificationPermissions permissions, {
    BackgroundWorkPolicy? policy,
    DateTime? now,
  }) => NotificationSettingsController(
    database: database,
    permissions: permissions,
    policy: policy ?? FakeBackgroundWorkPolicy(exempt: true),
    clock: () => now ?? DateTime.utc(2026, 8, 18, 12),
  );

  /// Drift stores a `DateTime` as epoch seconds and hands it back in local time,
  /// so compare the instant rather than the value's own timezone flag.
  Future<DateTime?> storedRequestedAt() async =>
      (await database.readSyncMetadata()).notificationPermissionRequestedAt
          ?.toUtc();

  Future<DateTime?> storedExemptionAskedAt() async =>
      (await database.readSyncMetadata()).batteryExemptionRequestedAt?.toUtc();

  test('does not ask when Android already shows notifications', () async {
    final permissions = FakeNotificationPermissions(enabled: true);

    await controllerWith(permissions).ensureNotificationPermission();

    expect(permissions.requestCalls, 0);
    expect(await storedRequestedAt(), isNull);
  });

  test('asks on first open and records when the member answered', () async {
    final permissions = FakeNotificationPermissions(
      enabled: false,
      grants: true,
    );
    final controller = controllerWith(permissions);

    await controller.ensureNotificationPermission();

    expect(permissions.requestCalls, 1);
    expect(permissions.enabled, isTrue);
    expect(await storedRequestedAt(), DateTime.utc(2026, 8, 18, 12));
  });

  test('an ask that never reached Android is not recorded as an answer', () async {
    // The exact failure a resource-shrunk status icon produced: the request
    // resolves without a dialog, so treating it as a denial would consume the
    // member's one chance to be asked.
    final permissions = FakeNotificationPermissions(
      enabled: false,
      canAsk: false,
    );
    final controller = controllerWith(permissions);

    await controller.ensureNotificationPermission();

    expect(permissions.requestCalls, 1);
    expect(await storedRequestedAt(), isNull);

    // The next launch tries again rather than giving up for the install's life.
    permissions.canAsk = true;
    await controller.ensureNotificationPermission();

    expect(permissions.requestCalls, 2);
    expect(permissions.enabled, isTrue);
    expect(await storedRequestedAt(), DateTime.utc(2026, 8, 18, 12));
  });

  test('a denial is recorded once and the timestamp is never rewritten', () async {
    final permissions = FakeNotificationPermissions(
      enabled: false,
      grants: false,
    );
    final controller = controllerWith(permissions);

    await controller.ensureNotificationPermission();

    expect(permissions.requestCalls, 1);
    expect(permissions.enabled, isFalse);
    final firstAnswer = await storedRequestedAt();
    expect(firstAnswer, DateTime.utc(2026, 8, 18, 12));

    // Android answers instantly and shows nothing the second time, so re-asking
    // is safe; the record of when the member answered must not move.
    await controllerWith(
      permissions,
      now: DateTime.utc(2026, 8, 19, 9),
    ).ensureNotificationPermission();

    expect(permissions.requestCalls, 2);
    expect(await storedRequestedAt(), firstAnswer);
  });

  test(
    'an unavailable platform neither throws nor records an answer',
    () async {
      final controller = controllerWith(_ThrowingPermissions());

      await expectLater(controller.ensureNotificationPermission(), completes);
      expect(await storedRequestedAt(), isNull);
    },
  );

  test(
    'does not ask for the exemption when Android already grants it',
    () async {
      final policy = FakeBackgroundWorkPolicy(exempt: true);

      await controllerWith(
        FakeNotificationPermissions(),
        policy: policy,
      ).ensureBackgroundExemption();

      expect(policy.requestCalls, 0);
      expect(await storedExemptionAskedAt(), isNull);
    },
  );

  test('asks for the exemption on first open and records the ask', () async {
    final policy = FakeBackgroundWorkPolicy();

    await controllerWith(
      FakeNotificationPermissions(),
      policy: policy,
    ).ensureBackgroundExemption();

    expect(policy.requestCalls, 1);
    expect(await storedExemptionAskedAt(), DateTime.utc(2026, 8, 18, 12));
  });

  test('a dialog that never launched is not recorded and is retried', () async {
    // Some OEM builds remove the activity. Recording that as an ask would spend
    // the one prompt on something the member never saw.
    final policy = FakeBackgroundWorkPolicy(canLaunchDialog: false);
    final controller = controllerWith(
      FakeNotificationPermissions(),
      policy: policy,
    );

    await controller.ensureBackgroundExemption();

    expect(policy.requestCalls, 1);
    expect(await storedExemptionAskedAt(), isNull);

    policy.canLaunchDialog = true;
    await controller.ensureBackgroundExemption();

    expect(policy.requestCalls, 2);
    expect(await storedExemptionAskedAt(), DateTime.utc(2026, 8, 18, 12));
  });

  test('a recorded ask is never repeated on a later launch', () async {
    final policy = FakeBackgroundWorkPolicy();
    final permissions = FakeNotificationPermissions();

    await controllerWith(
      permissions,
      policy: policy,
    ).ensureBackgroundExemption();

    final firstAsk = await storedExemptionAskedAt();
    expect(firstAsk, DateTime.utc(2026, 8, 18, 12));

    // Unlike the notification dialog this one would reappear every launch, so
    // the stored timestamp is what stops the app from nagging a member who
    // declined.
    await controllerWith(
      permissions,
      policy: policy,
      now: DateTime.utc(2026, 8, 19, 9),
    ).ensureBackgroundExemption();

    expect(policy.requestCalls, 1);
    expect(await storedExemptionAskedAt(), firstAsk);
  });

  test('an unavailable channel neither throws nor records an ask', () async {
    final controller = controllerWith(
      FakeNotificationPermissions(),
      policy: FakeBackgroundWorkPolicy(unavailable: true),
    );

    await expectLater(controller.ensureBackgroundExemption(), completes);
    expect(await storedExemptionAskedAt(), isNull);
  });

  test('the exemption is reported but kept out of willNotify', () async {
    final controller = controllerWith(
      FakeNotificationPermissions(enabled: true),
      policy: FakeBackgroundWorkPolicy(),
    );

    final settings = await controller.read();

    // Late is not the same problem as silent, so a throttled app still reports
    // that it will notify.
    expect(settings.batteryExemptionGranted, isFalse);
    expect(settings.willNotify, isTrue);
  });

  test(
    'a background run is recorded without disturbing the settings',
    () async {
      final controller = controllerWith(FakeNotificationPermissions());
      await controller.setHouseholdActivityEnabled(false);
      final before = await database.readSyncMetadata();
      final ranAt = DateTime.utc(2026, 8, 18, 16, 14, 9);

      await database.recordBackgroundSync(ranAt);

      final after = await database.readSyncMetadata();
      expect(after.lastBackgroundSyncAt?.toUtc(), ranAt);
      // The column answers "did Android let the worker run", so it must not
      // masquerade as a change the member made, nor as a foreground sync.
      expect(after.householdActivityNotificationsEnabled, isFalse);
      expect(after.updatedAt.toUtc(), before.updatedAt.toUtc());
      expect(after.lastSuccessfulSyncAt, isNull);
    },
  );

  test('Settings watches the background-run timestamp', () async {
    final controller = controllerWith(FakeNotificationPermissions());
    final ranAt = DateTime.utc(2026, 8, 18, 16, 14, 9);

    // Null before any run, which is what tells the member closed-app delivery
    // has never happened on this install.
    expect(await controller.watchLastBackgroundSync().first, isNull);

    await database.recordBackgroundSync(ranAt);

    expect((await controller.watchLastBackgroundSync().first)?.toUtc(), ranAt);
  });
}
