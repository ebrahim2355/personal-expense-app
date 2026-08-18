import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/notification_settings.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/notifications/notification_permissions.dart';

import 'support/fakes.dart' show FakeNotificationPermissions;

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
    DateTime? now,
  }) => NotificationSettingsController(
    database: database,
    permissions: permissions,
    clock: () => now ?? DateTime.utc(2026, 8, 18, 12),
  );

  /// Drift stores a `DateTime` as epoch seconds and hands it back in local time,
  /// so compare the instant rather than the value's own timezone flag.
  Future<DateTime?> storedRequestedAt() async =>
      (await database.readSyncMetadata()).notificationPermissionRequestedAt
          ?.toUtc();

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
}
