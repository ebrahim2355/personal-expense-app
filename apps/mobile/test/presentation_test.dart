import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/sync_coordinator.dart';
import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/data/repositories/auth_repository.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/domain/dhaka_time.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/session.dart';
import 'package:houseexpenses/src/presentation/dashboard_screen.dart';
import 'package:houseexpenses/src/presentation/expense_form_screen.dart';
import 'package:houseexpenses/src/presentation/history_screen.dart';
import 'package:houseexpenses/src/presentation/home_shell.dart';
import 'package:houseexpenses/src/presentation/login_screen.dart';
import 'package:houseexpenses/src/presentation/presentation_providers.dart';
import 'package:houseexpenses/src/providers.dart';

void main() {
  final august = DhakaTime.initialize().range(
    const CalendarDate(2026, 8, 1),
    const CalendarDate(2026, 8, 31),
  );

  group('login', () {
    testWidgets('selects a member, validates PIN, and submits safely', (
      tester,
    ) async {
      final auth = FakeMemberAuthRepository();
      await tester.pumpWidget(
        _testApp(const LoginScreen(), <Override>[
          authRepositoryProvider.overrideWithValue(auth),
        ]),
      );

      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pump();
      expect(find.text('Enter your 6 to 12 digit PIN.'), findsOneWidget);

      await tester.tap(find.text('Ebrahim'));
      await tester.enterText(find.byKey(const Key('pin-field')), '123456');
      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pump();

      expect(auth.loginCalls, 1);
      expect(auth.lastMember, HouseholdMember.ebrahim);
      expect(auth.lastPin, '123456');
    });

    testWidgets('shows a clear offline sign-in error', (tester) async {
      final auth = FakeMemberAuthRepository(
        loginError: const NetworkException('offline'),
      );
      await tester.pumpWidget(
        _testApp(const LoginScreen(), <Override>[
          authRepositoryProvider.overrideWithValue(auth),
        ]),
      );
      await tester.enterText(find.byKey(const Key('pin-field')), '123456');
      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pump();

      expect(find.textContaining('Can’t reach the server'), findsOneWidget);
    });

    testWidgets('uses one generic message for invalid credentials', (
      tester,
    ) async {
      final auth = FakeMemberAuthRepository(
        loginError: const ApiException(
          statusCode: 401,
          code: 'INVALID_CREDENTIALS',
          message: 'internal detail',
        ),
      );
      await tester.pumpWidget(
        _testApp(const LoginScreen(), <Override>[
          authRepositoryProvider.overrideWithValue(auth),
        ]),
      );
      await tester.enterText(find.byKey(const Key('pin-field')), '123456');
      await tester.tap(find.byKey(const Key('login-button')));
      await tester.pump();

      expect(
        find.text('Couldn’t sign in. Check the selected member and PIN.'),
        findsOneWidget,
      );
      expect(find.textContaining('internal detail'), findsNothing);
    });
  });

  group('dashboard', () {
    testWidgets('shows exact paid, share, total, and settlement values', (
      tester,
    ) async {
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(
          id: 'sumon-1000',
          amountMinor: 100000,
          payer: HouseholdMember.sumon,
        ),
        testExpense(
          id: 'ebrahim-200',
          amountMinor: 20000,
          payer: HouseholdMember.ebrahim,
        ),
      ]);
      await tester.pumpWidget(
        _testApp(
          DashboardScreen(onOpenExpense: (_) {}),
          _dataOverrides(repository, august),
        ),
      );
      await tester.pump();

      expect(find.text('৳1,200.00'), findsOneWidget);
      expect(find.text('Ebrahim owes Sumon ৳400.00'), findsOneWidget);
      expect(find.text('৳1,000.00'), findsWidgets);
      expect(find.text('৳200.00'), findsOneWidget);
      expect(find.text('৳600.00'), findsNWidgets(2));
    });

    testWidgets('shows an understandable empty state', (tester) async {
      final repository = FakeExpenseRepository();
      await tester.pumpWidget(
        _testApp(
          DashboardScreen(onOpenExpense: (_) {}),
          _dataOverrides(repository, august),
        ),
      );
      await tester.pump();

      expect(find.text('No expenses in this range'), findsOneWidget);
      expect(find.text('All settled'), findsOneWidget);
    });

    testWidgets('fits a small screen with enlarged text', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(id: 'small', amountMinor: 100000),
      ]);
      await tester.pumpWidget(
        _testApp(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: DashboardScreen(onOpenExpense: (_) {}),
          ),
          _dataOverrides(repository, august),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('expense mutations', () {
    testWidgets('validates an amount before adding', (tester) async {
      final repository = FakeExpenseRepository();
      await tester.pumpWidget(_formLauncher(repository));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.pump();

      expect(
        find.text(
          'Enter a positive BDT amount with at most two decimal places.',
        ),
        findsOneWidget,
      );
      expect(repository.createCalls, 0);
    });

    testWidgets('adds offline immediately and prevents duplicate submission', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final repository = FakeExpenseRepository.blocking(saveGate.future);
      await tester.pumpWidget(_formLauncher(repository));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amount-field')), '100.01');
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(repository.expenses.single.amountMinor, 10001);
      expect(repository.expenses.single.syncState, LocalSyncState.pending);

      saveGate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('edits an existing local expense', (tester) async {
      final existing = testExpense(id: 'edit-me', amountMinor: 5000);
      final repository = FakeExpenseRepository(<Expense>[existing]);
      await tester.pumpWidget(_formLauncher(repository, expense: existing));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amount-field')), '75.25');
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.pumpAndSettle();

      expect(repository.editCalls, 1);
      expect(repository.expenses.single.amountMinor, 7525);
    });

    testWidgets('requires confirmation before deleting', (tester) async {
      final expense = testExpense(id: 'delete-me', amountMinor: 5000);
      final repository = FakeExpenseRepository(<Expense>[expense]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: HistoryScreen(onEditExpense: (_) {})),
          _dataOverrides(repository, august),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Expense actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete expense?'), findsOneWidget);
      expect(repository.deleteCalls, 0);

      await tester.tap(find.byKey(const Key('confirm-delete-button')));
      await tester.pumpAndSettle();
      expect(repository.deleteCalls, 1);
      expect(repository.expenses, isEmpty);
    });
  });

  group('sync feedback', () {
    testWidgets('shows offline pending state without blocking local data', (
      tester,
    ) async {
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(
          id: 'pending',
          amountMinor: 1000,
          syncState: LocalSyncState.pending,
        ),
      ]);
      final overrides = _dataOverrides(
        repository,
        august,
        syncOutcome: SyncOutcome.offline,
      );
      await tester.pumpWidget(
        _testApp(DashboardScreen(onOpenExpense: (_) {}), overrides),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('manual-sync-button')));
      await tester.pump();

      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('local change is safe'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('shows a brief server-wins conflict notice', (tester) async {
      final repository = FakeExpenseRepository();
      final overrides = _dataOverrides(repository, august)
        ..add(
          syncNoticesProvider.overrideWith(
            (ref) => Stream<SyncNotice>.value(
              const SyncNotice(
                kind: SyncNoticeKind.conflict,
                expenseId: 'conflict-id',
                message:
                    'This expense changed elsewhere. Server data was kept.',
              ),
            ),
          ),
        );
      await tester.pumpWidget(
        _testApp(HomeShell(member: testIdentity), overrides),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('sync-notice-banner')), findsOneWidget);
      expect(find.textContaining('Server data was kept'), findsOneWidget);
    });
  });
}

Widget _testApp(Widget child, [List<Override> overrides = const <Override>[]]) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: ThemeData(useMaterial3: true), home: child),
  );
}

List<Override> _dataOverrides(
  FakeExpenseRepository repository,
  ExpenseDateRange range, {
  SyncOutcome syncOutcome = SyncOutcome.completed,
}) {
  return <Override>[
    expenseRepositoryProvider.overrideWithValue(repository),
    visibleExpensesProvider.overrideWith(
      (ref) => repository.watchVisibleExpenses(),
    ),
    dashboardRangeProvider.overrideWith((ref) => range),
    historyFilterProvider.overrideWith((ref) => HistoryFilter(range: range)),
    unresolvedMutationCountProvider.overrideWith(
      (ref) => Stream<int>.value(
        repository.expenses
            .where((expense) => expense.syncState != LocalSyncState.synced)
            .length,
      ),
    ),
    lastSuccessfulSyncProvider.overrideWith(
      (ref) => Stream<DateTime?>.value(null),
    ),
    manualSyncControllerProvider.overrideWith(
      (ref) => ManualSyncController(
        synchronize: () async => SyncReport(syncOutcome),
      ),
    ),
    apiEnvironmentLabelProvider.overrideWithValue('Test · example.test'),
  ];
}

Widget _formLauncher(FakeExpenseRepository repository, {Expense? expense}) {
  return ProviderScope(
    overrides: <Override>[
      expenseRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('launch-form'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => ExpenseFormScreen(
                    defaultPayer: HouseholdMember.sumon,
                    expense: expense,
                  ),
                ),
              ),
              child: const Text('Launch'),
            ),
          ),
        ),
      ),
    ),
  );
}

const testIdentity = MemberIdentity(
  id: '00000000-0000-4000-8000-000000000001',
  householdId: '00000000-0000-4000-8000-000000000010',
  member: HouseholdMember.sumon,
  displayName: 'Sumon',
);

Expense testExpense({
  required String id,
  required int amountMinor,
  HouseholdMember payer = HouseholdMember.sumon,
  ExpenseCategory category = ExpenseCategory.groceries,
  LocalSyncState syncState = LocalSyncState.synced,
}) {
  return Expense(
    id: id,
    amountMinor: amountMinor,
    category: category,
    payer: payer,
    occurredAt: DateTime.utc(2026, 8, 10, 12),
    version: 1,
    updatedAt: DateTime.utc(2026, 8, 10, 12),
    syncState: syncState,
  );
}

final class FakeMemberAuthRepository implements MemberAuthRepository {
  FakeMemberAuthRepository({this.loginError});

  final Object? loginError;
  int loginCalls = 0;
  HouseholdMember? lastMember;
  String? lastPin;

  @override
  Future<MemberIdentity> login(HouseholdMember member, String pin) async {
    loginCalls += 1;
    lastMember = member;
    lastPin = pin;
    final error = loginError;
    if (error != null) {
      throw error;
    }
    return MemberIdentity(
      id: 'member-id',
      householdId: 'household-id',
      member: member,
      displayName: member.displayName,
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<MemberIdentity?> restoreStoredIdentity() async => null;

  @override
  Future<void> signOutLocally() async {}
}

final class FakeExpenseRepository implements ExpenseRepository {
  FakeExpenseRepository([List<Expense> initial = const <Expense>[]])
    : expenses = <Expense>[...initial],
      createGate = null;

  FakeExpenseRepository.blocking(Future<void> gate)
    : expenses = <Expense>[],
      createGate = gate;

  final List<Expense> expenses;
  final Future<void>? createGate;
  final StreamController<List<Expense>> _changes =
      StreamController<List<Expense>>.broadcast();
  final StreamController<LocalMutationEvent> _mutations =
      StreamController<LocalMutationEvent>.broadcast();
  int createCalls = 0;
  int editCalls = 0;
  int deleteCalls = 0;

  @override
  Stream<LocalMutationEvent> get localMutations => _mutations.stream;

  @override
  Stream<List<Expense>> watchVisibleExpenses() async* {
    yield List<Expense>.unmodifiable(expenses);
    yield* _changes.stream;
  }

  @override
  Future<List<Expense>> readVisibleExpenses() async =>
      List<Expense>.unmodifiable(expenses);

  @override
  Future<Expense> create(ExpenseDraft draft) async {
    createCalls += 1;
    final normalized = draft.normalized();
    final expense = Expense(
      id: 'created-$createCalls',
      amountMinor: normalized.amountMinor,
      category: normalized.category,
      payer: normalized.payer,
      occurredAt: normalized.occurredAt,
      note: normalized.note,
      version: 0,
      updatedAt: DateTime.utc(2026, 8, 13),
      syncState: LocalSyncState.pending,
    );
    expenses.add(expense);
    _emit(expense.id);
    await createGate;
    return expense;
  }

  @override
  Future<Expense> edit(String id, ExpenseDraft draft) async {
    editCalls += 1;
    final index = expenses.indexWhere((expense) => expense.id == id);
    if (index < 0) {
      throw ExpenseNotFoundException(id);
    }
    final normalized = draft.normalized();
    final current = expenses[index];
    final updated = Expense(
      id: current.id,
      amountMinor: normalized.amountMinor,
      category: normalized.category,
      payer: normalized.payer,
      occurredAt: normalized.occurredAt,
      note: normalized.note,
      version: current.version,
      updatedAt: DateTime.utc(2026, 8, 13),
      syncState: LocalSyncState.pending,
    );
    expenses[index] = updated;
    _emit(id);
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls += 1;
    expenses.removeWhere((expense) => expense.id == id);
    _emit(id);
  }

  void _emit(String id) {
    _changes.add(List<Expense>.unmodifiable(expenses));
    _mutations.add(LocalMutationEvent(id));
  }
}
