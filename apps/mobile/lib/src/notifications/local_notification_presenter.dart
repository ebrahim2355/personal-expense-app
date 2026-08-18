import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'activity_notification_text.dart';
import 'household_activity_notifier.dart';
import 'notification_permissions.dart';

/// The single notification channel this app owns. Household activity is the only
/// thing the app ever posts, so a second channel would only add a switch that
/// does the same job as the one in Settings.
const String _channelId = 'household-activity';

/// Groups every posted change so Android collapses a multi-change sync into one
/// stack instead of a column of separate notifications.
const String _groupKey = 'household-activity';

/// The status-bar drawable, a flat white silhouette at
/// `android/app/src/main/res/drawable/ic_stat_notification.xml`. Named without
/// the `@drawable/` prefix and without the extension, which is what the plugin
/// expects.
const String _smallIcon = 'ic_stat_notification';

/// Reserved for the group summary. The summary is a single notification that
/// each new batch replaces, so it keeps a fixed id while the children hash
/// theirs.
const int _groupSummaryId = 0;

/// Posts household activity to the Android notification shade.
///
/// Also answers for the notification permission, because the plugin is what
/// knows: keeping both on one object means one initialization, and the channel
/// exists by the time a member is asked to allow notifications.
final class LocalNotificationPresenter
    implements HouseholdActivityNotifier, NotificationPermissions {
  LocalNotificationPresenter();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _readiness;

  @override
  Future<void> announce(List<HouseholdActivity> activities) async {
    if (activities.isEmpty) {
      return;
    }
    try {
      await _ensureReady();
      // Post the children first so the summary never appears above an empty
      // stack, and mute them when a summary will follow: N buzzes for one sync
      // is what makes a notification feature get switched off.
      final grouped = activities.length > 1;
      for (final activity in activities) {
        final text = describeActivity(activity);
        await _plugin.show(
          id: _notificationId(activity.dedupeKey),
          title: text.title,
          body: text.body,
          notificationDetails: NotificationDetails(
            android: _details(
              style: text.body == null
                  ? null
                  // Notes and category names outrun one collapsed line, so the
                  // detail stays readable when expanded.
                  : BigTextStyleInformation(text.body!),
              alertBehavior: grouped
                  ? GroupAlertBehavior.summary
                  : GroupAlertBehavior.all,
            ),
          ),
        );
      }
      if (grouped) {
        final batch = describeActivityBatch(activities);
        await _plugin.show(
          id: _groupSummaryId,
          title: batch.title,
          body: batch.body,
          notificationDetails: NotificationDetails(
            android: _details(
              isGroupSummary: true,
              alertBehavior: GroupAlertBehavior.summary,
              style: InboxStyleInformation(
                batch.lines,
                contentTitle: batch.title,
                summaryText: batch.body,
              ),
            ),
          ),
        );
      }
    } on Object {
      // Announcing is the last step of a sync whose transaction already
      // committed. A revoked permission, a channel torn down with the isolate,
      // any platform failure at all — none of it is a reason to report a
      // successful sync as failed. The member simply learns about the change the
      // next time they open the app, which is exactly today's behaviour.
    }
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } on Object {
      // Reported as disabled on purpose: Settings then shows the re-enable
      // instructions, which is the honest thing to say when the answer is
      // unknown.
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      // Initialize first so the channel exists the moment permission is
      // granted; a member who allows notifications and then opens Android's
      // notification settings should find the channel already listed.
      await _ensureReady();
      return await _android?.requestNotificationsPermission() ?? false;
    } on Object {
      return false;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Initializes the plugin and creates the channel, at most once per isolate.
  ///
  /// Every entry point calls this rather than relying on a caller to remember:
  /// the UI isolate and the WorkManager isolate each need their own
  /// initialization, and neither knows which will run first.
  Future<void> _ensureReady() async {
    final pending = _readiness ??= _initialize();
    try {
      await pending;
    } on Object {
      // A failed initialization must not be cached as the permanent answer.
      // Clearing it only if nothing else already replaced it keeps concurrent
      // callers from discarding a fresh attempt.
      if (_readiness == pending) {
        _readiness = null;
      }
      rethrow;
    }
  }

  Future<void> _initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
      ),
    );
    // Creating a channel that already exists is a no-op, so this is safe to run
    // on every launch. Importance is fixed at creation: Android ignores later
    // changes, deliberately, so that the member's own adjustments stick.
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Household activity',
        description:
            'Expenses, loans and spending periods the other member adds, '
            'edits or deletes.',
        importance: Importance.high,
      ),
    );
  }

  AndroidNotificationDetails _details({
    required GroupAlertBehavior alertBehavior,
    StyleInformation? style,
    bool isGroupSummary = false,
  }) => AndroidNotificationDetails(
    _channelId,
    'Household activity',
    channelDescription:
        'Expenses, loans and spending periods the other member adds, '
        'edits or deletes.',
    importance: Importance.high,
    // Honoured on Android 7.1 and older, where channels do not exist.
    priority: Priority.high,
    groupKey: _groupKey,
    setAsGroupSummary: isGroupSummary,
    groupAlertBehavior: alertBehavior,
    // Ids are stable, so a retried sync page re-shows a notification rather than
    // adding one. This keeps that replacement from buzzing a second time.
    onlyAlertOnce: true,
    styleInformation: style,
  );
}

/// A stable positive notification id for one change.
///
/// Android identifies a notification by an int and replaces rather than
/// duplicates when an id is reused, which is what makes a retried sync page
/// harmless. The id therefore has to survive a process restart, and that rules
/// out `String.hashCode` — Dart does not promise it is stable across runs — so
/// this is an explicit FNV-1a over the key.
int _notificationId(String dedupeKey) {
  var hash = 0x811c9dc5;
  for (final unit in dedupeKey.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final positive = hash & 0x7fffffff;
  // Must not land on the id the group summary holds.
  return positive == _groupSummaryId ? _groupSummaryId + 1 : positive;
}
