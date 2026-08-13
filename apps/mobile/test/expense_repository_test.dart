import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/domain/expense.dart';

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

  test(
    'offline create is returned immediately and enqueued atomically',
    () async {
      final expense = await repository.create(
        ExpenseDraft(
          amountMinor: 12345,
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
      expect(visible.single.amountMinor, 12345);
      expect(visible.single.note, 'Rice');
      expect(visible.single.syncState, LocalSyncState.pending);
      expect(outbox, hasLength(1));
      expect(outbox.single.entityId, expense.id);
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
    expect(await database.select(database.outboxMutations).get(), hasLength(2));
  });
}
