import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_coordinator.dart';
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
                Text(
                  'Android decides when background work can run and does not '
                  'guarantee an immediate sync. Open the app or tap refresh '
                  'to request one now. Notifications about the other member '
                  'arrive with that sync, so they inherit the same delay.',
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
    // Until the platform answers, assume notifications work: showing the
    // re-enable instructions for a moment on every visit would cry wolf.
    final blocked = systemEnabled.valueOrNull == false;
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
          if (blocked) ...<Widget>[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.notifications_off_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Android is blocking notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Android will not re-show its permission dialog once it has
                  // been answered, so an in-app "ask again" button would be a
                  // lie. Instructions plus a re-check are the honest options.
                  const Text(
                    'Open Android Settings → Apps → Household Expenses → '
                    'Notifications and allow them, then re-check here.',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('recheck-notification-permission-button'),
                      onPressed: () =>
                          ref.invalidate(systemNotificationsEnabledProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-check'),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
