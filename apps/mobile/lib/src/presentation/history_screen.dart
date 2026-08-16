import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expense.dart';
import '../domain/spending_period.dart';
import '../providers.dart';
import 'common_widgets.dart';
import 'presentation_providers.dart';

final class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({required this.onEditExpense, super.key});

  final ValueChanged<Expense> onEditExpense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final expenses = ref.watch(visibleExpensesProvider);

    return Column(
      children: <Widget>[
        _HistoryFilters(filter: filter),
        Expanded(
          child: expenses.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not read expense history.'),
              ),
            ),
            data: (allExpenses) {
              // History spans every period, closed ones included, so search and
              // the period selector are the only things that narrow it.
              final visible =
                  allExpenses.where(filter.includes).toList(growable: false)
                    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
              if (visible.isEmpty) {
                return const _EmptyHistory();
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await ref.read(manualSyncControllerProvider.notifier).run();
                },
                child: ListView.builder(
                  key: const PageStorageKey<String>('history-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final expense = visible[index];
                    return ExpenseListTile(
                      expense: expense,
                      onTap: () => onEditExpense(expense),
                      onEdit: () => onEditExpense(expense),
                      onDelete: () => _delete(context, ref, expense),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    if (!await confirmExpenseDelete(context, expense) || !context.mounted) {
      return;
    }
    try {
      await ref.read(expenseRepositoryProvider).delete(expense.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense deleted.')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this expense.')),
        );
      }
    }
  }
}

final class _HistoryFilters extends ConsumerWidget {
  const _HistoryFilters({required this.filter});

  final HistoryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyFilterProvider.notifier);
    final periods = ref.watch(visiblePeriodsProvider).valueOrNull ?? const [];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SearchField(
              key: const Key('history-search-field'),
              value: filter.query,
              hintText: 'Search amount, note, category or payer',
              onChanged: (value) =>
                  notifier.state = filter.copyWith(query: value),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DateRangeButton(
                    range: filter.range,
                    onPressed: () async {
                      final range = await pickExpenseDateRange(
                        context,
                        filter.range,
                      );
                      if (range != null) {
                        notifier.state = filter.copyWith(range: range);
                      }
                    },
                  ),
                ),
                if (filter.range != null)
                  IconButton(
                    key: const Key('history-clear-range'),
                    tooltip: 'All dates',
                    icon: const Icon(Icons.event_busy_outlined),
                    onPressed: () =>
                        notifier.state = filter.copyWith(clearRange: true),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              children: <Widget>[
                DropdownButtonFormField<String?>(
                  key: const Key('history-period-filter'),
                  initialValue: filter.periodId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Spending period',
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(child: Text('All periods')),
                    ...periods.map(
                      (period) => DropdownMenuItem<String?>(
                        value: period.id,
                        child: Text(_periodLabel(period)),
                      ),
                    ),
                  ],
                  onChanged: (value) => notifier.state = value == null
                      ? filter.copyWith(clearPeriod: true)
                      : filter.copyWith(periodId: value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<HouseholdMember?>(
                  key: const Key('history-payer-filter'),
                  initialValue: filter.payer,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payer',
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<HouseholdMember?>>[
                    const DropdownMenuItem<HouseholdMember?>(
                      child: Text('All payers'),
                    ),
                    ...HouseholdMember.values.map(
                      (member) => DropdownMenuItem<HouseholdMember?>(
                        value: member,
                        child: Text(member.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) => notifier.state = value == null
                      ? filter.copyWith(clearPayer: true)
                      : filter.copyWith(payer: value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ExpenseCategory?>(
                  key: const Key('history-category-filter'),
                  initialValue: filter.category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<ExpenseCategory?>>[
                    const DropdownMenuItem<ExpenseCategory?>(
                      child: Text('All categories'),
                    ),
                    ...ExpenseCategory.values.map(
                      (category) => DropdownMenuItem<ExpenseCategory?>(
                        value: category,
                        child: Text(category.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) => notifier.state = value == null
                      ? filter.copyWith(clearCategory: true)
                      : filter.copyWith(category: value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _periodLabel(SpendingPeriod period) => period.isOpen
    ? '${period.displayName} · open'
    : '${period.displayName} · closed ${dhakaDate(period.closedAt!)}';

final class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.manage_search_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No matching expenses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Try a different search, or clear the date, period, payer and '
              'category filters.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
