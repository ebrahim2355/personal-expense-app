import 'dart:async';

import 'package:drift/drift.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/notifications/household_activity_notifier.dart';
import 'package:houseexpenses/src/notifications/notification_permissions.dart';

typedef PushHandler = Future<List<MutationResultDto>> Function(
  List<MutationCandidateDto> mutations,
);

final class FakeExpenseSyncApi implements ExpenseSyncApi {
  FakeExpenseSyncApi({
    this.pushHandler,
    List<BootstrapPageDto>? bootstrapPages,
    List<ChangePageDto>? changePages,
  }) : _bootstrapPages = bootstrapPages ?? <BootstrapPageDto>[],
       _changePages = changePages ?? <ChangePageDto>[];

  final PushHandler? pushHandler;
  final List<BootstrapPageDto> _bootstrapPages;
  final List<ChangePageDto> _changePages;

  /// What the default handler believes about each entity. A DELETE candidate
  /// carries no payload, so echoing a tombstone needs the previous snapshot.
  final Map<String, EntitySnapshotDto> serverEntities =
      <String, EntitySnapshotDto>{};
  final List<MutationCandidateDto> pushedCandidates = <MutationCandidateDto>[];
  int pushCalls = 0;
  int activePushes = 0;
  int maximumActivePushes = 0;
  int bootstrapCalls = 0;
  int pullCalls = 0;

  @override
  Future<List<MutationResultDto>> pushMutations(
    List<MutationCandidateDto> mutations,
  ) async {
    pushCalls += 1;
    activePushes += 1;
    if (activePushes > maximumActivePushes) {
      maximumActivePushes = activePushes;
    }
    try {
      pushedCandidates.addAll(mutations);
      final handler = pushHandler;
      if (handler != null) {
        return await handler(mutations);
      }
      return mutations.map(_applyToFakeServer).toList(growable: false);
    } finally {
      activePushes -= 1;
    }
  }

  /// Applies one candidate the way the server would: the payload becomes the
  /// authoritative snapshot, a delete becomes a tombstone, and either way the
  /// version advances.
  MutationResultDto _applyToFakeServer(MutationCandidateDto candidate) {
    final previous = serverEntities[candidate.entityId];
    final version = (previous?.version ?? 0) + 1;
    final snapshot = candidate.operation == MutationOperation.delete
        ? tombstoneOf(previous, version: version)
        : snapshotFromCandidate(candidate, version: version);
    serverEntities[candidate.entityId] = snapshot;
    return appliedResult(candidate.mutationId, snapshot);
  }

  @override
  Future<BootstrapPageDto> bootstrap({
    String? pageToken,
    required int limit,
  }) async {
    final index = bootstrapCalls++;
    if (index < _bootstrapPages.length) {
      return _bootstrapPages[index];
    }
    return const BootstrapPageDto(
      items: <BootstrapItemDto>[],
      watermarkCursor: 'cursor-0',
      nextPageToken: null,
      hasMore: false,
    );
  }

  @override
  Future<ChangePageDto> pullChanges({
    String? cursor,
    required int limit,
  }) async {
    final index = pullCalls++;
    if (index < _changePages.length) {
      return _changePages[index];
    }
    return ChangePageDto(
      changes: const <ChangeDto>[],
      nextCursor: cursor ?? 'cursor-0',
      hasMore: false,
    );
  }
}

/// Records what a coordinator announced, so a test can assert on the batching
/// as well as on the contents.
final class RecordingActivityNotifier implements HouseholdActivityNotifier {
  /// One entry per [announce] call, which is one entry per synced page that had
  /// anything to say.
  final List<List<HouseholdActivity>> batches = <List<HouseholdActivity>>[];

  List<HouseholdActivity> get announced =>
      batches.expand((batch) => batch).toList(growable: false);

  @override
  Future<void> announce(List<HouseholdActivity> activities) async {
    batches.add(List<HouseholdActivity>.unmodifiable(activities));
  }
}

final class FakeNotificationPermissions implements NotificationPermissions {
  FakeNotificationPermissions({
    this.enabled = true,
    this.grants = true,
    this.canAsk = true,
  });

  /// What Android currently answers about this app's notifications.
  bool enabled;

  /// What the permission dialog would return. A denial leaves [enabled] false.
  bool grants;

  /// Whether an ask reaches Android at all. False models the request failing
  /// before the dialog — the shape a missing status icon takes — which must not
  /// be recorded as the member's answer.
  bool canAsk;
  int requestCalls = 0;

  @override
  Future<bool> areNotificationsEnabled() async => enabled;

  @override
  Future<bool?> requestPermission() async {
    requestCalls += 1;
    if (!canAsk) {
      return null;
    }
    enabled = grants;
    return grants;
  }
}

/// Records who is signed in on this device, which is what lets the coordinator
/// tell the other member's changes from its own echoing back, and optionally
/// turns announcements off the way the Settings switch does.
Future<void> recordDeviceMember(
  AppDatabase database,
  HouseholdMember member, {
  bool announcementsEnabled = true,
}) async {
  // Ensures the singleton exists before updating it.
  await database.readSyncMetadata();
  await (database.update(
    database.syncMetadata,
  )..where((row) => row.singletonId.equals(1))).write(
    SyncMetadataCompanion(
      memberKey: Value<String>(member.wireName),
      householdActivityNotificationsEnabled: Value<bool>(announcementsEnabled),
      updatedAt: Value<DateTime>(DateTime.utc(2026, 8, 13, 12)),
    ),
  );
}

/// A snapshot whose payload is missing, so the first write against it throws.
/// Stands in for any failure inside the transaction that applies a change page.
EntitySnapshotDto malformedSnapshot() =>
    const EntitySnapshotDto(entityType: SyncEntityType.expense);

EntitySnapshotDto expenseSnapshot(ExpenseDto expense) =>
    EntitySnapshotDto(entityType: SyncEntityType.expense, expense: expense);

EntitySnapshotDto periodSnapshot(PeriodDto period) =>
    EntitySnapshotDto(entityType: SyncEntityType.period, period: period);

EntitySnapshotDto loanSnapshot(LoanDto loan) =>
    EntitySnapshotDto(entityType: SyncEntityType.loan, loan: loan);

/// The result the server returns once it has applied a mutation, with the
/// snapshot placed on the property that matches its entity type.
MutationResultDto appliedResult(
  String mutationId,
  EntitySnapshotDto snapshot, {
  MutationResultStatus status = MutationResultStatus.applied,
  String? code,
}) => MutationResultDto(
  mutationId: mutationId,
  status: status,
  entityType: snapshot.entityType,
  code: code,
  expense: snapshot.expense,
  period: snapshot.period,
  loan: snapshot.loan,
);

/// Rebuilds the entity a CREATE or UPDATE candidate describes, dispatching on
/// the candidate's entity type so a period is never read as an expense.
EntitySnapshotDto snapshotFromCandidate(
  MutationCandidateDto candidate, {
  int version = 1,
  DateTime? updatedAt,
}) => switch (candidate.entityType) {
  SyncEntityType.expense => expenseSnapshot(
    expenseFromCandidate(candidate, version: version, updatedAt: updatedAt),
  ),
  SyncEntityType.period => periodSnapshot(
    periodFromCandidate(candidate, version: version, updatedAt: updatedAt),
  ),
  SyncEntityType.loan => loanSnapshot(
    loanFromCandidate(candidate, version: version, updatedAt: updatedAt),
  ),
};

ExpenseDto expenseFromCandidate(
  MutationCandidateDto candidate, {
  int version = 1,
  DateTime? updatedAt,
}) {
  final payload = candidate.expense!;
  return ExpenseDto(
    id: candidate.entityId,
    amountMinor: payload['amountMinor']! as int,
    category: ExpenseCategoryWire.parse(payload['category']! as String),
    payer: HouseholdMemberWire.parse(payload['payer']! as String),
    occurredAt: DateTime.parse(payload['occurredAt']! as String).toUtc(),
    note: payload['note'] as String?,
    periodId: payload['periodId'] as String?,
    version: version,
    updatedAt: (updatedAt ?? DateTime.utc(2026, 8, 13, 12)).toUtc(),
  );
}

PeriodDto periodFromCandidate(
  MutationCandidateDto candidate, {
  int version = 1,
  DateTime? updatedAt,
}) {
  final payload = candidate.period!;
  final closedAt = payload['closedAt'] as String?;
  return PeriodDto(
    id: candidate.entityId,
    sequenceNumber: payload['sequenceNumber']! as int,
    startedAt: DateTime.parse(payload['startedAt']! as String).toUtc(),
    closedAt: closedAt == null ? null : DateTime.parse(closedAt).toUtc(),
    note: payload['note'] as String?,
    version: version,
    updatedAt: (updatedAt ?? DateTime.utc(2026, 8, 13, 12)).toUtc(),
  );
}

LoanDto loanFromCandidate(
  MutationCandidateDto candidate, {
  int version = 1,
  DateTime? updatedAt,
}) {
  final payload = candidate.loan!;
  return LoanDto(
    id: candidate.entityId,
    debtor: HouseholdMemberWire.parse(payload['debtor']! as String),
    amountMinor: payload['amountMinor']! as int,
    occurredAt: DateTime.parse(payload['occurredAt']! as String).toUtc(),
    note: payload['note'] as String?,
    version: version,
    updatedAt: (updatedAt ?? DateTime.utc(2026, 8, 13, 12)).toUtc(),
  );
}

/// The tombstone a DELETE produces. Periods are never deleted — the server
/// answers INVALID_MUTATION — so asking for one here is a test-authoring bug.
EntitySnapshotDto tombstoneOf(
  EntitySnapshotDto? previous, {
  required int version,
  DateTime? deletedAt,
}) {
  if (previous == null) {
    throw StateError('Cannot delete an entity the fake server never saw.');
  }
  final at = deletedAt ?? DateTime.utc(2026, 8, 13, 13);
  switch (previous.entityType) {
    case SyncEntityType.expense:
      final dto = previous.expense!;
      return expenseSnapshot(
        ExpenseDto(
          id: dto.id,
          amountMinor: dto.amountMinor,
          category: dto.category,
          payer: dto.payer,
          occurredAt: dto.occurredAt,
          note: dto.note,
          periodId: dto.periodId,
          version: version,
          updatedAt: at,
          deletedAt: at,
        ),
      );
    case SyncEntityType.period:
      throw StateError('A spending period cannot be deleted.');
    case SyncEntityType.loan:
      final dto = previous.loan!;
      return loanSnapshot(
        LoanDto(
          id: dto.id,
          debtor: dto.debtor,
          amountMinor: dto.amountMinor,
          occurredAt: dto.occurredAt,
          note: dto.note,
          version: version,
          updatedAt: at,
          deletedAt: at,
        ),
      );
  }
}

ExpenseDto remoteExpense({
  required String id,
  required int amountMinor,
  int version = 1,
  ExpenseCategory category = ExpenseCategory.groceries,
  HouseholdMember payer = HouseholdMember.sumon,
  DateTime? occurredAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? note,
  String? periodId,
}) => ExpenseDto(
  id: id,
  amountMinor: amountMinor,
  category: category,
  payer: payer,
  occurredAt: occurredAt ?? DateTime.utc(2026, 8, 1, 8),
  note: note,
  periodId: periodId,
  version: version,
  updatedAt: updatedAt ?? DateTime.utc(2026, 8, 13, 12),
  deletedAt: deletedAt,
);

PeriodDto remotePeriod({
  required String id,
  required int sequenceNumber,
  int version = 1,
  DateTime? startedAt,
  DateTime? closedAt,
  DateTime? updatedAt,
  String? note,
}) => PeriodDto(
  id: id,
  sequenceNumber: sequenceNumber,
  startedAt: startedAt ?? DateTime.utc(2026, 8, 1),
  closedAt: closedAt,
  note: note,
  version: version,
  updatedAt: updatedAt ?? DateTime.utc(2026, 8, 13, 12),
);

LoanDto remoteLoan({
  required String id,
  required int amountMinor,
  int version = 1,
  HouseholdMember debtor = HouseholdMember.ebrahim,
  DateTime? occurredAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? note,
}) => LoanDto(
  id: id,
  debtor: debtor,
  amountMinor: amountMinor,
  occurredAt: occurredAt ?? DateTime.utc(2026, 8, 2, 9),
  note: note,
  version: version,
  updatedAt: updatedAt ?? DateTime.utc(2026, 8, 13, 12),
  deletedAt: deletedAt,
);

final class QueueHttpTransport implements HttpTransport {
  QueueHttpTransport(this.responses);

  final List<TransportResponse> responses;
  final List<TransportRequest> requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (responses.isEmpty) {
      throw StateError('No fake HTTP response remains.');
    }
    return responses.removeAt(0);
  }
}

final class BlockingPush {
  final Completer<void> started = Completer<void>();
  final Completer<List<MutationResultDto>> result =
      Completer<List<MutationResultDto>>();

  Future<List<MutationResultDto>> call(List<MutationCandidateDto> mutations) {
    if (!started.isCompleted) {
      started.complete();
    }
    return result.future;
  }
}
