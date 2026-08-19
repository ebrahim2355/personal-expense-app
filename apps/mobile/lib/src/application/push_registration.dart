import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/local/app_database.dart';
import '../data/remote/api_client.dart';
import '../domain/session.dart';
import '../notifications/push_messaging.dart';
import 'session_controller.dart';
import 'sync_coordinator.dart';

/// The one thing signing out needs from push registration.
///
/// Split out for the same reason `NotificationPermissions` is split from
/// `HouseholdActivityNotifier`: `AuthRepository` has no business with tokens,
/// streams or Firebase, and a one-method dependency is one a test can satisfy
/// without building any of that.
abstract interface class DeviceDeregistration {
  /// Stops the API from waking this device, and forgets the local record of it.
  ///
  /// Must never throw. Sign-out is the member's decision and cannot be blocked
  /// by a network the phone does not have.
  Future<void> unregister();
}

/// For the callers that never registered a device to begin with — the real-stack
/// tests, and any future entry point that signs out without a push isolate.
///
/// Named rather than nullable so a wiring mistake reads as a deliberate choice
/// instead of a forgotten argument.
const DeviceDeregistration noDeviceDeregistration = _NoDeviceDeregistration();

final class _NoDeviceDeregistration implements DeviceDeregistration {
  const _NoDeviceDeregistration();

  @override
  Future<void> unregister() async {}
}

/// Keeps the API's list of devices to wake in step with this install's FCM
/// token, and turns a foreground push into a sync.
///
/// Modelled on `SyncTriggerController`: it subscribes on [start], every platform
/// and network call is best-effort, and [dispose] cancels what it opened. The
/// reason it is a controller and not a one-shot call at startup is
/// [PushMessaging.tokenRefreshes] — Google can reissue a token at any time, and a
/// device that misses that silently stops being woken with no symptom the member
/// could ever notice.
final class PushRegistrationController implements DeviceDeregistration {
  PushRegistrationController({
    required this._database,
    required this._api,
    required this._messaging,
    required this._sessionController,
    required this._syncCoordinator,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final AppDatabase _database;
  final DeviceRegistrationApi _api;
  final PushMessaging _messaging;
  final SessionController _sessionController;
  final SyncCoordinator _syncCoordinator;
  final DateTime Function() _clock;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _subscriptions.add(
      _sessionController.changes.listen((session) {
        if (session.status == SessionStatus.signedIn) {
          unawaited(_registerCurrentToken());
        }
      }),
    );
    _subscriptions.add(
      // A refreshed token makes the stored one dead, so this registers whatever
      // Google just issued rather than re-reading the current one.
      _messaging.tokenRefreshes.listen((token) {
        unawaited(_register(token));
      }),
    );
    _subscriptions.add(
      _messaging.foregroundMessages.listen((_) {
        unawaited(_handleForegroundPush());
      }),
    );
    await _registerCurrentToken();
  }

  /// Gives up this device's token, so a signed-out phone stops being woken.
  ///
  /// Called from `AuthRepository.logout` before the tokens are discarded,
  /// because the request needs an access token that is still valid. The local
  /// record is cleared either way: a phone that could not reach the API on the
  /// way out must still re-register on the next sign-in, and re-registering a
  /// token the server already has costs one idempotent upsert.
  @override
  Future<void> unregister() async {
    try {
      final token = await _messaging.currentToken();
      if (token != null) {
        await _api.unregister(token);
      }
    } on Object {
      // A failed deregistration leaves the server able to wake a signed-out
      // phone until the token rotates. Blocking sign-out on it would be worse:
      // the member asked to be signed out.
    }
    try {
      await _database.clearDeviceRegistration();
    } on Object {
      // Nothing left to do about a database that will not write; the next
      // sign-in re-registers anyway if the fingerprint is gone, and re-POSTs
      // harmlessly if it is not.
    }
  }

  Future<void> dispose() async {
    if (!_started) {
      return;
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _started = false;
  }

  Future<void> _registerCurrentToken() async {
    if (_sessionController.current.status != SessionStatus.signedIn) {
      // The registration routes are authenticated, and there is nobody to
      // register the device to yet. The sign-in listener above picks this up.
      return;
    }
    final token = await _messaging.currentToken();
    if (token == null) {
      // No Play Services, no `google-services.json`, or no route to Google. The
      // app is fully functional on background polling; it just is not fast.
      return;
    }
    await _register(token);
  }

  Future<void> _register(String token) async {
    try {
      final fingerprint = _fingerprint(token);
      final metadata = await _database.readSyncMetadata();
      // Both conditions matter. A matching fingerprint alone would skip a
      // registration whose POST failed last launch, and a null timestamp alone
      // would re-POST on every open.
      if (metadata.fcmTokenFingerprint == fingerprint &&
          metadata.fcmTokenRegisteredAt != null) {
        return;
      }
      await _api.register(token);
      await _database.recordDeviceRegistration(
        fingerprint: fingerprint,
        at: _clock(),
      );
    } on Object {
      // Deliberately leaves `fcmTokenRegisteredAt` null so the next launch tries
      // again. Until one succeeds this device is only reached by the poll, which
      // is exactly where it was before push existed.
    }
  }

  Future<void> _handleForegroundPush() async {
    try {
      // Reuses the UI isolate's coordinator rather than building a second one:
      // the app is on screen, so its wiring is already alive and its own
      // notifier already applies the household-activity toggle.
      await _syncCoordinator.synchronize();
      await _database.recordPushReceived(_clock());
    } on Object {
      // A push is a hint, not a delivery. Failing to act on one costs at most
      // the delay until the next sync.
    }
  }

  /// The digest the server's `tokenHash` habit is borrowed from: the local
  /// database keeps only a fingerprint, so a stolen database cannot be used to
  /// send this phone anything.
  String _fingerprint(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}
