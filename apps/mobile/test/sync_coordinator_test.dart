import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/sync_coordinator.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/domain/expense.dart';

import 'support/fakes.dart';

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

  test('lost response retries one mutation id without a duplicate', () async {
    var now = DateTime.utc(2026, 8, 13, 12);
    final receipts = <String, MutationResultDto>{};
    final serverExpenses = <String, ExpenseDto>{};
    var loseFirstResponse = true;
    final api = FakeExpenseSyncApi(
      pushHandler: (mutations) async {
        final results = <MutationResultDto>[];
        for (final mutation in mutations) {
          final result = receipts.putIfAbsent(mutation.mutationId, () {
            final expense = expenseFromCandidate(mutation, updatedAt: now);
            serverExpenses[expense.id] = expense;
            return MutationResultDto(
              mutationId: mutation.mutationId,
              status: MutationResultStatus.applied,
              expense: expense,
            );
          });
          results.add(result);
        }
        if (loseFirstResponse) {
          loseFirstResponse = false;
          throw const NetworkException('simulated lost response');
        }
        return results;
      },
    );
    final coordinator = SyncCoordinator(
      database: database,
      api: api,
      clock: () => now,
    );
    addTearDown(coordinator.close);
    await repository.create(
      ExpenseDraft(
        amountMinor: 999,
        category: ExpenseCategory.transport,
        payer: HouseholdMember.sumon,
        occurredAt: DateTime.utc(2026, 8, 13),
      ),
    );

    expect((await coordinator.synchronize()).outcome, SyncOutcome.offline);
    expect(await repository.readVisibleExpenses(), hasLength(1));
    now = now.add(const Duration(minutes: 16));
    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

    expect(api.pushCalls, 2);
    expect(receipts, hasLength(1));
    expect(serverExpenses, hasLength(1));
    expect(await database.select(database.outboxMutations).get(), isEmpty);
    expect((await repository.readVisibleExpenses()).single.version, 1);
  });

  test('concurrent sync triggers share one active job', () async {
    final blocking = BlockingPush();
    final api = FakeExpenseSyncApi(pushHandler: blocking.call);
    final coordinator = SyncCoordinator(database: database, api: api);
    addTearDown(coordinator.close);
    final local = await repository.create(
      ExpenseDraft(
        amountMinor: 500,
        category: ExpenseCategory.household,
        payer: HouseholdMember.ebrahim,
        occurredAt: DateTime.utc(2026, 8, 13),
      ),
    );

    final first = coordinator.synchronize();
    await blocking.started.future;
    final second = coordinator.synchronize();
    expect(identical(first, second), isTrue);
    final mutation =
        (await database.select(database.outboxMutations).get()).single;
    blocking.result.complete(<MutationResultDto>[
      MutationResultDto(
        mutationId: mutation.mutationId,
        status: MutationResultStatus.applied,
        expense: remoteExpense(id: local.id, amountMinor: 500),
      ),
    ]);

    expect((await first).outcome, SyncOutcome.completed);
    expect((await second).outcome, SyncOutcome.completed);
    expect(api.pushCalls, 1);
    expect(api.maximumActivePushes, 1);
  });

  test(
    'pull pagination applies every page and commits the final cursor',
    () async {
      final firstExpense = remoteExpense(
        id: '00000000-0000-4000-8000-000000000001',
        amountMinor: 100,
      );
      final secondExpense = remoteExpense(
        id: '00000000-0000-4000-8000-000000000002',
        amountMinor: 200,
      );
      final api = FakeExpenseSyncApi(
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-1',
                originMutationId: '10000000-0000-4000-8000-000000000001',
                expense: firstExpense,
              ),
            ],
            nextCursor: 'cursor-1',
            hasMore: true,
          ),
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                originMutationId: '10000000-0000-4000-8000-000000000002',
                expense: secondExpense,
              ),
            ],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(database: database, api: api);
      addTearDown(coordinator.close);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      expect(await repository.readVisibleExpenses(), hasLength(2));
      expect((await database.readSyncMetadata()).lastCursor, 'cursor-2');
      expect(api.pullCalls, 2);
    },
  );

  test(
    'remote tombstone is retained but hidden from repository reads',
    () async {
      const id = '00000000-0000-4000-8000-000000000003';
      final active = remoteExpense(id: id, amountMinor: 300);
      final deleted = remoteExpense(
        id: id,
        amountMinor: 300,
        version: 2,
        deletedAt: DateTime.utc(2026, 8, 13, 13),
      );
      final api = FakeExpenseSyncApi(
        bootstrapPages: <BootstrapPageDto>[
          BootstrapPageDto(
            items: <ExpenseDto>[active],
            watermarkCursor: 'cursor-1',
            nextPageToken: null,
            hasMore: false,
          ),
        ],
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                originMutationId: '10000000-0000-4000-8000-000000000003',
                expense: deleted,
              ),
            ],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(database: database, api: api);
      addTearDown(coordinator.close);

      await coordinator.synchronize();

      expect(await repository.readVisibleExpenses(), isEmpty);
      final stored = await database.findExpenseRow(id);
      expect(stored!.deletedAt, isNotNull);
      expect(stored.version, 2);
    },
  );

  test('conflict replaces optimistic data and emits a notice', () async {
    late ExpenseDto authoritative;
    final api = FakeExpenseSyncApi(
      pushHandler: (mutations) async => mutations
          .map(
            (mutation) => MutationResultDto(
              mutationId: mutation.mutationId,
              status: MutationResultStatus.conflict,
              code: 'ENTITY_EXISTS',
              expense: authoritative,
            ),
          )
          .toList(growable: false),
    );
    final coordinator = SyncCoordinator(database: database, api: api);
    addTearDown(coordinator.close);
    final local = await repository.create(
      ExpenseDraft(
        amountMinor: 100,
        category: ExpenseCategory.other,
        payer: HouseholdMember.sumon,
        occurredAt: DateTime.utc(2026, 8, 13),
      ),
    );
    authoritative = remoteExpense(
      id: local.id,
      amountMinor: 800,
      payer: HouseholdMember.ebrahim,
      version: 4,
    );
    final noticeFuture = coordinator.notices.first;

    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);
    final notice = await noticeFuture;
    final stored = (await repository.readVisibleExpenses()).single;

    expect(stored.amountMinor, 800);
    expect(stored.payer, HouseholdMember.ebrahim);
    expect(stored.version, 4);
    expect(stored.syncState, LocalSyncState.synced);
    expect(notice.kind, SyncNoticeKind.conflict);
    expect(await database.select(database.outboxMutations).get(), isEmpty);
  });
}
