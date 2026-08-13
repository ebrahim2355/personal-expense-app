import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  'to request one now.',
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
