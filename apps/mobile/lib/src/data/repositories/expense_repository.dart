import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/expense.dart';
import '../local/app_database.dart';
import '../local/database_mappers.dart';
import '../remote/api_models.dart';

final class ExpenseNotFoundException implements Exception {
  const ExpenseNotFoundException(this.id);

  final String id;
}

final class LocalMutationEvent {
  const LocalMutationEvent(this.expenseId);

  final String expenseId;
}

abstract interface class ExpenseRepository {
  Stream<List<Expense>> watchVisibleExpenses();

  Future<List<Expense>> readVisibleExpenses();

  Future<Expense> create(ExpenseDraft draft);

  Future<Expense> edit(String id, ExpenseDraft draft);

  Future<void> delete(String id);

  Stream<LocalMutationEvent> get localMutations;
}

final class DriftExpenseRepository implements ExpenseRepository {
  DriftExpenseRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;
  final StreamController<LocalMutationEvent> _localMutations =
      StreamController<LocalMutationEvent>.broadcast();

  @override
  Stream<LocalMutationEvent> get localMutations => _localMutations.stream;

  @override
  Stream<List<Expense>> watchVisibleExpenses() => _database
      .watchVisibleExpenseRows()
      .map((rows) => rows.map(expenseFromRow).toList(growable: false));

  @override
  Future<List<Expense>> readVisibleExpenses() async =>
      (await _database.readVisibleExpenseRows())
          .map(expenseFromRow)
          .toList(growable: false);

  @override
  Future<Expense> create(ExpenseDraft draft) async {
    final normalized = draft.normalized();
    final now = DateTime.now().toUtc();
    final expense = Expense(
      id: _uuid.v4(),
      amountMinor: normalized.amountMinor,
      category: normalized.category,
      payer: normalized.payer,
      occurredAt: normalized.occurredAt,
      note: normalized.note,
      version: 0,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.localExpenses)
          .insert(expenseCompanion(expense, localModifiedAt: now));
      await _enqueue(
        entityId: expense.id,
        operation: MutationOperation.create,
        baseVersion: 0,
        payload: normalized.toWireJson(),
        now: now,
      );
    });
    _localMutations.add(LocalMutationEvent(expense.id));
    return expense;
  }

  @override
  Future<Expense> edit(String id, ExpenseDraft draft) async {
    final normalized = draft.normalized();
    final currentRow = await _database.findExpenseRow(id);
    if (currentRow == null || currentRow.deletedAt != null) {
      throw ExpenseNotFoundException(id);
    }
    final now = DateTime.now().toUtc();
    final current = expenseFromRow(currentRow);
    final updated = Expense(
      id: current.id,
      amountMinor: normalized.amountMinor,
      category: normalized.category,
      payer: normalized.payer,
      occurredAt: normalized.occurredAt,
      note: normalized.note,
      version: current.version,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    await _database.transaction(() async {
      await (_database.update(_database.localExpenses)
            ..where((row) => row.id.equals(id)))
          .write(expenseCompanion(updated, localModifiedAt: now));
      await _enqueue(
        entityId: id,
        operation: MutationOperation.update,
        baseVersion: current.version,
        payload: normalized.toWireJson(),
        now: now,
      );
    });
    _localMutations.add(LocalMutationEvent(id));
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    final currentRow = await _database.findExpenseRow(id);
    if (currentRow == null || currentRow.deletedAt != null) {
      throw ExpenseNotFoundException(id);
    }
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await (_database.update(
        _database.localExpenses,
      )..where((row) => row.id.equals(id))).write(
        LocalExpensesCompanion(
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
    _localMutations.add(LocalMutationEvent(id));
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

enum OutboxStatus { pending, inFlight, needsAttention }

extension OutboxStatusStorage on OutboxStatus {
  String get storedName => switch (this) {
    OutboxStatus.pending => 'PENDING',
    OutboxStatus.inFlight => 'IN_FLIGHT',
    OutboxStatus.needsAttention => 'NEEDS_ATTENTION',
  };

  static OutboxStatus parse(String value) => switch (value) {
    'PENDING' => OutboxStatus.pending,
    'IN_FLIGHT' => OutboxStatus.inFlight,
    'NEEDS_ATTENTION' => OutboxStatus.needsAttention,
    _ => throw FormatException('Unknown outbox status: $value'),
  };
}
