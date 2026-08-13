import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/database_mappers.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_models.dart';
import '../data/remote/http_transport.dart';
import '../data/repositories/expense_repository.dart';
import '../domain/expense.dart';

enum SyncOutcome { completed, offline, authenticationRequired, failed }

final class SyncReport {
  const SyncReport(this.outcome, {this.error});

  final SyncOutcome outcome;
  final Object? error;
}

enum SyncNoticeKind { conflict, permanentFailure }

final class SyncNotice {
  const SyncNotice({
    required this.kind,
    required this.expenseId,
    required this.message,
  });

  final SyncNoticeKind kind;
  final String expenseId;
  final String message;
}

final class RetryPolicy {
  RetryPolicy({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Duration delayFor(int attemptCount, {Duration? retryAfter}) {
    final exponent = min(max(attemptCount - 1, 0), 7);
    final exponentialSeconds = min(2 * (1 << exponent), 300);
    final jitter = Duration(milliseconds: _random.nextInt(1001));
    final calculated = Duration(seconds: exponentialSeconds) + jitter;
    final requested = retryAfter ?? Duration.zero;
    final chosen = requested > calculated ? requested : calculated;
    return chosen > const Duration(minutes: 15)
        ? const Duration(minutes: 15)
        : chosen;
  }
}

final class SyncCoordinator {
  SyncCoordinator({
    required this._database,
    required this._api,
    RetryPolicy? retryPolicy,
    DateTime Function()? clock,
    this.pageSize = 100,
  }) : _retryPolicy = retryPolicy ?? RetryPolicy(),
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final AppDatabase _database;
  final ExpenseSyncApi _api;
  final RetryPolicy _retryPolicy;
  final DateTime Function() _clock;
  final int pageSize;
  final StreamController<SyncNotice> _notices =
      StreamController<SyncNotice>.broadcast();
  final StreamController<SyncReport> _reports =
      StreamController<SyncReport>.broadcast();

  Future<SyncReport>? _activeRun;
  SyncReport? _lastReport;

  Stream<SyncNotice> get notices => _notices.stream;
  Stream<SyncReport> get reports => _reports.stream;
  SyncReport? get lastReport => _lastReport;
  bool get isRunning => _activeRun != null;

  Future<SyncReport> synchronize() {
    final active = _activeRun;
    if (active != null) {
      return active;
    }
    final completer = Completer<SyncReport>();
    _activeRun = completer.future;
    () async {
      try {
        await _resetInterruptedMutations();
        await _pushAllReadyMutations();
        await _bootstrapIfNeeded();
        await _pullAllChanges();
        final completedAt = _clock();
        await (_database.update(
          _database.syncMetadata,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncMetadataCompanion(
            lastSuccessfulSyncAt: Value<DateTime>(completedAt),
            updatedAt: Value<DateTime>(completedAt),
          ),
        );
        _completeRun(completer, const SyncReport(SyncOutcome.completed));
      } on AuthenticationExpiredException catch (error) {
        _completeRun(
          completer,
          SyncReport(SyncOutcome.authenticationRequired, error: error),
        );
      } on NetworkException catch (error) {
        _completeRun(completer, SyncReport(SyncOutcome.offline, error: error));
      } catch (error) {
        _completeRun(completer, SyncReport(SyncOutcome.failed, error: error));
      } finally {
        _activeRun = null;
      }
    }();
    return completer.future;
  }

  void _completeRun(Completer<SyncReport> completer, SyncReport report) {
    _lastReport = report;
    _reports.add(report);
    completer.complete(report);
  }

  Future<void> _resetInterruptedMutations() async {
    await (_database.update(_database.outboxMutations)
          ..where((row) => row.status.equals(OutboxStatus.inFlight.storedName)))
        .write(
          OutboxMutationsCompanion(
            status: Value<String>(OutboxStatus.pending.storedName),
          ),
        );
  }

  Future<void> _pushAllReadyMutations() async {
    while (true) {
      final rows = await _claimReadyMutations();
      if (rows.isEmpty) {
        return;
      }
      final candidates = rows.map(_candidateFromRow).toList(growable: false);
      late final List<MutationResultDto> results;
      try {
        results = await _api.pushMutations(candidates);
        _validateResults(rows, results);
      } on NetworkException {
        await _markTransientFailure(rows, 'NETWORK_ERROR');
        rethrow;
      } on ApiException catch (error) {
        if (error.isTransient) {
          await _markTransientFailure(
            rows,
            error.code,
            retryAfter: error.retryAfter,
          );
        } else if (error.isAuthenticationFailure) {
          await _releaseClaims(rows, 'AUTHENTICATION_REQUIRED');
        } else {
          await _markPermanentFailure(rows, error.code);
        }
        rethrow;
      } on AuthenticationExpiredException {
        await _releaseClaims(rows, 'AUTHENTICATION_REQUIRED');
        rethrow;
      } on FormatException {
        await _markPermanentFailure(rows, 'PROTOCOL_ERROR');
        rethrow;
      }

      for (final result in results) {
        await _applyMutationResult(result);
      }
    }
  }

  Future<List<OutboxMutationRow>> _claimReadyMutations() async {
    return _database.transaction(() async {
      final all =
          await (_database.select(_database.outboxMutations)
                ..orderBy(<OrderingTerm Function(OutboxMutations)>[
                  (row) => OrderingTerm.asc(row.localSequence),
                ]))
              .get();
      final now = _clock();
      final seenEntities = <String>{};
      final ready = <OutboxMutationRow>[];
      for (final row in all) {
        if (!seenEntities.add(row.entityId)) {
          continue;
        }
        if (row.status != OutboxStatus.pending.storedName) {
          continue;
        }
        final nextAttempt = row.nextAttemptAt;
        if (nextAttempt != null && nextAttempt.toUtc().isAfter(now)) {
          continue;
        }
        ready.add(row);
        if (ready.length == 50) {
          break;
        }
      }
      for (final row in ready) {
        await (_database.update(
          _database.outboxMutations,
        )..where((item) => item.localSequence.equals(row.localSequence))).write(
          OutboxMutationsCompanion(
            status: Value<String>(OutboxStatus.inFlight.storedName),
            lastAttemptAt: Value<DateTime>(now),
          ),
        );
      }
      return ready;
    });
  }

  MutationCandidateDto _candidateFromRow(OutboxMutationRow row) {
    Map<String, Object?>? payload;
    if (row.payloadJson != null) {
      final decoded = jsonDecode(row.payloadJson!);
      if (decoded is! Map) {
        throw const FormatException('Outbox payload must be an object.');
      }
      payload = decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return MutationCandidateDto(
      mutationId: row.mutationId,
      entityId: row.entityId,
      operation: MutationOperationWire.parse(row.action),
      baseVersion: row.baseVersion,
      expense: payload,
    );
  }

  void _validateResults(
    List<OutboxMutationRow> rows,
    List<MutationResultDto> results,
  ) {
    if (rows.length != results.length) {
      throw const FormatException(
        'The API did not return one result per mutation.',
      );
    }
    for (var index = 0; index < rows.length; index += 1) {
      if (rows[index].mutationId != results[index].mutationId) {
        throw const FormatException('Mutation results are out of order.');
      }
    }
  }

  Future<void> _applyMutationResult(MutationResultDto result) async {
    SyncNotice? notice;
    await _database.transaction(() async {
      final mutation =
          await (_database.select(_database.outboxMutations)
                ..where((row) => row.mutationId.equals(result.mutationId)))
              .getSingleOrNull();
      if (mutation == null) {
        return;
      }

      switch (result.status) {
        case MutationResultStatus.applied:
          final expense = result.expense;
          if (expense == null) {
            throw const FormatException('APPLIED result needs an expense.');
          }
          await _acknowledgeMutation(mutation, expense);
        case MutationResultStatus.conflict:
          final expense = result.expense;
          if (expense == null) {
            throw const FormatException('CONFLICT result needs an expense.');
          }
          await (_database.delete(
            _database.outboxMutations,
          )..where((row) => row.entityId.equals(mutation.entityId))).go();
          await _upsertAuthoritative(expense);
          notice = SyncNotice(
            kind: SyncNoticeKind.conflict,
            expenseId: mutation.entityId,
            message: 'This expense changed elsewhere. Server data was kept.',
          );
        case MutationResultStatus.rejected:
          final code = result.code ?? 'REJECTED';
          await (_database.update(_database.outboxMutations)..where(
                (row) => row.localSequence.equals(mutation.localSequence),
              ))
              .write(
                OutboxMutationsCompanion(
                  status: Value<String>(OutboxStatus.needsAttention.storedName),
                  lastErrorCode: Value<String>(code),
                ),
              );
          await _markExpenseNeedsAttention(mutation.entityId);
          notice = SyncNotice(
            kind: SyncNoticeKind.permanentFailure,
            expenseId: mutation.entityId,
            message: 'This local change could not be synchronized ($code).',
          );
      }
    });
    if (notice != null) {
      _notices.add(notice!);
    }
  }

  Future<void> _acknowledgeMutation(
    OutboxMutationRow mutation,
    ExpenseDto authoritative,
  ) async {
    await (_database.delete(
      _database.outboxMutations,
    )..where((row) => row.localSequence.equals(mutation.localSequence))).go();
    final next =
        await (_database.select(_database.outboxMutations)
              ..where((row) => row.entityId.equals(mutation.entityId))
              ..orderBy(<OrderingTerm Function(OutboxMutations)>[
                (row) => OrderingTerm.asc(row.localSequence),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (next == null) {
      await _upsertAuthoritative(authoritative);
      return;
    }
    await (_database.update(
      _database.outboxMutations,
    )..where((row) => row.localSequence.equals(next.localSequence))).write(
      OutboxMutationsCompanion(baseVersion: Value<int>(authoritative.version)),
    );
    await (_database.update(
      _database.localExpenses,
    )..where((row) => row.id.equals(mutation.entityId))).write(
      LocalExpensesCompanion(
        version: Value<int>(authoritative.version),
        syncState: Value<String>(LocalSyncState.pending.storedName),
      ),
    );
  }

  Future<void> _markTransientFailure(
    List<OutboxMutationRow> rows,
    String code, {
    Duration? retryAfter,
  }) async {
    final now = _clock();
    await _database.transaction(() async {
      for (final row in rows) {
        final attempts = row.attemptCount + 1;
        await (_database.update(
          _database.outboxMutations,
        )..where((item) => item.localSequence.equals(row.localSequence))).write(
          OutboxMutationsCompanion(
            attemptCount: Value<int>(attempts),
            status: Value<String>(OutboxStatus.pending.storedName),
            lastErrorCode: Value<String>(code),
            nextAttemptAt: Value<DateTime>(
              now.add(_retryPolicy.delayFor(attempts, retryAfter: retryAfter)),
            ),
          ),
        );
      }
    });
  }

  Future<void> _releaseClaims(List<OutboxMutationRow> rows, String code) async {
    await _database.transaction(() async {
      for (final row in rows) {
        await (_database.update(
          _database.outboxMutations,
        )..where((item) => item.localSequence.equals(row.localSequence))).write(
          OutboxMutationsCompanion(
            status: Value<String>(OutboxStatus.pending.storedName),
            lastErrorCode: Value<String>(code),
          ),
        );
      }
    });
  }

  Future<void> _markPermanentFailure(
    List<OutboxMutationRow> rows,
    String code,
  ) async {
    await _database.transaction(() async {
      for (final row in rows) {
        await (_database.update(
          _database.outboxMutations,
        )..where((item) => item.localSequence.equals(row.localSequence))).write(
          OutboxMutationsCompanion(
            status: Value<String>(OutboxStatus.needsAttention.storedName),
            lastErrorCode: Value<String>(code),
          ),
        );
        await _markExpenseNeedsAttention(row.entityId);
      }
    });
  }

  Future<void> _markExpenseNeedsAttention(String entityId) {
    return (_database.update(
      _database.localExpenses,
    )..where((row) => row.id.equals(entityId))).write(
      LocalExpensesCompanion(
        syncState: Value<String>(LocalSyncState.needsAttention.storedName),
      ),
    );
  }

  Future<void> _bootstrapIfNeeded() async {
    var metadata = await _database.readSyncMetadata();
    if (metadata.lastCursor != null) {
      return;
    }

    var pageToken = metadata.bootstrapPageToken;
    var expectedWatermark = metadata.bootstrapWatermark;
    while (true) {
      final page = await _api.bootstrap(pageToken: pageToken, limit: pageSize);
      if (expectedWatermark != null &&
          expectedWatermark != page.watermarkCursor) {
        throw const FormatException(
          'Bootstrap watermark changed between pages.',
        );
      }
      expectedWatermark = page.watermarkCursor;
      if (page.hasMore && page.nextPageToken == null) {
        throw const FormatException('Bootstrap continuation token is missing.');
      }
      await _database.transaction(() async {
        for (final expense in page.items) {
          await _applyRemoteExpense(expense);
        }
        await (_database.update(
          _database.syncMetadata,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncMetadataCompanion(
            lastCursor: page.hasMore
                ? const Value<String?>.absent()
                : Value<String?>(page.watermarkCursor),
            bootstrapPageToken: Value<String?>(page.nextPageToken),
            bootstrapWatermark: page.hasMore
                ? Value<String?>(page.watermarkCursor)
                : const Value<String?>(null),
            updatedAt: Value<DateTime>(_clock()),
          ),
        );
      });
      if (!page.hasMore) {
        return;
      }
      pageToken = page.nextPageToken;
      metadata = await _database.readSyncMetadata();
      expectedWatermark = metadata.bootstrapWatermark;
    }
  }

  Future<void> _pullAllChanges() async {
    var metadata = await _database.readSyncMetadata();
    var cursor = metadata.lastCursor;
    if (cursor == null) {
      throw const FormatException('Bootstrap did not establish a cursor.');
    }
    while (true) {
      final page = await _api.pullChanges(cursor: cursor, limit: pageSize);
      await _database.transaction(() async {
        for (final change in page.changes) {
          await _applyRemoteChange(change);
        }
        await (_database.update(
          _database.syncMetadata,
        )..where((row) => row.singletonId.equals(1))).write(
          SyncMetadataCompanion(
            lastCursor: Value<String?>(page.nextCursor),
            updatedAt: Value<DateTime>(_clock()),
          ),
        );
      });
      cursor = page.nextCursor;
      if (!page.hasMore) {
        return;
      }
      metadata = await _database.readSyncMetadata();
      if (metadata.lastCursor != cursor) {
        throw StateError('Change cursor was not committed atomically.');
      }
    }
  }

  Future<void> _applyRemoteChange(ChangeDto change) async {
    final originating =
        await (_database.select(_database.outboxMutations)
              ..where((row) => row.mutationId.equals(change.originMutationId)))
            .getSingleOrNull();
    if (originating != null) {
      await _acknowledgeMutation(originating, change.expense);
      return;
    }
    await _applyRemoteExpense(change.expense);
  }

  Future<void> _applyRemoteExpense(ExpenseDto remote) async {
    final pending =
        await (_database.select(_database.outboxMutations)
              ..where((row) => row.entityId.equals(remote.id))
              ..limit(1))
            .getSingleOrNull();
    if (pending != null) {
      return;
    }
    final local = await _database.findExpenseRow(remote.id);
    if (local != null && local.version > remote.version) {
      return;
    }
    await _upsertAuthoritative(remote);
  }

  Future<void> _upsertAuthoritative(ExpenseDto remote) {
    final expense = expenseFromDto(remote);
    return _database
        .into(_database.localExpenses)
        .insertOnConflictUpdate(
          expenseCompanion(expense, localModifiedAt: remote.updatedAt),
        );
  }

  Future<void> close() async {
    await _notices.close();
    await _reports.close();
  }
}
