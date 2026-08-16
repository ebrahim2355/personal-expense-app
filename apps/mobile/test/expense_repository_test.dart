import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/local/database_mappers.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/spending_period.dart';

void main() {
  late AppDatabase database;
  late DriftExpenseRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftExpenseRepository(database);
  });

  tearDown(() async {
    await repository.close();
    await database.close();
  });

  Future<SpendingPeriod> seedPeriod({
    String id = '20000000-0000-4000-8000-000000000001',
    int sequenceNumber = 1,
    DateTime? closedAt,
  }) async {
    final period = SpendingPeriod(
      id: id,
      sequenceNumber: sequenceNumber,
      startedAt: DateTime.utc(2026, 8, 1),
      closedAt: closedAt,
      version: 1,
      updatedAt: DateTime.utc(2026, 8, 1),
      syncState: LocalSyncState.synced,
    );
    await database
        .into(database.localPeriods)
        .insertOnConflictUpdate(periodCompanion(period));
    return period;
  }

  test(
    'offline create is returned immediately and enqueued atomically',
    () async {
      final expense = await repository.create(
        ExpenseDraft(
          amountMinor: 80000,
          category: ExpenseCategory.groceries,
          payer: HouseholdMember.sumon,
          occurredAt: DateTime.utc(2026, 8, 13, 10),
          note: '  Rice  ',
        ),
      );

      final visible = await repository.readVisibleExpenses();
      final outbox = await database.select(database.outboxMutations).get();

      expect(visible, hasLength(1));
      expect(visible.single.id, expense.id);
      expect(visible.single.amountMinor, 80000);
      expect(visible.single.note, 'Rice');
      expect(visible.single.syncState, LocalSyncState.pending);
      expect(outbox, hasLength(1));
      expect(outbox.single.entityId, expense.id);
      expect(outbox.single.entityType, SyncEntityType.expense.storedName);
      expect(outbox.single.action, 'CREATE');
      expect(outbox.single.baseVersion, 0);
    },
  );

  test('soft-deleting locally hides the row and queues a delete', () async {
    final expense = await repository.create(
      ExpenseDraft(
        amountMinor: 100,
        category: ExpenseCategory.other,
        payer: HouseholdMember.ebrahim,
        occurredAt: DateTime.utc(2026, 8, 13),
      ),
    );

    await repository.delete(expense.id);

    expect(await repository.readVisibleExpenses(), isEmpty);
    final stored = await database.findExpenseRow(expense.id);
    expect(stored!.deletedAt, isNotNull);
    final outbox = await database.select(database.outboxMutations).get();
    expect(outbox, hasLength(2));
    expect(outbox.last.action, 'DELETE');
    expect(outbox.last.entityType, SyncEntityType.expense.storedName);
  });

  test('a create is filed into the period that is open', () async {
    final period = await seedPeriod();

    final expense = await repository.create(
      ExpenseDraft(
        amountMinor: 120000,
        category: ExpenseCategory.utilities,
        payer: HouseholdMember.sumon,
        occurredAt: DateTime.utc(2026, 8, 13, 10),
      ),
    );

    expect(expense.periodId, period.id);
    final outbox = await database.select(database.outboxMutations).get();
    final payload =
        jsonDecode(outbox.single.payloadJson!) as Map<String, Object?>;
    expect(payload['periodId'], period.id);
  });

  test('without a period the payload lets the server choose', () async {
    await repository.create(
      ExpenseDraft(
        amountMinor: 40000,
        category: ExpenseCategory.transport,
        payer: HouseholdMember.sumon,
        occurredAt: DateTime.utc(2026, 8, 13, 10),
      ),
    );

    final outbox = await database.select(database.outboxMutations).get();
    final payload =
        jsonDecode(outbox.single.payloadJson!) as Map<String, Object?>;
    // Absent rather than null: the contract reads an omitted periodId as
    // "file this into whichever period is open".
    expect(payload.containsKey('periodId'), isFalse);
  });

  test('an edit never moves an expense into the newer period', () async {
    final first = await seedPeriod();
    final expense = await repository.create(
      ExpenseDraft(
        amountMinor: 50000,
        category: ExpenseCategory.household,
        payer: HouseholdMember.sumon,
        occurredAt: DateTime.utc(2026, 8, 13, 10),
      ),
    );
    // The household settles up, so a later period takes over.
    await seedPeriod(closedAt: DateTime.utc(2026, 8, 14));
    await seedPeriod(
      id: '20000000-0000-4000-8000-000000000002',
      sequenceNumber: 2,
    );

    final updated = await repository.edit(
      expense.id,
      expense.draft.withPeriodId(null),
    );

    expect(updated.periodId, first.id);
  });

  test('a sub-taka amount never reaches the outbox', () async {
    expect(
      () => repository.create(
        ExpenseDraft(
          amountMinor: 12345,
          category: ExpenseCategory.groceries,
          payer: HouseholdMember.sumon,
          occurredAt: DateTime.utc(2026, 8, 13, 10),
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await database.select(database.outboxMutations).get(), isEmpty);
  });
}
