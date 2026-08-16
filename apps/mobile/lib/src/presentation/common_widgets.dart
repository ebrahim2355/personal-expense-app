import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_coordinator.dart';
import '../domain/dhaka_time.dart';
import '../domain/expense.dart';
import '../domain/loan.dart';
import '../domain/money.dart';
import '../domain/spending_period.dart';
import 'presentation_providers.dart';

/// A date in the household's own timezone, which is the only one members think
/// in even though every instant is stored as UTC.
String dhakaDate(DateTime instant) =>
    DhakaTime.initialize().formatDate(instant);

Future<ExpenseDateRange?> pickExpenseDateRange(
  BuildContext context,
  ExpenseDateRange? current,
) async {
  final initial = current;
  final result = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100, 12, 31),
    initialDateRange: initial == null
        ? null
        : DateTimeRange(
            start: DateTime(
              initial.startDate.year,
              initial.startDate.month,
              initial.startDate.day,
            ),
            end: DateTime(
              initial.endDateInclusive.year,
              initial.endDateInclusive.month,
              initial.endDateInclusive.day,
            ),
          ),
    helpText: 'Select expense dates',
  );
  if (result == null) {
    return null;
  }
  return DhakaTime.initialize().range(
    CalendarDate(result.start.year, result.start.month, result.start.day),
    CalendarDate(result.end.year, result.end.month, result.end.day),
  );
}

final class DateRangeButton extends StatelessWidget {
  const DateRangeButton({
    required this.range,
    required this.onPressed,
    super.key,
  });

  /// Null renders the button as an invitation rather than a selection.
  final ExpenseDateRange? range;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final range = this.range;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(
        range == null ? 'All dates' : DhakaTime.initialize().formatRange(range),
      ),
    );
  }
}

final class SyncStatusCard extends ConsumerWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unresolvedMutationCountProvider).valueOrNull ?? 0;
    final lastSync = ref.watch(lastSuccessfulSyncProvider).valueOrNull;
    final manual = ref.watch(manualSyncControllerProvider);
    final report = manual.lastReport;

    final (icon, title, detail, color) = switch (report?.outcome) {
      SyncOutcome.offline => (
        Icons.cloud_off_outlined,
        'Offline',
        count == 0
            ? 'Local data is available. We’ll try again automatically.'
            : '$count local ${count == 1 ? 'change is' : 'changes are'} safe and waiting to sync.',
        Theme.of(context).colorScheme.tertiary,
      ),
      SyncOutcome.authenticationRequired => (
        Icons.lock_clock_outlined,
        'Sign-in required',
        'Your local expenses are still on this device.',
        Theme.of(context).colorScheme.error,
      ),
      SyncOutcome.failed => (
        Icons.sync_problem_outlined,
        'Sync needs attention',
        'Your local data is safe. Try again in a moment.',
        Theme.of(context).colorScheme.error,
      ),
      _ when manual.isRunning => (
        Icons.sync,
        'Syncing',
        'Sending local changes and checking for updates…',
        Theme.of(context).colorScheme.primary,
      ),
      _ when count > 0 => (
        Icons.cloud_upload_outlined,
        '$count ${count == 1 ? 'change' : 'changes'} waiting',
        'You can keep using the app while we sync.',
        Theme.of(context).colorScheme.tertiary,
      ),
      _ => (
        Icons.cloud_done_outlined,
        'Up to date',
        lastSync == null
            ? 'No successful sync on this device yet.'
            : 'Last synced ${DhakaTime.initialize().formatDateTime(lastSync)}',
        Theme.of(context).colorScheme.primary,
      ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              key: const Key('manual-sync-button'),
              tooltip: 'Sync now',
              onPressed: manual.isRunning
                  ? null
                  : () => ref.read(manualSyncControllerProvider.notifier).run(),
              icon: manual.isRunning
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

final class ExpenseListTile extends StatelessWidget {
  const ExpenseListTile({
    required this.expense,
    this.onTap,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final Expense expense;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final stateLabel = switch (expense.syncState) {
      LocalSyncState.synced => null,
      LocalSyncState.pending => 'Waiting to sync',
      LocalSyncState.needsAttention => 'Sync issue',
    };
    final stateIcon = switch (expense.syncState) {
      LocalSyncState.synced => null,
      LocalSyncState.pending => Icons.cloud_upload_outlined,
      LocalSyncState.needsAttention => Icons.sync_problem_outlined,
    };
    final subtitleParts = <String>[
      '${expense.payer.displayName} paid',
      DhakaTime.initialize().formatDateTime(expense.occurredAt),
      if (expense.note != null) expense.note!,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: Key('expense-${expense.id}'),
        onTap: onTap,
        minVerticalPadding: 12,
        leading: CircleAvatar(
          child: Icon(_categoryIcon(expense.category), size: 20),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                expense.category.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatBdt(expense.amountMinor),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                subtitleParts.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (stateLabel != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Icon(stateIcon, size: 15),
                    const SizedBox(width: 4),
                    Text(stateLabel),
                  ],
                ),
              ],
            ],
          ),
        ),
        trailing: onEdit == null && onDelete == null
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Expense actions',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit?.call();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  if (onEdit != null)
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

IconData _categoryIcon(ExpenseCategory category) => switch (category) {
  ExpenseCategory.groceries => Icons.shopping_basket_outlined,
  ExpenseCategory.utilities => Icons.bolt_outlined,
  ExpenseCategory.transport => Icons.directions_bus_outlined,
  ExpenseCategory.household => Icons.home_outlined,
  ExpenseCategory.medicine => Icons.medical_services_outlined,
  ExpenseCategory.other => Icons.receipt_long_outlined,
};

Future<bool> confirmExpenseDelete(BuildContext context, Expense expense) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete expense?'),
          content: Text(
            '${expense.category.displayName} · ${formatBdt(expense.amountMinor)}\n'
            'This will disappear now and sync as a deletion later.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-delete-button'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Closing wipes the dashboard clean, so the members see the figure they are
/// agreeing on before it moves into history.
Future<bool> confirmPeriodClose(
  BuildContext context, {
  required SpendingPeriod period,
  required ExpenseSummary summary,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('close-period-dialog'),
          title: Text('Close ${period.displayName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                summary.settlementText,
                key: const Key('close-period-settlement'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('Total spent: ${formatBdt(summary.totalMinor)}'),
              const SizedBox(height: 12),
              const Text(
                'The dashboard starts empty in a new period. This one stays '
                'readable in History.',
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-close-period-button'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close period'),
            ),
          ],
        ),
      ) ??
      false;
}

final class LoanListTile extends StatelessWidget {
  const LoanListTile({
    required this.loan,
    this.onTap,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final Loan loan;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final stateLabel = switch (loan.syncState) {
      LocalSyncState.synced => null,
      LocalSyncState.pending => 'Waiting to sync',
      LocalSyncState.needsAttention => 'Sync issue',
    };
    final subtitleParts = <String>[
      DhakaTime.initialize().formatDateTime(loan.occurredAt),
      if (loan.note != null) loan.note!,
      ?stateLabel,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: Key('loan-${loan.id}'),
        onTap: onTap,
        minVerticalPadding: 12,
        leading: const CircleAvatar(
          child: Icon(Icons.swap_horiz_outlined, size: 20),
        ),
        title: Text(
          loan.summaryText,
          maxLines: 2,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitleParts.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: onEdit == null && onDelete == null
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Loan actions',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit?.call();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  if (onEdit != null)
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<bool> confirmLoanDelete(BuildContext context, Loan loan) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete loan entry?'),
          content: Text(
            '${loan.summaryText}\n'
            'This will disappear now and sync as a deletion later.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-delete-loan-button'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

/// One search box, shared by the expense history and the lending ledger.
final class SearchField extends StatefulWidget {
  const SearchField({
    required this.value,
    required this.hintText,
    required this.onChanged,
    super.key,
  });

  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

final class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        hintText: widget.hintText,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value);
      },
    );
  }
}
