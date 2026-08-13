import 'dart:async';

import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/domain/expense.dart';

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
      final handler = pushHandler;
      if (handler != null) {
        return await handler(mutations);
      }
      return mutations
          .map(
            (mutation) => MutationResultDto(
              mutationId: mutation.mutationId,
              status: MutationResultStatus.applied,
              expense: expenseFromCandidate(mutation),
            ),
          )
          .toList(growable: false);
    } finally {
      activePushes -= 1;
    }
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
      items: <ExpenseDto>[],
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
    version: version,
    updatedAt: (updatedAt ?? DateTime.utc(2026, 8, 13, 12)).toUtc(),
  );
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
}) => ExpenseDto(
  id: id,
  amountMinor: amountMinor,
  category: category,
  payer: payer,
  occurredAt: occurredAt ?? DateTime.utc(2026, 8, 1, 8),
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
