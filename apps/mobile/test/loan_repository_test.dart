import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/local/database_mappers.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/repositories/loan_repository.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/loan.dart';

void main() {
  late AppDatabase database;
  late DriftLoanRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLoanRepository(database);
  });

  tearDown(() async {
    await repository.close();
    await database.close();
  });

  test('a hand-recorded loan is stamped, stored and enqueued', () async {
    final before = DateTime.now().toUtc();
    final loan = await repository.create(
      const LoanDraft(
        debtor: HouseholdMember.ebrahim,
        amountMinor: 50000,
        note: '  Rickshaw fare  ',
      ),
    );

    expect(loan.amountMinor, 50000);
    expect(loan.note, 'Rickshaw fare');
    expect(loan.creditor, HouseholdMember.sumon);
    expect(loan.summaryText, 'Ebrahim owes Sumon ৳500');
    expect(loan.syncState, LocalSyncState.pending);
    // The timestamp is the one field the form never asks for.
    expect(loan.occurredAt.isBefore(before), isFalse);
    expect(loan.occurredAt.isUtc, isTrue);

    expect((await repository.readVisibleLoans()).single.id, loan.id);
    final outbox = await database.select(database.outboxMutations).get();
    expect(outbox.single.entityId, loan.id);
    expect(outbox.single.entityType, SyncEntityType.loan.storedName);
    expect(outbox.single.action, 'CREATE');
    expect(outbox.single.baseVersion, 0);
    final payload =
        jsonDecode(outbox.single.payloadJson!) as Map<String, Object?>;
    expect(payload['debtor'], 'EBRAHIM');
    expect(payload['amountMinor'], 50000);
    expect(payload['occurredAt'], loan.occurredAt.toIso8601String());
  });

  test('an edit rewrites the entry but keeps the original stamp', () async {
    final loan = await repository.create(
      const LoanDraft(debtor: HouseholdMember.ebrahim, amountMinor: 50000),
    );

    final updated = await repository.edit(
      loan.id,
      const LoanDraft(
        debtor: HouseholdMember.sumon,
        amountMinor: 30000,
        note: 'Corrected',
      ),
    );

    expect(updated.debtor, HouseholdMember.sumon);
    expect(updated.amountMinor, 30000);
    expect(updated.note, 'Corrected');
    expect(updated.occurredAt, wholeSeconds(loan.occurredAt));
    final outbox = await database.select(database.outboxMutations).get();
    expect(outbox, hasLength(2));
    expect(outbox.last.action, 'UPDATE');
    final payload =
        jsonDecode(outbox.last.payloadJson!) as Map<String, Object?>;
    expect(
      payload['occurredAt'],
      wholeSeconds(loan.occurredAt).toIso8601String(),
    );
  });

  test('deleting hides the entry, keeps the row and queues a delete', () async {
    final loan = await repository.create(
      const LoanDraft(debtor: HouseholdMember.sumon, amountMinor: 20000),
    );

    await repository.delete(loan.id);

    expect(await repository.readVisibleLoans(), isEmpty);
    final stored = await database.findLoanRow(loan.id);
    expect(stored!.deletedAt, isNotNull);
    final outbox = await database.select(database.outboxMutations).get();
    expect(outbox, hasLength(2));
    expect(outbox.last.action, 'DELETE');
    expect(outbox.last.payloadJson, isNull);
    expect(outbox.last.baseVersion, 0);
  });

  test('editing or deleting an entry that is gone is refused', () async {
    final loan = await repository.create(
      const LoanDraft(debtor: HouseholdMember.sumon, amountMinor: 20000),
    );
    await repository.delete(loan.id);

    expect(
      () => repository.edit(
        loan.id,
        const LoanDraft(debtor: HouseholdMember.sumon, amountMinor: 30000),
      ),
      throwsA(isA<LoanNotFoundException>()),
    );
    expect(
      () => repository.delete(loan.id),
      throwsA(isA<LoanNotFoundException>()),
    );
    expect(
      () => repository.delete('20000000-0000-4000-8000-00000000ffff'),
      throwsA(isA<LoanNotFoundException>()),
    );
  });

  test('a sub-taka loan never reaches the outbox', () async {
    expect(
      () => repository.create(
        const LoanDraft(debtor: HouseholdMember.sumon, amountMinor: 50050),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await database.select(database.outboxMutations).get(), isEmpty);
  });

  test('the newest entry leads the ledger', () async {
    const olderId = '30000000-0000-4000-8000-000000000001';
    await database
        .into(database.localLoans)
        .insertOnConflictUpdate(
          loanCompanion(
            Loan(
              id: olderId,
              debtor: HouseholdMember.sumon,
              amountMinor: 10000,
              occurredAt: DateTime.utc(2026, 8, 1, 9),
              version: 1,
              updatedAt: DateTime.utc(2026, 8, 1, 9),
              syncState: LocalSyncState.synced,
            ),
          ),
        );

    final newer = await repository.create(
      const LoanDraft(debtor: HouseholdMember.ebrahim, amountMinor: 20000),
    );

    final visible = await repository.readVisibleLoans();

    expect(visible.map((loan) => loan.id), <String>[newer.id, olderId]);
  });

  test('a write announces itself to the sync triggers', () async {
    final events = repository.localMutations.take(1).toList();

    final loan = await repository.create(
      const LoanDraft(debtor: HouseholdMember.sumon, amountMinor: 20000),
    );

    final event = (await events).single;
    expect(event.entityType, SyncEntityType.loan);
    expect(event.entityId, loan.id);
  });
}

/// The local datetime columns hold whole seconds, so a stamp that survives a
/// round trip through the database comes back without its microseconds. An edit
/// reads the stored stamp, which is why it is compared this way.
DateTime wholeSeconds(DateTime instant) => DateTime.fromMillisecondsSinceEpoch(
  instant.millisecondsSinceEpoch ~/ 1000 * 1000,
  isUtc: true,
);
