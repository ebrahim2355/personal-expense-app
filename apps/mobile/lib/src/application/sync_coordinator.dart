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
import '../notifications/household_activity_notifier.dart';

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
    required this.entityType,
    required this.entityId,
    required this.message,
  });

  final SyncNoticeKind kind;

  /// Which ledger the notice is about, so the UI can point at the right screen.
  final SyncEntityType entityType;
  final String entityId;
  final String message;
}

/// How an entity is named in a notice the members read.
String _entityLabel(SyncEntityType entityType) => switch (entityType) {
  SyncEntityType.expense => 'expense',
  SyncEntityType.period => 'spending period',
  SyncEntityType.loan => 'loan entry',
};

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
    this._notifier,
    this.pageSize = 100,
  }) : _retryPolicy = retryPolicy ?? RetryPolicy(),
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final AppDatabase _database;
  final ExpenseSyncApi _api;
  final RetryPolicy _retryPolicy;
  final DateTime Function() _clock;

  /// Announces the other member's incoming activity, or null to stay silent.
  ///
  /// Injected and awaited rather than exposed as another broadcast stream: the
  /// WorkManager isolate exits as soon as [synchronize] returns, so a listener
  /// registered on a stream might never get to run.
  final HouseholdActivityNotifier? _notifier;
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
      // One in-flight mutation per entity, keyed by type as well as id so the
      // three ledgers never shadow one another.
      final seenEntities = <String>{};
      final ready = <OutboxMutationRow>[];
      for (final row in all) {
        if (!seenEntities.add('${row.entityType}:${row.entityId}')) {
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
    final entityType = SyncEntityTypeWire.parse(row.entityType);
    return MutationCandidateDto(
      mutationId: row.mutationId,
      entityId: row.entityId,
      entityType: entityType,
      operation: MutationOperationWire.parse(row.action),
      baseVersion: row.baseVersion,
      // The payload travels under the property that matches the entity type, so
      // a period never arrives on the wire looking like an expense.
      expense: entityType == SyncEntityType.expense ? payload : null,
      period: entityType == SyncEntityType.period ? payload : null,
      loan: entityType == SyncEntityType.loan ? payload : null,
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
      // The queued row is the local authority on what was sent, so a result
      // whose entityType is absent still resolves to the right table.
      final entityType = SyncEntityTypeWire.parse(mutation.entityType);

      switch (result.status) {
        case MutationResultStatus.applied:
          final snapshot = result.snapshot;
          if (snapshot == null) {
            throw const FormatException('APPLIED result needs a snapshot.');
          }
          await _acknowledgeMutation(mutation, snapshot);
        case MutationResultStatus.conflict:
          final snapshot = result.snapshot;
          if (snapshot == null) {
            throw const FormatException('CONFLICT result needs a snapshot.');
          }
          await (_database.delete(
            _database.outboxMutations,
          )..where((row) => row.entityId.equals(mutation.entityId))).go();
          await _upsertAuthoritative(snapshot);
          notice = SyncNotice(
            kind: SyncNoticeKind.conflict,
            entityType: entityType,
            entityId: mutation.entityId,
            message:
                'This ${_entityLabel(entityType)} changed elsewhere. '
                'Server data was kept.',
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
          await _markNeedsAttention(entityType, mutation.entityId);
          notice = SyncNotice(
            kind: SyncNoticeKind.permanentFailure,
            entityType: entityType,
            entityId: mutation.entityId,
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
    EntitySnapshotDto authoritative,
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
    await _rebaseLocal(
      authoritative.entityType,
      mutation.entityId,
      authoritative.version,
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
        await _markNeedsAttention(
          SyncEntityTypeWire.parse(row.entityType),
          row.entityId,
        );
      }
    });
  }

  /// Flags the local row so the member sees the entry needs their attention.
  Future<void> _markNeedsAttention(SyncEntityType entityType, String entityId) {
    final flagged = Value<String>(LocalSyncState.needsAttention.storedName);
    return switch (entityType) {
      SyncEntityType.expense =>
        (_database.update(_database.localExpenses)
              ..where((row) => row.id.equals(entityId)))
            .write(LocalExpensesCompanion(syncState: flagged)),
      SyncEntityType.period =>
        (_database.update(_database.localPeriods)
              ..where((row) => row.id.equals(entityId)))
            .write(LocalPeriodsCompanion(syncState: flagged)),
      SyncEntityType.loan =>
        (_database.update(_database.localLoans)
              ..where((row) => row.id.equals(entityId)))
            .write(LocalLoansCompanion(syncState: flagged)),
    };
  }

  /// Adopts the server's version for an entity that still has queued edits, so
  /// the next one replays against the right base instead of conflicting.
  Future<void> _rebaseLocal(
    SyncEntityType entityType,
    String entityId,
    int version,
  ) {
    final pending = Value<String>(LocalSyncState.pending.storedName);
    return switch (entityType) {
      SyncEntityType.expense =>
        (_database.update(
          _database.localExpenses,
        )..where((row) => row.id.equals(entityId))).write(
          LocalExpensesCompanion(
            version: Value<int>(version),
            syncState: pending,
          ),
        ),
      SyncEntityType.period =>
        (_database.update(
          _database.localPeriods,
        )..where((row) => row.id.equals(entityId))).write(
          LocalPeriodsCompanion(
            version: Value<int>(version),
            syncState: pending,
          ),
        ),
      SyncEntityType.loan =>
        (_database.update(
          _database.localLoans,
        )..where((row) => row.id.equals(entityId))).write(
          LocalLoansCompanion(version: Value<int>(version), syncState: pending),
        ),
    };
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
        // The server pages periods before expenses before loans, so an expense
        // never lands before the period it names. Bootstrap goes straight to the
        // snapshot writer and never through _applyRemoteChange, which is what
        // keeps a fresh install from announcing the household's whole history.
        for (final item in page.items) {
          await _applyRemoteSnapshot(item);
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
    // Read once per run. Without a recorded member there is no way to tell the
    // other member's writes apart from this device's own echoing back, so an
    // unidentified device announces nothing rather than announcing wrongly.
    final self = _selfMember(metadata.memberKey);
    final notifier = metadata.householdActivityNotificationsEnabled
        ? _notifier
        : null;
    while (true) {
      final page = await _api.pullChanges(cursor: cursor, limit: pageSize);
      final incoming = <HouseholdActivity>[];
      await _database.transaction(() async {
        for (final change in page.changes) {
          final activity = await _applyRemoteChange(change, self: self);
          if (activity != null) {
            incoming.add(activity);
          }
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
      // Deliberately after the commit. Announcing inside the transaction would
      // promise a change that a rollback then takes back; announcing after it
      // means a crash in the gap loses a notification, which is no worse than
      // today's silence and the safer of the two failures.
      if (notifier != null && incoming.isNotEmpty) {
        await notifier.announce(incoming);
      }
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

  /// This device's own member, or null when none has been recorded yet.
  HouseholdMember? _selfMember(String? storedKey) {
    if (storedKey == null) {
      return null;
    }
    try {
      return HouseholdMemberWire.parse(storedKey);
    } on FormatException {
      // An unreadable stored key must not fail a sync. It only costs
      // notifications, and the next sign-in rewrites it.
      return null;
    }
  }

  /// Applies one change, and reports it when it is news from the other member.
  ///
  /// Returns null whenever there is nothing to announce: an acknowledgement of
  /// this device's own queued mutation, a snapshot that local state outranked, a
  /// change the server did not attribute, or a change this device authored.
  Future<HouseholdActivity?> _applyRemoteChange(
    ChangeDto change, {
    required HouseholdMember? self,
  }) async {
    final originating =
        await (_database.select(_database.outboxMutations)
              ..where((row) => row.mutationId.equals(change.originMutationId)))
            .getSingleOrNull();
    if (originating != null) {
      await _acknowledgeMutation(originating, change.snapshot);
      return null;
    }
    final applied = await _applyRemoteSnapshot(change.snapshot);
    if (!applied) {
      return null;
    }
    final actor = change.actorMember;
    // The author is the only reliable discriminator. A change this device wrote
    // reaches this point whenever the push earlier in the same run already
    // deleted its outbox row, so a missing outbox row says nothing about who
    // wrote it. An unattributed change comes from an API deployed before change
    // authorship existed; announcing it could self-notify, so it stays quiet.
    if (actor == null || self == null || actor == self) {
      return null;
    }
    return HouseholdActivity(
      actor: actor,
      operation: change.operation,
      snapshot: change.snapshot,
    );
  }

  /// Writes the server's snapshot unless local state outranks it. Reports
  /// whether anything was actually written.
  Future<bool> _applyRemoteSnapshot(EntitySnapshotDto remote) async {
    final pending =
        await (_database.select(_database.outboxMutations)
              ..where((row) => row.entityId.equals(remote.entityId))
              ..limit(1))
            .getSingleOrNull();
    if (pending != null) {
      return false;
    }
    final localVersion = await _localVersion(
      remote.entityType,
      remote.entityId,
    );
    if (localVersion != null && localVersion > remote.version) {
      return false;
    }
    await _upsertAuthoritative(remote);
    return true;
  }

  Future<int?> _localVersion(
    SyncEntityType entityType,
    String entityId,
  ) async => switch (entityType) {
    SyncEntityType.expense => (await _database.findExpenseRow(
      entityId,
    ))?.version,
    SyncEntityType.period => (await _database.findPeriodRow(entityId))?.version,
    SyncEntityType.loan => (await _database.findLoanRow(entityId))?.version,
  };

  Future<void> _upsertAuthoritative(EntitySnapshotDto remote) {
    switch (remote.entityType) {
      case SyncEntityType.expense:
        final dto = remote.expense!;
        return _database
            .into(_database.localExpenses)
            .insertOnConflictUpdate(
              expenseCompanion(
                expenseFromDto(dto),
                localModifiedAt: dto.updatedAt,
              ),
            );
      case SyncEntityType.period:
        final dto = remote.period!;
        return _database
            .into(_database.localPeriods)
            .insertOnConflictUpdate(
              periodCompanion(
                periodFromDto(dto),
                localModifiedAt: dto.updatedAt,
              ),
            );
      case SyncEntityType.loan:
        final dto = remote.loan!;
        return _database
            .into(_database.localLoans)
            .insertOnConflictUpdate(
              loanCompanion(loanFromDto(dto), localModifiedAt: dto.updatedAt),
            );
    }
  }

  Future<void> close() async {
    await _notices.close();
    await _reports.close();
  }
}
