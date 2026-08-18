import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/sync_coordinator.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/data/repositories/loan_repository.dart';
import 'package:houseexpenses/src/data/repositories/period_repository.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/loan.dart';

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
            return appliedResult(mutation.mutationId, expenseSnapshot(expense));
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
        amountMinor: 90000,
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
      appliedResult(
        mutation.mutationId,
        expenseSnapshot(remoteExpense(id: local.id, amountMinor: 500)),
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
                operation: ChangeOperation.created,
                originMutationId: '10000000-0000-4000-8000-000000000001',
                snapshot: expenseSnapshot(firstExpense),
              ),
            ],
            nextCursor: 'cursor-1',
            hasMore: true,
          ),
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                operation: ChangeOperation.created,
                originMutationId: '10000000-0000-4000-8000-000000000002',
                snapshot: expenseSnapshot(secondExpense),
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
            items: <BootstrapItemDto>[expenseSnapshot(active)],
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
                operation: ChangeOperation.deleted,
                originMutationId: '10000000-0000-4000-8000-000000000003',
                snapshot: expenseSnapshot(deleted),
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
            (mutation) => appliedResult(
              mutation.mutationId,
              expenseSnapshot(authoritative),
              status: MutationResultStatus.conflict,
              code: 'ENTITY_EXISTS',
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
    expect(notice.entityType, SyncEntityType.expense);
    expect(notice.message, contains('expense'));
    expect(await database.select(database.outboxMutations).get(), isEmpty);
  });

  test('bootstrap files an expense into the period that precedes it', () async {
    const periodId = '20000000-0000-4000-8000-000000000001';
    const expenseId = '00000000-0000-4000-8000-000000000010';
    const loanId = '30000000-0000-4000-8000-000000000001';
    final api = FakeExpenseSyncApi(
      bootstrapPages: <BootstrapPageDto>[
        BootstrapPageDto(
          // The server pages PERIOD before EXPENSE before LOAN, so the expense
          // never names a period this device has not stored yet.
          items: <BootstrapItemDto>[
            periodSnapshot(remotePeriod(id: periodId, sequenceNumber: 1)),
            expenseSnapshot(
              remoteExpense(
                id: expenseId,
                amountMinor: 80000,
                periodId: periodId,
              ),
            ),
            loanSnapshot(remoteLoan(id: loanId, amountMinor: 50000)),
          ],
          watermarkCursor: 'cursor-1',
          nextPageToken: null,
          hasMore: false,
        ),
      ],
    );
    final coordinator = SyncCoordinator(database: database, api: api);
    addTearDown(coordinator.close);

    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

    expect((await database.readOpenPeriodRow())!.id, periodId);
    expect((await repository.readVisibleExpenses()).single.periodId, periodId);
    expect((await database.readVisibleLoanRows()).single.id, loanId);
  });

  test('closing a period pushes the close ahead of the next open', () async {
    const periodId = '20000000-0000-4000-8000-000000000002';
    final api = FakeExpenseSyncApi(
      bootstrapPages: <BootstrapPageDto>[
        BootstrapPageDto(
          items: <BootstrapItemDto>[
            periodSnapshot(remotePeriod(id: periodId, sequenceNumber: 1)),
          ],
          watermarkCursor: 'cursor-1',
          nextPageToken: null,
          hasMore: false,
        ),
      ],
    );
    api.serverEntities[periodId] = periodSnapshot(
      remotePeriod(id: periodId, sequenceNumber: 1),
    );
    final coordinator = SyncCoordinator(database: database, api: api);
    addTearDown(coordinator.close);
    final periods = DriftPeriodRepository(database);
    addTearDown(periods.close);

    // The first sync brings the open period down; only then can it be closed.
    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);
    final rollover = await periods.closeAndOpenNext();
    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

    expect(
      api.pushedCandidates.map((candidate) => candidate.entityType),
      everyElement(SyncEntityType.period),
    );
    expect(
      api.pushedCandidates.map((candidate) => candidate.operation).toList(),
      <MutationOperation>[MutationOperation.update, MutationOperation.create],
    );
    expect(await database.select(database.outboxMutations).get(), isEmpty);

    final closed = await database.findPeriodRow(rollover.closed.id);
    expect(closed!.closedAt, isNotNull);
    expect(closed.version, 2);
    expect(closed.syncState, LocalSyncState.synced.storedName);
    final open = await database.readOpenPeriodRow();
    expect(open!.id, rollover.opened.id);
    expect(open.sequenceNumber, 2);
    expect(open.version, 1);
  });

  test('a close made on another device converges on this one', () async {
    const firstPeriod = '20000000-0000-4000-8000-000000000003';
    const secondPeriod = '20000000-0000-4000-8000-000000000004';
    final closedAt = DateTime.utc(2026, 8, 14, 10);
    final api = FakeExpenseSyncApi(
      bootstrapPages: <BootstrapPageDto>[
        BootstrapPageDto(
          items: <BootstrapItemDto>[
            periodSnapshot(remotePeriod(id: firstPeriod, sequenceNumber: 1)),
          ],
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
              operation: ChangeOperation.updated,
              originMutationId: '10000000-0000-4000-8000-000000000004',
              snapshot: periodSnapshot(
                remotePeriod(
                  id: firstPeriod,
                  sequenceNumber: 1,
                  version: 2,
                  closedAt: closedAt,
                ),
              ),
            ),
            ChangeDto(
              cursor: 'cursor-3',
              operation: ChangeOperation.created,
              originMutationId: '10000000-0000-4000-8000-000000000005',
              snapshot: periodSnapshot(
                remotePeriod(
                  id: secondPeriod,
                  sequenceNumber: 2,
                  startedAt: closedAt,
                ),
              ),
            ),
          ],
          nextCursor: 'cursor-3',
          hasMore: false,
        ),
      ],
    );
    final coordinator = SyncCoordinator(database: database, api: api);
    addTearDown(coordinator.close);

    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

    expect((await database.readOpenPeriodRow())!.id, secondPeriod);
    // The settled period stays on the device so History can still show it. The
    // raw row hands back a local-zone instant, which the mappers normalize.
    expect(
      (await database.findPeriodRow(firstPeriod))!.closedAt!.toUtc(),
      closedAt,
    );
    expect(await database.readPeriodRows(), hasLength(2));
  });

  test('a local loan delete round-trips as a tombstone', () async {
    final loans = DriftLoanRepository(database);
    addTearDown(loans.close);
    final coordinator = SyncCoordinator(
      database: database,
      api: FakeExpenseSyncApi(),
    );
    addTearDown(coordinator.close);
    final loan = await loans.create(
      const LoanDraft(
        debtor: HouseholdMember.ebrahim,
        amountMinor: 50000,
        note: 'Rickshaw fare',
      ),
    );

    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);
    expect((await loans.readVisibleLoans()).single.version, 1);

    await loans.delete(loan.id);
    expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

    expect(await loans.readVisibleLoans(), isEmpty);
    final stored = await database.findLoanRow(loan.id);
    expect(stored!.deletedAt, isNotNull);
    expect(stored.version, 2);
    expect(await database.select(database.outboxMutations).get(), isEmpty);
  });

  test('a remote loan tombstone hides the entry but keeps the row', () async {
    const id = '30000000-0000-4000-8000-000000000002';
    final api = FakeExpenseSyncApi(
      bootstrapPages: <BootstrapPageDto>[
        BootstrapPageDto(
          items: <BootstrapItemDto>[
            loanSnapshot(remoteLoan(id: id, amountMinor: 30000)),
          ],
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
              operation: ChangeOperation.deleted,
              originMutationId: '10000000-0000-4000-8000-000000000006',
              snapshot: loanSnapshot(
                remoteLoan(
                  id: id,
                  amountMinor: 30000,
                  version: 2,
                  deletedAt: DateTime.utc(2026, 8, 14, 11),
                ),
              ),
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

    expect(await database.readVisibleLoanRows(), isEmpty);
    final stored = await database.findLoanRow(id);
    expect(stored!.deletedAt, isNotNull);
    expect(stored.version, 2);
  });

  test('a rejected loan is flagged on the entry the member sees', () async {
    final loans = DriftLoanRepository(database);
    addTearDown(loans.close);
    final api = FakeExpenseSyncApi(
      pushHandler: (mutations) async => mutations
          .map(
            (mutation) => MutationResultDto(
              mutationId: mutation.mutationId,
              status: MutationResultStatus.rejected,
              entityType: mutation.entityType,
              code: 'VALIDATION_FAILED',
            ),
          )
          .toList(growable: false),
    );
    final coordinator = SyncCoordinator(database: database, api: api);
    addTearDown(coordinator.close);
    final loan = await loans.create(
      const LoanDraft(debtor: HouseholdMember.sumon, amountMinor: 20000),
    );
    final noticeFuture = coordinator.notices.first;

    await coordinator.synchronize();
    final notice = await noticeFuture;

    expect(notice.entityType, SyncEntityType.loan);
    expect(notice.entityId, loan.id);
    expect(notice.kind, SyncNoticeKind.permanentFailure);
    expect(
      (await database.findLoanRow(loan.id))!.syncState,
      LocalSyncState.needsAttention.storedName,
    );
  });

  group('household activity notifications', () {
    const otherMemberExpense = '00000000-0000-4000-8000-000000000020';

    /// A change feed carrying one expense written by Sumon, which is the other
    /// member on a device signed in as Ebrahim.
    FakeExpenseSyncApi apiWithSumonsExpense({
      HouseholdMember? actorMember = HouseholdMember.sumon,
    }) {
      return FakeExpenseSyncApi(
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                operation: ChangeOperation.created,
                actorMember: actorMember,
                originMutationId: '10000000-0000-4000-8000-000000000020',
                snapshot: expenseSnapshot(
                  remoteExpense(
                    id: otherMemberExpense,
                    amountMinor: 45000,
                    note: 'Rice',
                  ),
                ),
              ),
            ],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );
    }

    test('announces a change the other member made', () async {
      final notifier = RecordingActivityNotifier();
      final coordinator = SyncCoordinator(
        database: database,
        api: apiWithSumonsExpense(),
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(database, HouseholdMember.ebrahim);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      final activity = notifier.announced.single;
      expect(activity.actor, HouseholdMember.sumon);
      expect(activity.operation, ChangeOperation.created);
      expect(activity.entityType, SyncEntityType.expense);
      expect(activity.snapshot.entityId, otherMemberExpense);
      expect(activity.dedupeKey, '$otherMemberExpense:1');
    });

    test('stays silent about your own write echoing back', () async {
      // The regression test for self-notification. The push deletes the outbox
      // row before the pull runs in the very same sync, so the change comes back
      // with no outbox row to match it and only its author says it began here.
      final notifier = RecordingActivityNotifier();
      await recordDeviceMember(database, HouseholdMember.ebrahim);
      final local = await repository.create(
        ExpenseDraft(
          amountMinor: 30000,
          category: ExpenseCategory.groceries,
          payer: HouseholdMember.ebrahim,
          occurredAt: DateTime.utc(2026, 8, 14),
        ),
      );
      final queued =
          (await database.select(database.outboxMutations).get()).single;
      final api = FakeExpenseSyncApi(
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                operation: ChangeOperation.created,
                actorMember: HouseholdMember.ebrahim,
                originMutationId: queued.mutationId,
                snapshot: expenseSnapshot(
                  remoteExpense(
                    id: local.id,
                    amountMinor: 30000,
                    payer: HouseholdMember.ebrahim,
                  ),
                ),
              ),
            ],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(
        database: database,
        api: api,
        notifier: notifier,
      );
      addTearDown(coordinator.close);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      expect(notifier.batches, isEmpty);
      expect(await database.select(database.outboxMutations).get(), isEmpty);
      expect((await repository.readVisibleExpenses()).single.id, local.id);
    });

    test('stays silent through the first bootstrap', () async {
      final notifier = RecordingActivityNotifier();
      final api = FakeExpenseSyncApi(
        bootstrapPages: <BootstrapPageDto>[
          BootstrapPageDto(
            items: <BootstrapItemDto>[
              periodSnapshot(
                remotePeriod(
                  id: '20000000-0000-4000-8000-000000000020',
                  sequenceNumber: 1,
                ),
              ),
              expenseSnapshot(
                remoteExpense(id: otherMemberExpense, amountMinor: 45000),
              ),
            ],
            watermarkCursor: 'cursor-1',
            nextPageToken: null,
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(
        database: database,
        api: api,
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(database, HouseholdMember.ebrahim);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      // A fresh install downloads the household's whole history. Announcing it
      // would bury the member under notifications for entries they have seen.
      expect(notifier.batches, isEmpty);
      expect(await repository.readVisibleExpenses(), hasLength(1));
    });

    test('stays silent when local state outranks the change', () async {
      final notifier = RecordingActivityNotifier();
      // Version 2 arrives in the bootstrap, so the version-1 change that follows
      // is stale and nothing is written. Announcing it would describe a state
      // that is not what the member would find on screen.
      final api = FakeExpenseSyncApi(
        bootstrapPages: <BootstrapPageDto>[
          BootstrapPageDto(
            items: <BootstrapItemDto>[
              expenseSnapshot(
                remoteExpense(
                  id: otherMemberExpense,
                  amountMinor: 99000,
                  version: 2,
                ),
              ),
            ],
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
                operation: ChangeOperation.updated,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000020',
                snapshot: expenseSnapshot(
                  remoteExpense(id: otherMemberExpense, amountMinor: 45000),
                ),
              ),
            ],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(
        database: database,
        api: api,
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(database, HouseholdMember.ebrahim);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      expect(notifier.batches, isEmpty);
      final stored = (await repository.readVisibleExpenses()).single;
      expect(stored.version, 2);
      expect(stored.amountMinor, 99000);
    });

    test('stays silent while a local edit is still queued', () async {
      final notifier = RecordingActivityNotifier();
      await recordDeviceMember(database, HouseholdMember.ebrahim);
      final local = await repository.create(
        ExpenseDraft(
          amountMinor: 30000,
          category: ExpenseCategory.groceries,
          payer: HouseholdMember.ebrahim,
          occurredAt: DateTime.utc(2026, 8, 14),
        ),
      );
      // The push is rejected, so the mutation stays in the outbox needing the
      // member's attention. The pull then leaves that entity alone, and a change
      // that was never applied must not be announced.
      final api = FakeExpenseSyncApi(
        pushHandler: (mutations) async => mutations
            .map(
              (mutation) => MutationResultDto(
                mutationId: mutation.mutationId,
                status: MutationResultStatus.rejected,
                entityType: mutation.entityType,
                code: 'VALIDATION_FAILED',
              ),
            )
            .toList(growable: false),
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                operation: ChangeOperation.updated,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000020',
                snapshot: expenseSnapshot(
                  remoteExpense(id: local.id, amountMinor: 45000, version: 3),
                ),
              ),
            ],
            nextCursor: 'cursor-2',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(
        database: database,
        api: api,
        notifier: notifier,
      );
      addTearDown(coordinator.close);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      expect(notifier.batches, isEmpty);
      final stored = (await repository.readVisibleExpenses()).single;
      expect(stored.amountMinor, 30000);
      expect(
        await database.select(database.outboxMutations).get(),
        hasLength(1),
      );
    });

    test('announces nothing when the page transaction fails', () async {
      final notifier = RecordingActivityNotifier();
      final api = FakeExpenseSyncApi(
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                operation: ChangeOperation.created,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000021',
                snapshot: expenseSnapshot(
                  remoteExpense(id: otherMemberExpense, amountMinor: 45000),
                ),
              ),
              ChangeDto(
                cursor: 'cursor-3',
                operation: ChangeOperation.created,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000022',
                snapshot: malformedSnapshot(),
              ),
            ],
            nextCursor: 'cursor-3',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(
        database: database,
        api: api,
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(database, HouseholdMember.ebrahim);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.failed);

      // The first change was collected before the failure, but the transaction
      // rolled it back. Announcing it would promise an entry the member cannot
      // find, so posting waits until after the commit.
      expect(notifier.batches, isEmpty);
      expect(await database.findExpenseRow(otherMemberExpense), isNull);
      expect((await database.readSyncMetadata()).lastCursor, 'cursor-0');
    });

    test('respects the Settings switch being off', () async {
      final notifier = RecordingActivityNotifier();
      final coordinator = SyncCoordinator(
        database: database,
        api: apiWithSumonsExpense(),
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(
        database,
        HouseholdMember.ebrahim,
        announcementsEnabled: false,
      );

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      // Silenced, but still synced: the switch turns off announcements only.
      expect(notifier.batches, isEmpty);
      expect(await repository.readVisibleExpenses(), hasLength(1));
    });

    test('stays silent when the API did not attribute the change', () async {
      final notifier = RecordingActivityNotifier();
      final coordinator = SyncCoordinator(
        database: database,
        api: apiWithSumonsExpense(actorMember: null),
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(database, HouseholdMember.ebrahim);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      // An APK running against an API deployed before change authorship. It must
      // keep syncing, and it must not guess who wrote what.
      expect(notifier.batches, isEmpty);
      expect(await repository.readVisibleExpenses(), hasLength(1));
    });

    test('announces one batch per page, in the applied order', () async {
      final notifier = RecordingActivityNotifier();
      final api = FakeExpenseSyncApi(
        changePages: <ChangePageDto>[
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-2',
                operation: ChangeOperation.created,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000023',
                snapshot: expenseSnapshot(
                  remoteExpense(id: otherMemberExpense, amountMinor: 45000),
                ),
              ),
              ChangeDto(
                cursor: 'cursor-3',
                operation: ChangeOperation.created,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000024',
                snapshot: loanSnapshot(
                  remoteLoan(
                    id: '30000000-0000-4000-8000-000000000020',
                    amountMinor: 100000,
                  ),
                ),
              ),
            ],
            nextCursor: 'cursor-3',
            hasMore: true,
          ),
          ChangePageDto(
            changes: <ChangeDto>[
              ChangeDto(
                cursor: 'cursor-4',
                operation: ChangeOperation.created,
                actorMember: HouseholdMember.sumon,
                originMutationId: '10000000-0000-4000-8000-000000000025',
                snapshot: periodSnapshot(
                  remotePeriod(
                    id: '20000000-0000-4000-8000-000000000021',
                    sequenceNumber: 1,
                  ),
                ),
              ),
            ],
            nextCursor: 'cursor-4',
            hasMore: false,
          ),
        ],
      );
      final coordinator = SyncCoordinator(
        database: database,
        api: api,
        notifier: notifier,
      );
      addTearDown(coordinator.close);
      await recordDeviceMember(database, HouseholdMember.ebrahim);

      expect((await coordinator.synchronize()).outcome, SyncOutcome.completed);

      // One announcement per committed page, so a member who was offline for a
      // while is told about a page as soon as that page is durable.
      expect(notifier.batches.map((batch) => batch.length).toList(), <int>[
        2,
        1,
      ]);
      expect(
        notifier.announced.map((activity) => activity.entityType).toList(),
        <SyncEntityType>[
          SyncEntityType.expense,
          SyncEntityType.loan,
          SyncEntityType.period,
        ],
      );
    });
  });
}
