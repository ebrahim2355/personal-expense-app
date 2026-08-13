import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expense.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common_widgets.dart';
import 'presentation_providers.dart';

final class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({required this.onOpenExpense, super.key});

  final ValueChanged<Expense> onOpenExpense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dashboardRangeProvider);
    final expenses = ref.watch(visibleExpensesProvider);

    return expenses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _DashboardError(
        onRetry: () => ref.invalidate(visibleExpensesProvider),
      ),
      data: (allExpenses) {
        final selected = allExpenses
            .where((expense) => range.contains(expense.occurredAt))
            .toList(growable: false);
        final summary = summarizeExpenses(selected);
        final recent = selected.take(5).toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(manualSyncControllerProvider.notifier).run();
          },
          child: ListView(
            key: const PageStorageKey<String>('dashboard-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: DateRangeButton(
                  range: range,
                  onPressed: () async {
                    final next = await pickExpenseDateRange(context, range);
                    if (next != null) {
                      ref.read(dashboardRangeProvider.notifier).state = next;
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              _TotalCard(summary: summary),
              const SizedBox(height: 12),
              _SettlementCard(summary: summary),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      SizedBox(
                        width: width,
                        child: _MemberSummaryCard(
                          member: HouseholdMember.sumon,
                          paidMinor: summary.sumonPaidMinor,
                          allocatedMinor: summary.sumonAllocatedMinor,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _MemberSummaryCard(
                          member: HouseholdMember.ebrahim,
                          paidMinor: summary.ebrahimPaidMinor,
                          allocatedMinor: summary.ebrahimAllocatedMinor,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const SyncStatusCard(),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Recent expenses',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text('${selected.length} in range'),
                ],
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                const _EmptyDashboard()
              else
                ...recent.map(
                  (expense) => ExpenseListTile(
                    expense: expense,
                    onTap: () => onOpenExpense(expense),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

final class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Total household spending',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatBdt(summary.totalMinor),
                key: const Key('dashboard-total'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final settled = summary.sumonBalanceMinor == 0;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          child: Icon(
            settled ? Icons.handshake_outlined : Icons.payments_outlined,
          ),
        ),
        title: Text(
          summary.settlementText,
          key: const Key('settlement-text'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Based on the selected range and equal shares'),
      ),
    );
  }
}

final class _MemberSummaryCard extends StatelessWidget {
  const _MemberSummaryCard({
    required this.member,
    required this.paidMinor,
    required this.allocatedMinor,
  });

  final HouseholdMember member;
  final int paidMinor;
  final int allocatedMinor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              member.displayName,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _AmountLine(label: 'Paid', amountMinor: paidMinor),
            const SizedBox(height: 6),
            _AmountLine(label: 'Allocated share', amountMinor: allocatedMinor),
          ],
        ),
      ),
    );
  }
}

final class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.amountMinor});

  final String label;
  final int amountMinor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        Text(
          formatBdt(amountMinor),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

final class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No expenses in this range',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap Add expense to record one, even while offline.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

final class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            const Text('Could not read expenses from this device.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
