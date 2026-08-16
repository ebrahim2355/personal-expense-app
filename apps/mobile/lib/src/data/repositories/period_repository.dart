import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/expense.dart';
import '../../domain/spending_period.dart';
import '../local/app_database.dart';
import '../local/database_mappers.dart';
import '../remote/api_models.dart';
import 'local_mutations.dart';

final class PeriodNotFoundException implements Exception {
  const PeriodNotFoundException(this.id);

  final String id;
}

/// Thrown when a close is attempted with nothing open, which only happens if the
/// device has never bootstrapped.
final class NoOpenPeriodException implements Exception {
  const NoOpenPeriodException();
}

/// The pair a close produces: the period that was just settled and the one that
/// took its place.
final class PeriodRollover {
  const PeriodRollover({required this.closed, required this.opened});

  final SpendingPeriod closed;
  final SpendingPeriod opened;
}

abstract interface class PeriodRepository {
  Stream<List<SpendingPeriod>> watchPeriods();

  Future<List<SpendingPeriod>> readPeriods();

  Stream<SpendingPeriod?> watchOpenPeriod();

  Future<SpendingPeriod?> readOpenPeriod();

  /// Stamps the open period closed and opens the next one.
  Future<PeriodRollover> closeAndOpenNext();

  Stream<LocalMutationEvent> get localMutations;
}

final class DriftPeriodRepository implements PeriodRepository {
  DriftPeriodRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;
  final StreamController<LocalMutationEvent> _localMutations =
      StreamController<LocalMutationEvent>.broadcast();

  @override
  Stream<LocalMutationEvent> get localMutations => _localMutations.stream;

  @override
  Stream<List<SpendingPeriod>> watchPeriods() => _database
      .watchPeriodRows()
      .map((rows) => rows.map(periodFromRow).toList(growable: false));

  @override
  Future<List<SpendingPeriod>> readPeriods() async =>
      (await _database.readPeriodRows())
          .map(periodFromRow)
          .toList(growable: false);

  @override
  Stream<SpendingPeriod?> watchOpenPeriod() => _database
      .watchOpenPeriodRow()
      .map((row) => row == null ? null : periodFromRow(row));

  @override
  Future<SpendingPeriod?> readOpenPeriod() async {
    final row = await _database.readOpenPeriodRow();
    return row == null ? null : periodFromRow(row);
  }

  @override
  Future<PeriodRollover> closeAndOpenNext() async {
    final openRow = await _database.readOpenPeriodRow();
    if (openRow == null) {
      throw const NoOpenPeriodException();
    }
    final now = DateTime.now().toUtc();
    final current = periodFromRow(openRow);
    final closedDraft = current.closedAtDraft(now).normalized();
    final closed = SpendingPeriod(
      id: current.id,
      sequenceNumber: current.sequenceNumber,
      startedAt: current.startedAt,
      closedAt: closedDraft.closedAt,
      note: closedDraft.note,
      version: current.version,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    final highestSequence = await _database.readHighestPeriodSequenceNumber();
    final nextDraft = SpendingPeriodDraft(
      sequenceNumber: (highestSequence ?? current.sequenceNumber) + 1,
      startedAt: now,
    ).normalized();
    final opened = SpendingPeriod(
      id: _uuid.v4(),
      sequenceNumber: nextDraft.sequenceNumber,
      startedAt: nextDraft.startedAt,
      note: nextDraft.note,
      version: 0,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );

    await _database.transaction(() async {
      await (_database.update(_database.localPeriods)
            ..where((row) => row.id.equals(closed.id)))
          .write(periodCompanion(closed, localModifiedAt: now));
      await _enqueue(
        entityId: closed.id,
        operation: MutationOperation.update,
        baseVersion: current.version,
        payload: closedDraft.toWireJson(),
        now: now,
      );
      await _database
          .into(_database.localPeriods)
          .insert(periodCompanion(opened, localModifiedAt: now));
      // Queued after the close so the server, which applies a batch in array
      // order, never sees two open periods and never trips PERIOD_ALREADY_OPEN.
      await _enqueue(
        entityId: opened.id,
        operation: MutationOperation.create,
        baseVersion: 0,
        payload: nextDraft.toWireJson(),
        now: now,
      );
      // Expenses recorded before this device knew any period belong to the one
      // being closed: they were entered while it was open. Their already-queued
      // payloads are untouched, so the wire behaviour is unchanged, and the
      // server's snapshot still overwrites this guess on the next sync.
      await (_database.update(_database.localExpenses)
            ..where((row) => row.periodId.isNull()))
          .write(LocalExpensesCompanion(periodId: Value<String>(closed.id)));
    });

    _localMutations.add(LocalMutationEvent(SyncEntityType.period, closed.id));
    _localMutations.add(LocalMutationEvent(SyncEntityType.period, opened.id));
    return PeriodRollover(closed: closed, opened: opened);
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
            entityType: Value<String>(SyncEntityType.period.storedName),
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
