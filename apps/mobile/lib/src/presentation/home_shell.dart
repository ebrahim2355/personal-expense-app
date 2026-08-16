import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_coordinator.dart';
import '../domain/expense.dart';
import '../domain/loan.dart';
import '../domain/session.dart';
import '../providers.dart';
import 'dashboard_screen.dart';
import 'expense_form_screen.dart';
import 'history_screen.dart';
import 'lending_screen.dart';
import 'loan_form_screen.dart';
import 'presentation_providers.dart';
import 'settings_screen.dart';

/// The tabs, in the order they appear. Named so the app bar, the floating
/// action button and the navigation bar all agree without an index to remember.
enum _Tab { dashboard, lending, history, settings }

final class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.member, super.key});

  final MemberIdentity member;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends ConsumerState<HomeShell> {
  _Tab _tab = _Tab.dashboard;

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
      LendingScreen(onEditLoan: _editLoan),
      HistoryScreen(onEditExpense: _editExpense),
      SettingsScreen(member: widget.member),
    ];
    final title = switch (_tab) {
      _Tab.dashboard => 'Dashboard',
      _Tab.lending => 'Lending',
      _Tab.history => 'Expense history',
      _Tab.settings => 'Settings',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: _tab == _Tab.settings
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
      body: IndexedStack(index: _tab.index, children: screens),
      floatingActionButton: switch (_tab) {
        // Each ledger gets its own entry point, so a member on the lending page
        // never has to guess which kind of record the button will create.
        _Tab.dashboard || _Tab.history => FloatingActionButton.extended(
          key: const Key('add-expense-button'),
          onPressed: _addExpense,
          icon: const Icon(Icons.add),
          label: const Text('Add expense'),
        ),
        _Tab.lending => FloatingActionButton.extended(
          key: const Key('add-loan-button'),
          onPressed: _addLoan,
          icon: const Icon(Icons.add),
          label: const Text('Add loan'),
        ),
        _Tab.settings => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (index) {
          setState(() => _tab = _Tab.values[index]);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'Lending',
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

  Future<void> _addLoan() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            LoanFormScreen(defaultDebtor: widget.member.member),
      ),
    );
  }

  Future<void> _editLoan(Loan loan) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            LoanFormScreen(defaultDebtor: widget.member.member, loan: loan),
      ),
    );
  }
}
