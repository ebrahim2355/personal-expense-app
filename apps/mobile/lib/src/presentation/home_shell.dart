import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_coordinator.dart';
import '../domain/expense.dart';
import '../domain/session.dart';
import '../providers.dart';
import 'dashboard_screen.dart';
import 'expense_form_screen.dart';
import 'history_screen.dart';
import 'presentation_providers.dart';
import 'settings_screen.dart';

final class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.member, super.key});

  final MemberIdentity member;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SyncNotice>>(syncNoticesProvider, (previous, next) {
      next.whenData((notice) {
        final icon = notice.kind == SyncNoticeKind.conflict
            ? Icons.merge_type
            : Icons.sync_problem_outlined;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('sync-notice-banner'),
              content: Row(
                children: <Widget>[
                  Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(notice.message)),
                ],
              ),
            ),
          );
      });
    });

    final screens = <Widget>[
      DashboardScreen(onOpenExpense: _editExpense),
      HistoryScreen(onEditExpense: _editExpense),
      SettingsScreen(member: widget.member),
    ];
    const titles = <String>['Dashboard', 'Expense history', 'Settings'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
        actions: _selectedIndex == 2
            ? null
            : <Widget>[
                IconButton(
                  tooltip: 'Sync now',
                  onPressed: () =>
                      ref.read(manualSyncControllerProvider.notifier).run(),
                  icon: const Icon(Icons.sync),
                ),
              ],
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      floatingActionButton: _selectedIndex == 2
          ? null
          : FloatingActionButton.extended(
              key: const Key('add-expense-button'),
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _addExpense() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            ExpenseFormScreen(defaultPayer: widget.member.member),
      ),
    );
  }

  Future<void> _editExpense(Expense expense) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ExpenseFormScreen(
          defaultPayer: widget.member.member,
          expense: expense,
        ),
      ),
    );
  }
}
