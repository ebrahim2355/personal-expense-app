import 'package:flutter/services.dart';

/// The channel `MainActivity` hosts. Namespaced by the application id so it
/// cannot collide with a plugin's.
const MethodChannel _channel = MethodChannel(
  'com.sumonebrahim.houseexpenses/background-work-policy',
);

/// Android's power-management stance toward this app's background work.
///
/// Split from [BackgroundSyncScheduler] because the two answer different
/// questions: the scheduler asks Android to run work, while this reports whether
/// Android is willing to run it on time and offers the member the switches that
/// change that. Kept behind an interface so the Settings screen can be driven in
/// a widget test with no platform channel attached.
///
/// **UI isolate only.** The channel is hosted by the Activity, so the
/// WorkManager isolate has no handler for it and must never call these. Nothing
/// here is needed there: background work asks no questions about itself.
abstract interface class BackgroundWorkPolicy {
  /// Whether this app is on Android's power-save whitelist.
  ///
  /// An exempt app moves to the EXEMPTED standby bucket and stops being subject
  /// to Doze and JobScheduler quota, which is what keeps a fifteen-minute
  /// periodic sync running on an idle phone. False when the answer cannot be
  /// obtained at all, for the same reason [NotificationPermissions] reports an
  /// unknown permission as disabled: "we cannot confirm it works" and "it does
  /// not work" deserve the same honest treatment in the UI.
  Future<bool> isExemptFromBatteryOptimization();

  /// Shows Android's battery-optimization dialog, reporting whether it was
  /// actually launched.
  ///
  /// True does **not** mean the member allowed anything — the answer arrives
  /// later and only by re-querying [isExemptFromBatteryOptimization]. False means
  /// no dialog appeared, which some OEM builds do by removing the activity
  /// outright. That distinction is not decoration: recording a dialog nobody saw
  /// as the member's answer is the bug that kept the notification permission from
  /// ever being asked for.
  Future<bool> requestBatteryExemption();

  /// Opens this app's page in Android Settings, reporting whether it opened.
  ///
  /// For the states no dialog can fix: notifications switched off after the
  /// runtime permission was answered, and the OEM autostart toggle, which no app
  /// can read or set.
  Future<bool> openAppSettings();
}

/// The real implementation, over the channel `MainActivity` registers.
final class AndroidBackgroundWorkPolicy implements BackgroundWorkPolicy {
  const AndroidBackgroundWorkPolicy();

  @override
  Future<bool> isExemptFromBatteryOptimization() =>
      _invoke('isExemptFromBatteryOptimization');

  @override
  Future<bool> requestBatteryExemption() => _invoke('requestBatteryExemption');

  @override
  Future<bool> openAppSettings() => _invoke('openAppSettings');

  /// Every call answers false rather than throwing. A missing handler is what a
  /// non-UI isolate and a stale Activity both look like from here, and neither is
  /// a reason to fail the caller: Settings simply shows the state it cannot rule
  /// out, and startup carries on without a dialog.
  Future<bool> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on Object {
      return false;
    }
  }
}
