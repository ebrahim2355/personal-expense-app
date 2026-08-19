import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_coordinator.dart';
import '../domain/dhaka_time.dart';
import '../domain/session.dart';
import '../providers.dart';
import 'common_widgets.dart';
import 'presentation_providers.dart';

final class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({required this.member, super.key});

  final MemberIdentity member;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(apiEnvironmentLabelProvider);
    final packageInfo = ref.watch(packageInfoProvider);
    return ListView(
      key: const PageStorageKey<String>('settings-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            minVerticalPadding: 16,
            leading: CircleAvatar(
              child: Text(widget.member.displayName.substring(0, 1)),
            ),
            title: Text(widget.member.displayName),
            subtitle: const Text('Household member'),
          ),
        ),
        const SizedBox(height: 12),
        const SyncStatusCard(),
        if (kDebugMode) ...<Widget>[
          const SizedBox(height: 12),
          const _DebugSyncDiagnosticsCard(),
        ],
        const SizedBox(height: 20),
        Text('Notifications', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        const _NotificationsCard(),
        const SizedBox(height: 20),
        Text('App', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('API environment'),
                subtitle: Text(environment),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('App version'),
                subtitle: Text(
                  packageInfo.when(
                    data: (info) => '${info.version} (${info.buildNumber})',
                    loading: () => 'Loading…',
                    error: (_, _) => 'Unavailable',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Your data', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Card(
          margin: EdgeInsets.zero,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Works offline',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Expenses are saved on this device first, so totals and '
                  'history remain usable without internet. Pending changes '
                  'sync automatically when the API is reachable.',
                ),
                SizedBox(height: 12),
                Text(
                  'Background sync is best effort',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                // Says out loud what the notification card only implies: even a
                // fully permitted app is polling, so "sooner" is the most this
                // can promise. Better here than a surprise later.
                Text(
                  'Sync runs about every fifteen minutes in the background, '
                  'and Android decides when — it does not guarantee an '
                  'immediate run. Open the app or tap refresh to request one '
                  'now. Notifications about the other member arrive with that '
                  'sync, so they inherit the same delay.',
                ),
                SizedBox(height: 6),
                Text(
                  'Allowing background activity under Notifications above '
                  'makes those runs far more punctual, and leaving the app in '
                  'Recents keeps them happening at all. Neither makes delivery '
                  'instant.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const Key('logout-button'),
          onPressed: _loggingOut ? null : _confirmLogout,
          icon: _loggingOut
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
          label: Text(_loggingOut ? 'Signing out…' : 'Sign out'),
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Expenses already saved on this device will not be deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-logout-button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _loggingOut = true);
    await ref.read(authRepositoryProvider).logout();
  }
}

final class _NotificationsCard extends ConsumerWidget {
  const _NotificationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemEnabled = ref.watch(systemNotificationsEnabledProvider);
    final activityEnabled = ref.watch(
      householdActivityNotificationsEnabledProvider,
    );
    final exemption = ref.watch(batteryExemptionGrantedProvider);
    // Until the platform answers, assume notifications work: showing the
    // re-enable instructions for a moment on every visit would cry wolf. The
    // same optimism applies to the battery advisory below.
    final blocked = systemEnabled.valueOrNull == false;
    final throttled = exemption.valueOrNull == false;
    final enabled = activityEnabled.valueOrNull ?? true;
    return Card(
      key: const Key('notifications-card'),
      margin: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          SwitchListTile(
            key: const Key('household-activity-switch'),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Household activity'),
            subtitle: Text(
              enabled
                  ? 'Announce expenses, loans and periods the other member '
                        'adds, edits or deletes.'
                  : 'Nothing is announced. Sync keeps running as usual.',
            ),
            value: enabled,
            // Disabled until the stream has delivered a value, so a tap cannot
            // write a preference based on the placeholder above.
            onChanged: activityEnabled.hasValue
                ? (value) => ref
                      .read(notificationSettingsControllerProvider)
                      .setHouseholdActivityEnabled(value)
                : null,
          ),
          const Divider(height: 1),
          const _BackgroundDeliveryTile(),
          const Divider(height: 1),
          const _PushWakeTile(),
          if (blocked) ...<Widget>[
            const Divider(height: 1),
            _Advisory(
              icon: Icons.notifications_off_outlined,
              title: 'Android is blocking notifications',
              color: Theme.of(context).colorScheme.error,
              // Android will not re-show its permission dialog once it has been
              // answered, so an in-app "ask again" button would be a lie. A
              // shortcut to the right screen plus a re-check are the honest
              // options.
              body:
                  'Allow notifications for Household Expenses in Android '
                  'Settings, then re-check here.',
              actions: <Widget>[
                OutlinedButton.icon(
                  key: const Key('open-app-settings-button'),
                  onPressed: () => ref
                      .read(notificationSettingsControllerProvider)
                      .openAppSettings(),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open settings'),
                ),
                OutlinedButton.icon(
                  key: const Key('recheck-notification-permission-button'),
                  onPressed: () =>
                      ref.invalidate(systemNotificationsEnabledProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-check'),
                ),
              ],
            ),
          ],
          if (throttled) ...<Widget>[
            const Divider(height: 1),
            _Advisory(
              icon: Icons.battery_saver_outlined,
              title: 'Android is limiting background sync',
              // A warning, not an error: everything still works, just later.
              color: Theme.of(context).colorScheme.tertiary,
              // Deliberately about background sync rather than about
              // notifications: this stays true when the toggle above is off,
              // and the other member's changes arrive just as late either way.
              // Names the OEM's own wording for the control. Android's intent
              // opens a whole battery screen on this phone rather than a
              // yes/no dialog, and its default option is called "Battery
              // saver" — a member told only to "allow background activity"
              // picks that and changes nothing.
              body:
                  'Once the phone has been idle a while, Android defers this '
                  "app's background sync — sometimes for hours — so the other "
                  "member's changes, and any notification about them, arrive "
                  'late.\n\n'
                  'The button below opens this app\'s battery screen. Choose '
                  '"No restrictions" there; "Battery saver", the default, is '
                  'what causes the delay.\n\n'
                  'Clearing the app from Recents also stops background sync '
                  'until you next open it. To avoid that, enable Autostart for '
                  'Household Expenses in the Security app under Permissions.',
              actions: <Widget>[
                FilledButton.icon(
                  key: const Key('request-battery-exemption-button'),
                  onPressed: () => ref
                      .read(notificationSettingsControllerProvider)
                      .requestBatteryExemption(),
                  icon: const Icon(Icons.battery_charging_full_outlined),
                  label: const Text('Allow background activity'),
                ),
                // Not invalidated by the button above: the platform reports that
                // its screen opened, never what the member chose, so the app
                // cannot know when the answer is ready to re-read.
                OutlinedButton.icon(
                  key: const Key('recheck-battery-exemption-button'),
                  onPressed: () =>
                      ref.invalidate(batteryExemptionGrantedProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-check'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Reports whether background sync is actually running on this device.
///
/// Distinct from the "Last synced" line on [SyncStatusCard], which any
/// foreground sync also moves. Only this one can answer the question that
/// matters for notifications while the app is closed, and a null answer — never
/// run — is as informative as a timestamp.
final class _BackgroundDeliveryTile extends ConsumerWidget {
  const _BackgroundDeliveryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastRun = ref.watch(lastBackgroundSyncProvider);
    final String detail;
    if (!lastRun.hasValue) {
      detail = 'Checking…';
    } else if (lastRun.valueOrNull == null) {
      detail = 'Has not run yet on this device.';
    } else {
      detail =
          'Last ran '
          '${DhakaTime.initialize().formatDateTime(lastRun.valueOrNull!)}.';
    }
    return ListTile(
      key: const Key('background-delivery-tile'),
      leading: const Icon(Icons.sync_outlined),
      title: const Text('Background sync'),
      subtitle: Text(detail),
    );
  }
}

/// Reports whether a push has ever reached this device.
///
/// Kept apart from [_BackgroundDeliveryTile] because a poll that happens to land
/// seconds after the other member's change looks exactly like a push. Two
/// timestamps written by two paths is the only way to tell which mechanism is
/// actually working here — which matters, because the phone-specific reasons a
/// push never arrives are ones only the member can fix.
final class _PushWakeTile extends ConsumerWidget {
  const _PushWakeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPush = ref.watch(lastPushReceivedProvider);
    final String detail;
    if (!lastPush.hasValue) {
      detail = 'Checking…';
    } else if (lastPush.valueOrNull == null) {
      detail = 'Never received on this device.';
    } else {
      detail =
          'Last received '
          '${DhakaTime.initialize().formatDateTime(lastPush.valueOrNull!)}.';
    }
    return ListTile(
      key: const Key('push-wake-tile'),
      leading: const Icon(Icons.bolt_outlined),
      title: const Text('Push wake'),
      subtitle: Text(detail),
    );
  }
}

/// The shape both notification advisories share: a coloured heading, prose, and
/// the actions that can do something about it.
final class _Advisory extends StatelessWidget {
  const _Advisory({
    required this.icon,
    required this.title,
    required this.color,
    required this.body,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body),
          const SizedBox(height: 12),
          // Wrapped rather than a Row: two labelled buttons overflow a narrow
          // phone in the larger text scales.
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

final class _DebugSyncDiagnosticsCard extends ConsumerWidget {
  const _DebugSyncDiagnosticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursor = ref.watch(syncCursorProvider).valueOrNull;
    final pending = ref.watch(unresolvedMutationCountProvider).valueOrNull;
    final report = ref.watch(syncReportProvider).valueOrNull;
    final lastSync = ref.watch(lastSuccessfulSyncProvider).valueOrNull;
    return Card(
      key: const Key('debug-sync-diagnostics'),
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.bug_report_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Debug sync diagnostics',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DiagnosticLine(label: 'Cursor', value: _cursorPreview(cursor)),
            _DiagnosticLine(
              label: 'Pending',
              value: pending?.toString() ?? 'loading',
            ),
            _DiagnosticLine(
              label: 'Last result',
              value: _outcomeName(report?.outcome),
            ),
            _DiagnosticLine(
              label: 'Last success',
              value: lastSync?.toUtc().toIso8601String() ?? 'none',
            ),
          ],
        ),
      ),
    );
  }

  String _cursorPreview(String? cursor) {
    if (cursor == null) {
      return 'none';
    }
    const visibleLength = 24;
    return cursor.length <= visibleLength
        ? cursor
        : '${cursor.substring(0, visibleLength)}… (${cursor.length} chars)';
  }

  String _outcomeName(SyncOutcome? outcome) => outcome?.name ?? 'none';
}

final class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label: $value'),
    );
  }
}
