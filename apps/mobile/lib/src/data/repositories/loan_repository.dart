import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/expense.dart';
import '../../domain/loan.dart';
import '../local/app_database.dart';
import '../local/database_mappers.dart';
import '../remote/api_models.dart';
import 'local_mutations.dart';

final class LoanNotFoundException implements Exception {
  const LoanNotFoundException(this.id);

  final String id;
}

abstract interface class LoanRepository {
  Stream<List<Loan>> watchVisibleLoans();

  Future<List<Loan>> readVisibleLoans();

  Future<Loan> create(LoanDraft draft);

  Future<Loan> edit(String id, LoanDraft draft);

  Future<void> delete(String id);

  Stream<LocalMutationEvent> get localMutations;
}

final class DriftLoanRepository implements LoanRepository {
  DriftLoanRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;
  final StreamController<LocalMutationEvent> _localMutations =
      StreamController<LocalMutationEvent>.broadcast();

  @override
  Stream<LocalMutationEvent> get localMutations => _localMutations.stream;

  @override
  Stream<List<Loan>> watchVisibleLoans() => _database
      .watchVisibleLoanRows()
      .map((rows) => rows.map(loanFromRow).toList(growable: false));

  @override
  Future<List<Loan>> readVisibleLoans() async =>
      (await _database.readVisibleLoanRows())
          .map(loanFromRow)
          .toList(growable: false);

  @override
  Future<Loan> create(LoanDraft draft) async {
    final normalized = draft.normalized();
    // The only automatic field on the form: a loan is stamped when it is
    // recorded, and never asks the member for a date.
    final now = DateTime.now().toUtc();
    final loan = Loan(
      id: _uuid.v4(),
      debtor: normalized.debtor,
      amountMinor: normalized.amountMinor,
      occurredAt: now,
      note: normalized.note,
      version: 0,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.localLoans)
          .insert(loanCompanion(loan, localModifiedAt: now));
      await _enqueue(
        entityId: loan.id,
        operation: MutationOperation.create,
        baseVersion: 0,
        payload: normalized.toWireJson(occurredAt: now),
        now: now,
      );
    });
    _localMutations.add(LocalMutationEvent(SyncEntityType.loan, loan.id));
    return loan;
  }

  @override
  Future<Loan> edit(String id, LoanDraft draft) async {
    final currentRow = await _database.findLoanRow(id);
    if (currentRow == null || currentRow.deletedAt != null) {
      throw LoanNotFoundException(id);
    }
    final normalized = draft.normalized();
    final now = DateTime.now().toUtc();
    final current = loanFromRow(currentRow);
    // An edit keeps the original stamp: the entry still records when the money
    // changed hands, not when the wording was corrected.
    final updated = Loan(
      id: current.id,
      debtor: normalized.debtor,
      amountMinor: normalized.amountMinor,
      occurredAt: current.occurredAt,
      note: normalized.note,
      version: current.version,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    await _database.transaction(() async {
      await (_database.update(_database.localLoans)
            ..where((row) => row.id.equals(id)))
          .write(loanCompanion(updated, localModifiedAt: now));
      await _enqueue(
        entityId: id,
        operation: MutationOperation.update,
        baseVersion: current.version,
        payload: normalized.toWireJson(occurredAt: current.occurredAt),
        now: now,
      );
    });
    _localMutations.add(LocalMutationEvent(SyncEntityType.loan, id));
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    final currentRow = await _database.findLoanRow(id);
    if (currentRow == null || currentRow.deletedAt != null) {
      throw LoanNotFoundException(id);
    }
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await (_database.update(
        _database.localLoans,
      )..where((row) => row.id.equals(id))).write(
        LocalLoansCompanion(
          deletedAt: Value<DateTime>(now),
          updatedAt: Value<DateTime>(now),
          localModifiedAt: Value<DateTime>(now),
          syncState: Value<String>(LocalSyncState.pending.storedName),
        ),
      );
      await _enqueue(
        entityId: id,
        operation: MutationOperation.delete,
        baseVersion: currentRow.version,
        payload: null,
        now: now,
      );
    });
    _localMutations.add(LocalMutationEvent(SyncEntityType.loan, id));
  }

  Future<void> _enqueue({
    required String entityId,
    required MutationOperation operation,
    required int baseVersion,
    required Map<String, Object?>? payload,
    required DateTime now,
  }) {
    return _database
        .into(_database.outboxMutations)
        .insert(
          OutboxMutationsCompanion.insert(
            mutationId: _uuid.v4(),
            entityId: entityId,
            entityType: Value<String>(SyncEntityType.loan.storedName),
            action: operation.storedName,
            baseVersion: baseVersion,
            payloadJson: Value<String?>(
              payload == null ? null : jsonEncode(payload),
            ),
            createdAt: now,
            status: OutboxStatus.pending.storedName,
          ),
        );
  }

  Future<void> close() => _localMutations.close();
}
