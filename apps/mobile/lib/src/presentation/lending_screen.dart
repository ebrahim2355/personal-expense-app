import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expense.dart';
import '../domain/loan.dart';
import '../providers.dart';
import 'common_widgets.dart';
import 'presentation_providers.dart';

/// The lending ledger: hand-recorded loans with their own net total, kept apart
/// from shared expenses so neither figure moves the other.
final class LendingScreen extends ConsumerWidget {
  const LendingScreen({required this.onEditLoan, super.key});

  final ValueChanged<Loan> onEditLoan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(loanFilterProvider);
    final loans = ref.watch(visibleLoansProvider);

    return loans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Could not read the lending ledger.'),
        ),
      ),
      data: (allLoans) {
        // The net total covers the whole ledger, so a search narrows the list
        // without quietly changing the figure the members owe each other.
        final summary = summarizeLoans(allLoans);
        final visible = allLoans.where(filter.includes).toList(growable: false)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(manualSyncControllerProvider.notifier).run();
          },
          child: ListView(
            key: const PageStorageKey<String>('lending-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: <Widget>[
              _LoanNetCard(summary: summary),
              const SizedBox(height: 12),
              _LoanFilters(filter: filter),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                _EmptyLending(isFiltered: allLoans.isNotEmpty)
              else
                ...visible.map(
                  (loan) => LoanListTile(
                    loan: loan,
                    onTap: () => onEditLoan(loan),
                    onEdit: () => onEditLoan(loan),
                    onDelete: () => _delete(context, ref, loan),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Loan loan) async {
    if (!await confirmLoanDelete(context, loan) || !context.mounted) {
      return;
    }
    try {
      await ref.read(loanRepositoryProvider).delete(loan.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Loan entry deleted.')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this loan entry.')),
        );
      }
    }
  }
}

final class _LoanNetCard extends StatelessWidget {
  const _LoanNetCard({required this.summary});

  final LoanSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Outstanding loans',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                summary.netText,
                key: const Key('loan-net-text'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Recorded by hand and tracked on its own. Shared expenses settle '
              'separately on the dashboard.',
            ),
          ],
        ),
      ),
    );
  }
}

final class _LoanFilters extends ConsumerWidget {
  const _LoanFilters({required this.filter});

  final LoanFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(loanFilterProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SearchField(
          key: const Key('lending-search-field'),
          value: filter.query,
          hintText: 'Search amount, note or member',
          onChanged: (value) => notifier.state = filter.copyWith(query: value),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<HouseholdMember?>(
          key: const Key('lending-debtor-filter'),
          initialValue: filter.debtor,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Who owes',
            isDense: true,
          ),
          items: <DropdownMenuItem<HouseholdMember?>>[
            const DropdownMenuItem<HouseholdMember?>(child: Text('Either')),
            ...HouseholdMember.values.map(
              (member) => DropdownMenuItem<HouseholdMember?>(
                value: member,
                child: Text(member.displayName),
              ),
            ),
          ],
          onChanged: (value) => notifier.state = value == null
              ? filter.copyWith(clearDebtor: true)
              : filter.copyWith(debtor: value),
        ),
      ],
    );
  }
}

final class _EmptyLending extends StatelessWidget {
  const _EmptyLending({required this.isFiltered});

  /// True when entries exist but none match, so the copy points at the search
  /// rather than at an empty ledger.
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: <Widget>[
            Icon(
              isFiltered
                  ? Icons.manage_search_outlined
                  : Icons.swap_horiz_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              isFiltered ? 'No matching loans' : 'No loans recorded',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              isFiltered
                  ? 'Try a different search, or clear the “who owes” filter.'
                  : 'Tap Add loan to write one down, even while offline.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
