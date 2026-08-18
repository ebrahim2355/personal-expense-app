import '../data/remote/api_models.dart';
import '../domain/expense.dart';
import '../domain/money.dart';
import 'household_activity_notifier.dart';

/// What a notification says. Pure data, so the wording can be asserted without
/// a plugin or a platform channel.
final class ActivityNotificationText {
  const ActivityNotificationText({required this.title, this.body});

  final String title;

  /// The detail line, or null when the title already says everything.
  final String? body;
}

/// Renders one piece of household activity as notification text.
///
/// Every string the member reads comes from the same helpers the screens use —
/// [formatBdt], `displayName`, and `Loan.summaryText` — so a notification and
/// the row it points at never disagree about an amount or a name.
ActivityNotificationText describeActivity(HouseholdActivity activity) =>
    switch (activity.entityType) {
      SyncEntityType.expense => _describeExpense(
        activity,
        activity.snapshot.expense!,
      ),
      SyncEntityType.period => _describePeriod(
        activity,
        activity.snapshot.period!,
      ),
      SyncEntityType.loan => _describeLoan(activity, activity.snapshot.loan!),
    };

/// What the group summary says when one sync brought several changes.
final class ActivityBatchNotificationText {
  const ActivityBatchNotificationText({
    required this.title,
    required this.body,
    required this.lines,
  });

  final String title;

  /// The collapsed line, which is all the member sees until they expand.
  final String body;

  /// One line per change, in the order the changes were applied.
  final List<String> lines;
}

/// Renders the summary that sits above a batch of changes.
///
/// Only the count and the authors go in the collapsed line: a sync that brought
/// six entries should say so in one glance, and the per-change detail is one
/// expand away in [ActivityBatchNotificationText.lines].
ActivityBatchNotificationText describeActivityBatch(
  List<HouseholdActivity> activities,
) {
  // Insertion-ordered, so with two household members this reads "Sumon",
  // "Ebrahim", or "Sumon and Ebrahim" depending on who actually wrote.
  final actors = <String>{
    for (final activity in activities) activity.actor.displayName,
  };
  final count = activities.length;
  return ActivityBatchNotificationText(
    title: 'Household activity',
    body:
        '$count ${count == 1 ? 'change' : 'changes'} '
        'from ${actors.join(' and ')}',
    lines: activities
        .map((activity) {
          final text = describeActivity(activity);
          return text.body == null
              ? text.title
              : '${text.title} · ${text.body}';
        })
        .toList(growable: false),
  );
}

ActivityNotificationText _describeExpense(
  HouseholdActivity activity,
  ExpenseDto expense,
) {
  final verb = switch (activity.operation) {
    ChangeOperation.created => 'added',
    ChangeOperation.updated => 'edited',
    ChangeOperation.deleted => 'deleted',
  };
  return ActivityNotificationText(
    title: '${activity.actor.displayName} $verb an expense',
    body: _detailLine(<String?>[
      formatBdt(expense.amountMinor),
      expense.category.displayName,
      // Who recorded an expense is not always who paid for it, and the split
      // depends on the payer, so name the payer whenever the two differ.
      if (expense.payer != activity.actor)
        'paid by ${expense.payer.displayName}',
      expense.note,
    ]),
  );
}

ActivityNotificationText _describeLoan(
  HouseholdActivity activity,
  LoanDto loan,
) {
  final verb = switch (activity.operation) {
    ChangeOperation.created => 'added',
    ChangeOperation.updated => 'edited',
    ChangeOperation.deleted => 'deleted',
  };
  return ActivityNotificationText(
    title: '${activity.actor.displayName} $verb a loan entry',
    // The lending ledger already phrases a loan as "X owes Y ৳N". Reusing it
    // keeps the notification and the row identical.
    body: _detailLine(<String?>[loan.toDomain().summaryText, loan.note]),
  );
}

ActivityNotificationText _describePeriod(
  HouseholdActivity activity,
  PeriodDto period,
) {
  final name = period.toDomain().displayName;
  // A period is created open and closed by an update; it is never deleted, so
  // only these two shapes can reach a member.
  final title = switch (activity.operation) {
    ChangeOperation.created => '${activity.actor.displayName} opened $name',
    ChangeOperation.updated when period.closedAt != null =>
      '${activity.actor.displayName} closed $name',
    ChangeOperation.updated ||
    ChangeOperation.deleted => '${activity.actor.displayName} changed $name',
  };
  return ActivityNotificationText(
    title: title,
    body: _detailLine(<String?>[period.note]),
  );
}

/// Joins the parts that are actually present, dropping blanks so a missing note
/// never leaves a dangling separator. Returns null when nothing is left to say.
String? _detailLine(List<String?> parts) {
  final present = parts
      .map((part) => part?.trim() ?? '')
      .where((part) => part.isNotEmpty);
  return present.isEmpty ? null : present.join(' · ');
}
