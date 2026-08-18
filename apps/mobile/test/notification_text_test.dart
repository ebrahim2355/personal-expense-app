import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/notifications/activity_notification_text.dart';
import 'package:houseexpenses/src/notifications/household_activity_notifier.dart';

import 'support/fakes.dart';

/// Sumon is always the author here, so a device running these expectations is
/// Ebrahim's: the wording only ever describes the *other* member's activity.
HouseholdActivity activity(
  EntitySnapshotDto snapshot, {
  ChangeOperation operation = ChangeOperation.created,
  HouseholdMember actor = HouseholdMember.sumon,
}) => HouseholdActivity(actor: actor, operation: operation, snapshot: snapshot);

void main() {
  group('expenses', () {
    test('names the amount, the category and the note', () {
      final text = describeActivity(
        activity(
          expenseSnapshot(
            remoteExpense(
              id: '00000000-0000-4000-8000-000000000001',
              amountMinor: 45000,
              category: ExpenseCategory.groceries,
              note: 'Rice',
            ),
          ),
        ),
      );

      expect(text.title, 'Sumon added an expense');
      expect(text.body, '৳450 · Groceries · Rice');
    });

    test('names the payer only when it is not the author', () {
      final byOther = describeActivity(
        activity(
          expenseSnapshot(
            remoteExpense(
              id: '00000000-0000-4000-8000-000000000002',
              amountMinor: 120000,
              category: ExpenseCategory.utilities,
              payer: HouseholdMember.ebrahim,
            ),
          ),
        ),
      );

      // Who recorded an expense is not always who paid for it, and the split
      // follows the payer, so a mismatch has to be visible.
      expect(byOther.body, '৳1,200 · Utilities · paid by Ebrahim');
    });

    test('drops the detail parts that are absent', () {
      final text = describeActivity(
        activity(
          expenseSnapshot(
            remoteExpense(
              id: '00000000-0000-4000-8000-000000000003',
              amountMinor: 30000,
              category: ExpenseCategory.transport,
            ),
          ),
        ),
      );

      // No note and no payer clause, and no dangling separator either.
      expect(text.body, '৳300 · Transport');
    });

    test('ignores a note that is only whitespace', () {
      final text = describeActivity(
        activity(
          expenseSnapshot(
            remoteExpense(
              id: '00000000-0000-4000-8000-000000000004',
              amountMinor: 30000,
              category: ExpenseCategory.other,
              note: '   ',
            ),
          ),
        ),
      );

      expect(text.body, '৳300 · Other');
    });

    test('rounds nothing away from an odd taka amount', () {
      final text = describeActivity(
        activity(
          expenseSnapshot(
            remoteExpense(
              id: '00000000-0000-4000-8000-000000000005',
              amountMinor: 100100,
              category: ExpenseCategory.medicine,
            ),
          ),
        ),
      );

      expect(text.body, '৳1,001 · Medicine');
    });

    test('says edited and deleted for the other two operations', () {
      final snapshot = expenseSnapshot(
        remoteExpense(
          id: '00000000-0000-4000-8000-000000000006',
          amountMinor: 45000,
        ),
      );

      expect(
        describeActivity(activity(snapshot, operation: ChangeOperation.updated))
            .title,
        'Sumon edited an expense',
      );
      expect(
        describeActivity(activity(snapshot, operation: ChangeOperation.deleted))
            .title,
        'Sumon deleted an expense',
      );
    });
  });

  group('loans', () {
    test('phrases the entry the way the lending ledger does', () {
      final text = describeActivity(
        activity(
          loanSnapshot(
            remoteLoan(
              id: '30000000-0000-4000-8000-000000000001',
              amountMinor: 100000,
              debtor: HouseholdMember.ebrahim,
              note: 'Rickshaw fare',
            ),
          ),
        ),
      );

      expect(text.title, 'Sumon added a loan entry');
      expect(text.body, 'Ebrahim owes Sumon ৳1,000 · Rickshaw fare');
    });

    test('keeps the summary when there is no note', () {
      final text = describeActivity(
        activity(
          loanSnapshot(
            remoteLoan(
              id: '30000000-0000-4000-8000-000000000002',
              amountMinor: 50000,
              debtor: HouseholdMember.sumon,
            ),
          ),
          operation: ChangeOperation.deleted,
        ),
      );

      expect(text.title, 'Sumon deleted a loan entry');
      expect(text.body, 'Sumon owes Ebrahim ৳500');
    });
  });

  group('spending periods', () {
    test('reads a created period as opened', () {
      final text = describeActivity(
        activity(
          periodSnapshot(
            remotePeriod(
              id: '20000000-0000-4000-8000-000000000001',
              sequenceNumber: 4,
            ),
          ),
        ),
      );

      expect(text.title, 'Sumon opened Period 4');
      expect(text.body, isNull);
    });

    test('reads an update that settles a period as closed', () {
      final text = describeActivity(
        activity(
          periodSnapshot(
            remotePeriod(
              id: '20000000-0000-4000-8000-000000000002',
              sequenceNumber: 3,
              version: 2,
              closedAt: DateTime.utc(2026, 8, 14, 10),
              note: 'Rent settled',
            ),
          ),
          operation: ChangeOperation.updated,
        ),
      );

      expect(text.title, 'Sumon closed Period 3');
      expect(text.body, 'Rent settled');
    });

    test('falls back to a neutral verb for an update that is not a close', () {
      final text = describeActivity(
        activity(
          periodSnapshot(
            remotePeriod(
              id: '20000000-0000-4000-8000-000000000003',
              sequenceNumber: 5,
              version: 2,
            ),
          ),
          operation: ChangeOperation.updated,
        ),
      );

      // A period is never deleted and never reopened, so this only covers an
      // edit to a still-open period — a note, say.
      expect(text.title, 'Sumon changed Period 5');
    });
  });

  group('batch summary', () {
    test('counts the changes and names the author', () {
      final batch = describeActivityBatch(<HouseholdActivity>[
        activity(
          expenseSnapshot(
            remoteExpense(
              id: '00000000-0000-4000-8000-000000000010',
              amountMinor: 45000,
              note: 'Rice',
            ),
          ),
        ),
        activity(
          loanSnapshot(
            remoteLoan(
              id: '30000000-0000-4000-8000-000000000010',
              amountMinor: 100000,
            ),
          ),
        ),
      ]);

      expect(batch.title, 'Household activity');
      expect(batch.body, '2 changes from Sumon');
      expect(batch.lines, <String>[
        'Sumon added an expense · ৳450 · Groceries · Rice',
        'Sumon added a loan entry · Ebrahim owes Sumon ৳1,000',
      ]);
    });

    test('keeps a single change singular', () {
      final batch = describeActivityBatch(<HouseholdActivity>[
        activity(
          periodSnapshot(
            remotePeriod(
              id: '20000000-0000-4000-8000-000000000010',
              sequenceNumber: 2,
            ),
          ),
        ),
      ]);

      expect(batch.body, '1 change from Sumon');
      // A period line has no detail half, so it must not gain a separator.
      expect(batch.lines, <String>['Sumon opened Period 2']);
    });
  });
}
