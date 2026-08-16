import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/local/database_mappers.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/data/repositories/period_repository.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/spending_period.dart';

void main() {
  late AppDatabase database;
  late DriftPeriodRepository repository;
  late DriftExpenseRepository expenses;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPeriodRepository(database);
    expenses = DriftExpenseRepository(database);
  });

  tearDown(() async {
    await expenses.close();
    await repository.close();
    await database.close();
  });

  Future<SpendingPeriod> seedPeriod({
    String id = '20000000-0000-4000-8000-000000000001',
    int sequenceNumber = 1,
    DateTime? closedAt,
    int version = 1,
  }) async {
    final period = SpendingPeriod(
      id: id,
      sequenceNumber: sequenceNumber,
      startedAt: DateTime.utc(2026, 8, 1),
      closedAt: closedAt,
      version: version,
      updatedAt: DateTime.utc(2026, 8, 1),
      syncState: LocalSyncState.synced,
    );
    await database
        .into(database.localPeriods)
        .insertOnConflictUpdate(periodCompanion(period));
    return period;
  }

  test('a device that has never synced has no period to spend against', () {
    expect(repository.readOpenPeriod(), completion(isNull));
    expect(
      repository.closeAndOpenNext(),
      throwsA(isA<NoOpenPeriodException>()),
    );
  });

  test('closing stamps the open period and opens the next one', () async {
    final current = await seedPeriod();

    final rollover = await repository.closeAndOpenNext();

    expect(rollover.closed.id, current.id);
    expect(rollover.closed.isOpen, isFalse);
    expect(rollover.closed.closedAt, isNotNull);
    expect(rollover.opened.isOpen, isTrue);
    expect(rollover.opened.sequenceNumber, 2);
    expect(rollover.opened.displayName, 'Period 2');
    expect((await repository.readOpenPeriod())!.id, rollover.opened.id);
    // The settled period stays readable in History.
    expect(await repository.readPeriods(), hasLength(2));
  });

  test('the close is queued ahead of the period that replaces it', () async {
    final current = await seedPeriod(version: 3);

    final rollover = await repository.closeAndOpenNext();

    final outbox = await database.select(database.outboxMutations).get();
    expect(outbox, hasLength(2));
    expect(
      outbox.map((row) => row.entityType),
      everyElement(SyncEntityType.period.storedName),
    );
    // Queued in this order so the server never sees two open periods at once.
    expect(outbox.first.entityId, rollover.closed.id);
    expect(outbox.first.action, 'UPDATE');
    expect(outbox.first.baseVersion, current.version);
    expect(outbox.last.entityId, rollover.opened.id);
    expect(outbox.last.action, 'CREATE');
    expect(outbox.last.baseVersion, 0);

    final closePayload =
        jsonDecode(outbox.first.payloadJson!) as Map<String, Object?>;
    expect(closePayload['sequenceNumber'], 1);
    expect(closePayload['closedAt'], isA<String>());
    final openPayload =
        jsonDecode(outbox.last.payloadJson!) as Map<String, Object?>;
    expect(openPayload['sequenceNumber'], 2);
    expect(openPayload['closedAt'], isNull);
  });

  test('the next sequence number follows the highest period seen', () async {
    await seedPeriod(closedAt: DateTime.utc(2026, 7, 1));
    await seedPeriod(
      id: '20000000-0000-4000-8000-000000000009',
      sequenceNumber: 9,
    );

    final rollover = await repository.closeAndOpenNext();

    expect(rollover.closed.sequenceNumber, 9);
    expect(rollover.opened.sequenceNumber, 10);
  });

  test('expenses with no period are filed into the one being closed', () async {
    // Recorded before the first bootstrap, so the device knew no period yet.
    final orphan = await expenses.create(
      ExpenseDraft(
        amountMinor: 80000,
        category: ExpenseCategory.groceries,
        payer: HouseholdMember.sumon,
        occurredAt: DateTime.utc(2026, 8, 13, 10),
      ),
    );
    expect(orphan.periodId, isNull);
    await seedPeriod();

    final rollover = await repository.closeAndOpenNext();

    expect(
      (await database.findExpenseRow(orphan.id))!.periodId,
      rollover.closed.id,
    );
    // The already-queued payload is untouched, so the wire behaviour and the
    // server's own choice of period both stand.
    final outbox = await database.select(database.outboxMutations).get();
    final payload =
        jsonDecode(outbox.first.payloadJson!) as Map<String, Object?>;
    expect(payload.containsKey('periodId'), isFalse);
  });

  test('closing announces both periods to the sync triggers', () async {
    await seedPeriod();
    final events = repository.localMutations.take(2).toList();

    final rollover = await repository.closeAndOpenNext();

    expect((await events).map((event) => event.entityId), <String>[
      rollover.closed.id,
      rollover.opened.id,
    ]);
    expect(
      (await events).map((event) => event.entityType),
      everyElement(SyncEntityType.period),
    );
  });
}
