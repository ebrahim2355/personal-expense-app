import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// The device's Firebase Cloud Messaging registration, as far as the app needs
/// it.
///
/// Narrow on purpose. Everything about *what* a push means lives in
/// [PushRegistrationController] and the sync path; this is only the boundary to
/// Play Services, which is what makes it faked wholesale in tests.
///
/// It must never ask for the notification permission.
/// `NotificationSettingsController.ensureNotificationPermission` is the single
/// owner of that ask, and its rule — never record an ask that failed to reach
/// Android — is the fix for a bug that once left the permission permanently
/// unasked. A second asker would silently defeat it.
abstract interface class PushMessaging {
  /// This install's registration token, or null when there is none to be had.
  ///
  /// Null is a normal answer, not an error: a phone with no Play Services, a
  /// build with no `google-services.json`, and a device that simply cannot reach
  /// Google right now all land here, and all of them must still run the app on
  /// background polling alone.
  Future<String?> currentToken();

  /// Emits whenever Google issues this install a new token. The old one stops
  /// working, so a device that misses this stops being woken.
  Stream<String> get tokenRefreshes;

  /// Emits once per push that arrives while the app is in the foreground.
  ///
  /// Background and terminated deliveries never come through here — they run in
  /// their own isolate, wired in `background_sync.dart`.
  Stream<void> get foregroundMessages;
}

final class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<String?> currentToken() async {
    try {
      return await _messaging.getToken();
    } on Object {
      // A phone without working Play Services must still open, sync, and notify
      // on the fifteen-minute poll. All this costs is the instant wake.
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<void> get foregroundMessages =>
      // The payload is deliberately dropped. A push carries no detail — the
      // local database is what the notification is composed from — so the only
      // information in a message is that one arrived.
      FirebaseMessaging.onMessage.map<void>((message) {});
}
