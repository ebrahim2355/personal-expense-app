import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/push_registration.dart';
import 'package:houseexpenses/src/application/session_controller.dart';
import 'package:houseexpenses/src/application/sync_coordinator.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/repositories/auth_repository.dart';
import 'package:houseexpenses/src/data/security/token_store.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/session.dart';

import 'support/fakes.dart'
    show
        FakeDeviceRegistrationApi,
        FakeExpenseSyncApi,
        FakePushMessaging,
        RecordingActivityNotifier,
        RecordingDeviceDeregistration;

void main() {
  late AppDatabase database;
  late FakeDeviceRegistrationApi api;
  late FakePushMessaging messaging;
  late SessionController session;
  late SyncCoordinator coordinator;
  late FakeExpenseSyncApi syncApi;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    api = FakeDeviceRegistrationApi();
    messaging = FakePushMessaging();
    session = SessionController(MemoryTokenStore());
    syncApi = FakeExpenseSyncApi();
    coordinator = SyncCoordinator(
      database: database,
      api: syncApi,
      notifier: RecordingActivityNotifier(),
    );
  });

  tearDown(() async {
    await messaging.close();
    await coordinator.close();
    await session.close();
    await database.close();
  });

  PushRegistrationController controller({DateTime? now}) =>
      PushRegistrationController(
        database: database,
        api: api,
        messaging: messaging,
        sessionController: session,
        syncCoordinator: coordinator,
        clock: () => now ?? DateTime.utc(2026, 8, 18, 12),
      );

  /// Drift hands a stored `DateTime` back in local time, so compare instants.
  Future<DateTime?> registeredAt() async =>
      (await database.readSyncMetadata()).fcmTokenRegisteredAt?.toUtc();

  Future<String?> fingerprint() async =>
      (await database.readSyncMetadata()).fcmTokenFingerprint;

  Future<DateTime?> pushReceivedAt() async =>
      (await database.readSyncMetadata()).lastPushReceivedAt?.toUtc();

  test('registers this device once it knows who is signed in', () async {
    session.markSignedIn();
    final push = controller();
    addTearDown(push.dispose);

    await push.start();

    expect(api.registered, <String>['fcm-token']);
    expect(await registeredAt(), DateTime.utc(2026, 8, 18, 12));
    expect(await fingerprint(), isNotNull);
  });

  test('waits for sign-in rather than calling an authenticated route', () async {
    final push = controller();
    addTearDown(push.dispose);

    await push.start();

    // The routes are authenticated, so registering before sign-in could only
    // ever produce a 401 — and the listener below is what makes it unnecessary.
    expect(api.registered, isEmpty);
    expect(await registeredAt(), isNull);

    session.markSignedIn();
    await Future<void>.delayed(Duration.zero);

    expect(api.registered, <String>['fcm-token']);
  });

  test('does not re-register a token the API already has', () async {
    session.markSignedIn();
    final first = controller();
    await first.start();
    await first.dispose();

    final second = controller();
    addTearDown(second.dispose);
    await second.start();

    // One POST per token, not one per launch. The fingerprint is the whole
    // reason the column exists.
    expect(api.registered, <String>['fcm-token']);
    expect(messaging.tokenCalls, 2);
  });

  test('retries on the next launch when the registration failed', () async {
    session.markSignedIn();
    api.failure = StateError('502 from the API');
    final first = controller();
    await first.start();
    await first.dispose();

    // Nothing recorded, precisely so the next launch tries again: a stored
    // fingerprint with no timestamp would otherwise look like success.
    expect(await registeredAt(), isNull);
    expect(await fingerprint(), isNull);

    api.failure = null;
    final second = controller();
    addTearDown(second.dispose);
    await second.start();

    expect(api.registered, <String>['fcm-token']);
    expect(await registeredAt(), isNotNull);
  });

  test('registers the new token when Google rotates it', () async {
    session.markSignedIn();
    final push = controller();
    addTearDown(push.dispose);
    await push.start();

    messaging.refreshes.add('fcm-token-2');
    await Future<void>.delayed(Duration.zero);

    // A missed rotation is invisible — the phone simply stops being woken — so
    // this is the subscription that keeps push working past the first token.
    expect(api.registered, <String>['fcm-token', 'fcm-token-2']);
  });

  test('survives a phone with no Play Services', () async {
    session.markSignedIn();
    messaging.available = false;
    final push = controller();
    addTearDown(push.dispose);

    await push.start();

    expect(api.registered, isEmpty);
    expect(await registeredAt(), isNull);
  });

  test('syncs and records the wake when a push arrives in the foreground', () async {
    session.markSignedIn();
    final push = controller();
    addTearDown(push.dispose);
    await push.start();
    final pullsBefore = syncApi.pullCalls;

    messaging.pushes.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(syncApi.pullCalls, greaterThan(pullsBefore));
    // The timestamp is what separates a real push from a well-timed poll on the
    // Settings screen.
    expect(await pushReceivedAt(), DateTime.utc(2026, 8, 18, 12));
  });

  test('does not record a background run when a push arrives', () async {
    session.markSignedIn();
    final push = controller();
    addTearDown(push.dispose);
    await push.start();

    messaging.pushes.add(null);
    await Future<void>.delayed(Duration.zero);

    // Settings would otherwise report Android as running the scheduled worker on
    // the strength of a push, which is a different question with a different fix.
    expect((await database.readSyncMetadata()).lastBackgroundSyncAt, isNull);
  });

  test('gives up the token and the local record on sign-out', () async {
    session.markSignedIn();
    final push = controller();
    addTearDown(push.dispose);
    await push.start();

    await push.unregister();

    expect(api.unregistered, <String>['fcm-token']);
    expect(await fingerprint(), isNull);
    expect(await registeredAt(), isNull);
  });

  test('signs out locally even when the API refuses the deregistration', () async {
    session.markSignedIn();
    final push = controller();
    addTearDown(push.dispose);
    await push.start();
    api.failure = StateError('offline');

    await expectLater(push.unregister(), completes);

    // The member asked to be signed out. The cost of a failed deregistration is
    // a phone that may be woken until its token rotates, which is survivable;
    // blocking sign-out is not.
    expect(await fingerprint(), isNull);
  });

  group('sign-out', () {
    test('gives the push token up before the tokens are revoked', () async {
      final store = MemoryTokenStore(
        SessionTokens(
          accessToken: 'access',
          accessTokenExpiresAt: DateTime.utc(2026, 8, 18, 13),
          refreshToken: 'refresh',
          refreshTokenExpiresAt: DateTime.utc(2026, 9, 18),
        ),
      );
      final calls = <String>[];
      final deregistration = RecordingDeviceDeregistration(
        onUnregister: () => calls.add('deregister'),
      );
      final repository = AuthRepository(
        api: _RecordingAuthenticationApi(() => calls.add('logout')),
        tokenStore: store,
        sessionController: session,
        database: database,
        deviceDeregistration: deregistration,
      );

      await repository.logout();

      // Order is the whole point: `/v1/devices/unregister` is authenticated, and
      // the logout call is what revokes the token it needs.
      expect(calls, <String>['deregister', 'logout']);
      expect(store.tokens, isNull);
      expect(session.current.status, SessionStatus.signedOut);
    });

    test(
      'does not call the API when there is nothing to sign out of',
      () async {
        final deregistration = RecordingDeviceDeregistration();
        final repository = AuthRepository(
          api: _RecordingAuthenticationApi(() {}),
          tokenStore: MemoryTokenStore(),
          sessionController: session,
          database: database,
          deviceDeregistration: deregistration,
        );

        await repository.logout();

        expect(deregistration.calls, 0);
        expect(session.current.status, SessionStatus.signedOut);
      },
    );
  });
}

/// Records that logout reached the API, which is all the ordering test needs.
final class _RecordingAuthenticationApi implements AuthenticationApi {
  _RecordingAuthenticationApi(this._onLogout);

  final void Function() _onLogout;

  @override
  Future<AuthResponseDto> login(HouseholdMember member, String pin) =>
      throw UnimplementedError('login is not part of this test');

  @override
  Future<void> logout(SessionTokens tokens) async => _onLogout();
}
