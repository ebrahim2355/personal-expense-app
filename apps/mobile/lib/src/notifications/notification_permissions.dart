/// The device's notification permission, as far as the app can observe it.
///
/// Split from [HouseholdActivityNotifier] because the two have different
/// callers: the sync path only ever posts, while startup and the Settings screen
/// only ever ask about permission. Keeping them apart lets each depend on the
/// narrower interface, and lets a widget test drive the Settings card without a
/// platform channel.
abstract interface class NotificationPermissions {
  /// Whether Android will currently display this app's notifications.
  ///
  /// False when the member denied the runtime permission or switched the app's
  /// notifications off in Android Settings — and also when the answer cannot be
  /// obtained at all, since "we cannot confirm they work" and "they do not work"
  /// deserve the same honest treatment in the UI.
  Future<bool> areNotificationsEnabled();

  /// Shows Android's runtime permission dialog and reports the outcome.
  ///
  /// Android only shows the dialog once per install; afterwards this resolves
  /// immediately with the standing answer, which is why the Settings screen
  /// offers instructions rather than an "ask again" button.
  Future<bool> requestPermission();
}
