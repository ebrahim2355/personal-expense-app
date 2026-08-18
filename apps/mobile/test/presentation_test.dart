import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/notification_settings.dart';
import 'package:houseexpenses/src/application/sync_coordinator.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/api_models.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/data/repositories/auth_repository.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/data/repositories/loan_repository.dart';
import 'package:houseexpenses/src/data/repositories/period_repository.dart';
import 'package:houseexpenses/src/domain/dhaka_time.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/loan.dart';
import 'package:houseexpenses/src/domain/session.dart';
import 'package:houseexpenses/src/domain/spending_period.dart';
import 'package:houseexpenses/src/presentation/dashboard_screen.dart';
import 'package:houseexpenses/src/presentation/expense_form_screen.dart';
import 'package:houseexpenses/src/presentation/history_screen.dart';
import 'package:houseexpenses/src/presentation/home_shell.dart';
import 'package:houseexpenses/src/presentation/lending_screen.dart';
import 'package:houseexpenses/src/presentation/loan_form_screen.dart';
import 'package:houseexpenses/src/presentation/login_screen.dart';
import 'package:houseexpenses/src/presentation/presentation_providers.dart';
import 'package:houseexpenses/src/presentation/settings_screen.dart';
import 'package:houseexpenses/src/providers.dart';

// Only the notification permission fake is borrowed: this file defines its own
// repository fakes, and a blanket import would collide with the sync helpers.
import 'support/fakes.dart' show FakeNotificationPermissions;

/// The period the dashboard is scoped to in these tests, and an older settled one
/// that must stay out of the dashboard while remaining browsable in History.
const openPeriodId = '20000000-0000-4000-8000-000000000002';
const closedPeriodId = '20000000-0000-4000-8000-000000000001';

void main() {
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
      _useTallScreen(tester);
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
          _dataOverrides(repository),
        ),
      );
      await tester.pump();

      // Whole taka everywhere: not one amount carries a decimal point.
      expect(find.text('৳1,200'), findsOneWidget);
      expect(find.text('Ebrahim owes Sumon ৳400'), findsOneWidget);
      expect(find.text('৳1,000'), findsWidgets);
      expect(find.text('৳600'), findsNWidgets(2));
      expect(find.textContaining(RegExp(r'৳[\d,]*[.]')), findsNothing);
    });

    testWidgets('is scoped to the open period, not to a calendar month', (
      tester,
    ) async {
      _useTallScreen(tester);
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(id: 'this-period', amountMinor: 30000),
        // Already settled, so it belongs to History and not to the total.
        testExpense(
          id: 'last-period',
          amountMinor: 500000,
          periodId: closedPeriodId,
          occurredAt: DateTime.utc(2026, 7, 5, 12),
        ),
      ]);
      await tester.pumpWidget(
        _testApp(
          DashboardScreen(onOpenExpense: (_) {}),
          _dataOverrides(repository),
        ),
      );
      await tester.pump();

      expect(find.text('৳300'), findsWidgets);
      expect(find.text('৳5,000'), findsNothing);
      expect(find.textContaining('Period 2'), findsOneWidget);
      expect(find.text('1 in this period'), findsOneWidget);
    });

    testWidgets('shows an understandable empty state', (tester) async {
      _useTallScreen(tester);
      final repository = FakeExpenseRepository();
      await tester.pumpWidget(
        _testApp(
          DashboardScreen(onOpenExpense: (_) {}),
          _dataOverrides(repository),
        ),
      );
      await tester.pump();

      expect(find.text('No expenses in this period'), findsOneWidget);
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
          _dataOverrides(repository),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('closing states the final settlement before it commits', (
      tester,
    ) async {
      _useTallScreen(tester);
      final periods = FakePeriodRepository(<SpendingPeriod>[
        testPeriod(id: openPeriodId, sequenceNumber: 2),
      ]);
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
          Scaffold(body: DashboardScreen(onOpenExpense: (_) {})),
          _dataOverrides(repository, periods: periods),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('close-period-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('close-period-dialog')), findsOneWidget);
      expect(find.text('Close Period 2?'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('close-period-settlement')))
            .data,
        'Ebrahim owes Sumon ৳400',
      );
      expect(find.text('Total spent: ৳1,200'), findsOneWidget);
      expect(periods.closeCalls, 0);

      await tester.tap(find.byKey(const Key('confirm-close-period-button')));
      await tester.pumpAndSettle();

      expect(periods.closeCalls, 1);
      expect(find.textContaining('Period 2 closed'), findsOneWidget);
      expect(find.textContaining('Period 3 is now open'), findsOneWidget);
    });

    testWidgets('a cancelled confirmation leaves the period open', (
      tester,
    ) async {
      _useTallScreen(tester);
      final periods = FakePeriodRepository(<SpendingPeriod>[
        testPeriod(id: openPeriodId, sequenceNumber: 2),
      ]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: DashboardScreen(onOpenExpense: (_) {})),
          _dataOverrides(FakeExpenseRepository(), periods: periods),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('close-period-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(periods.closeCalls, 0);
      expect(find.byKey(const Key('close-period-dialog')), findsNothing);
    });
  });

  group('lending ledger', () {
    testWidgets('reads its own net total from manual entries only', (
      tester,
    ) async {
      final loans = FakeLoanRepository(<Loan>[
        testLoan(id: 'ebrahim-500', amountMinor: 50000),
        testLoan(
          id: 'sumon-200',
          amountMinor: 20000,
          debtor: HouseholdMember.sumon,
        ),
      ]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: LendingScreen(onEditLoan: (_) {})),
          _dataOverrides(FakeExpenseRepository(), loans: loans),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('loan-net-text'))).data,
        'Ebrahim owes Sumon ৳300',
      );
      expect(find.text('Ebrahim owes Sumon ৳500'), findsOneWidget);
      expect(find.text('Sumon owes Ebrahim ৳200'), findsOneWidget);
    });

    testWidgets('an empty ledger says so without a figure', (tester) async {
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: LendingScreen(onEditLoan: (_) {})),
          _dataOverrides(FakeExpenseRepository(), loans: FakeLoanRepository()),
        ),
      );
      await tester.pump();

      expect(find.text('No outstanding loans'), findsOneWidget);
      expect(find.text('No loans recorded'), findsOneWidget);
    });

    testWidgets('search narrows the list but never the net total', (
      tester,
    ) async {
      final loans = FakeLoanRepository(<Loan>[
        testLoan(id: 'ebrahim-500', amountMinor: 50000, note: 'Rickshaw fare'),
        testLoan(
          id: 'sumon-200',
          amountMinor: 20000,
          debtor: HouseholdMember.sumon,
          note: 'Bus pass',
        ),
      ]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: LendingScreen(onEditLoan: (_) {})),
          _dataOverrides(FakeExpenseRepository(), loans: loans),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('lending-search-field')),
        'rickshaw',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('loan-ebrahim-500')), findsOneWidget);
      expect(find.byKey(const Key('loan-sumon-200')), findsNothing);
      // The figure the members owe each other does not move when a search does.
      expect(
        tester.widget<Text>(find.byKey(const Key('loan-net-text'))).data,
        'Ebrahim owes Sumon ৳300',
      );
    });

    testWidgets('requires confirmation before deleting an entry', (
      tester,
    ) async {
      final loans = FakeLoanRepository(<Loan>[
        testLoan(id: 'delete-me', amountMinor: 50000),
      ]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: LendingScreen(onEditLoan: (_) {})),
          _dataOverrides(FakeExpenseRepository(), loans: loans),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Loan actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(find.text('Delete loan entry?'), findsOneWidget);
      expect(loans.deleteCalls, 0);

      await tester.tap(find.byKey(const Key('confirm-delete-loan-button')));
      await tester.pumpAndSettle();
      expect(loans.deleteCalls, 1);
      expect(loans.loans, isEmpty);
    });

    testWidgets('records a loan and stamps the time for the member', (
      tester,
    ) async {
      final loans = FakeLoanRepository();
      await tester.pumpWidget(_loanFormLauncher(loans));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();

      expect(find.text('Sumon owes Ebrahim.'), findsOneWidget);
      expect(find.text('Whole taka only'), findsOneWidget);
      expect(find.text('Stamped automatically when you save.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('loan-amount-field')), '500');
      await tester.tap(find.byKey(const Key('save-loan-button')));
      await tester.pumpAndSettle();

      expect(loans.createCalls, 1);
      expect(loans.loans.single.amountMinor, 50000);
      expect(loans.loans.single.summaryText, 'Sumon owes Ebrahim ৳500');
      expect(loans.loans.single.occurredAt.isUtc, isTrue);
    });

    testWidgets('validates a loan amount before saving', (tester) async {
      final loans = FakeLoanRepository();
      await tester.pumpWidget(_loanFormLauncher(loans));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-loan-button')));
      await tester.pump();

      expect(
        find.text('Enter a whole taka amount using digits only.'),
        findsOneWidget,
      );
      expect(loans.createCalls, 0);
    });
  });

  group('expense history', () {
    testWidgets('search reaches every period, closed ones included', (
      tester,
    ) async {
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(id: 'open-groceries', amountMinor: 30000),
        testExpense(
          id: 'closed-medicine',
          amountMinor: 45000,
          category: ExpenseCategory.medicine,
          payer: HouseholdMember.ebrahim,
          periodId: closedPeriodId,
          occurredAt: DateTime.utc(2026, 7, 5, 12),
          note: 'Pharmacy run',
        ),
      ]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: HistoryScreen(onEditExpense: (_) {})),
          _dataOverrides(repository),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('expense-open-groceries')), findsOneWidget);

      // A note fragment finds the settled period's row.
      await tester.enterText(
        find.byKey(const Key('history-search-field')),
        'pharmacy',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expense-closed-medicine')), findsOneWidget);
      expect(find.byKey(const Key('expense-open-groceries')), findsNothing);

      // So does a category, a payer and the bare whole-taka digits.
      for (final needle in <String>['medicine', 'ebrahim', '450']) {
        await tester.enterText(
          find.byKey(const Key('history-search-field')),
          needle,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('expense-closed-medicine')),
          findsOneWidget,
          reason: 'searching "$needle" should find the medicine expense',
        );
        expect(find.byKey(const Key('expense-open-groceries')), findsNothing);
      }

      await tester.enterText(
        find.byKey(const Key('history-search-field')),
        'nothing matches this',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching expenses'), findsOneWidget);
    });

    testWidgets('the period selector narrows history to one period', (
      tester,
    ) async {
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(id: 'open-groceries', amountMinor: 30000),
        testExpense(
          id: 'closed-medicine',
          amountMinor: 45000,
          periodId: closedPeriodId,
          occurredAt: DateTime.utc(2026, 7, 5, 12),
        ),
      ]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: HistoryScreen(onEditExpense: (_) {})),
          _dataOverrides(repository),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('history-period-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Period 1').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expense-closed-medicine')), findsOneWidget);
      expect(find.byKey(const Key('expense-open-groceries')), findsNothing);
    });

    testWidgets('an optional date range still narrows the list', (
      tester,
    ) async {
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(id: 'august', amountMinor: 30000),
        testExpense(
          id: 'july',
          amountMinor: 45000,
          periodId: closedPeriodId,
          occurredAt: DateTime.utc(2026, 7, 5, 12),
        ),
      ]);
      final august = DhakaTime.initialize().range(
        const CalendarDate(2026, 8, 1),
        const CalendarDate(2026, 8, 31),
      );
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: HistoryScreen(onEditExpense: (_) {})),
          _dataOverrides(
            repository,
            historyFilter: HistoryFilter(range: august),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('expense-august')), findsOneWidget);
      expect(find.byKey(const Key('expense-july')), findsNothing);

      await tester.tap(find.byKey(const Key('history-clear-range')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expense-july')), findsOneWidget);
      expect(find.text('All dates'), findsOneWidget);
    });

    testWidgets('requires confirmation before deleting', (tester) async {
      final expense = testExpense(id: 'delete-me', amountMinor: 5000);
      final repository = FakeExpenseRepository(<Expense>[expense]);
      await tester.pumpWidget(
        _testApp(
          Scaffold(body: HistoryScreen(onEditExpense: (_) {})),
          _dataOverrides(repository),
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

  group('expense mutations', () {
    testWidgets('validates an amount before adding', (tester) async {
      final repository = FakeExpenseRepository();
      await tester.pumpWidget(_formLauncher(repository));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.pump();

      expect(
        find.text('Enter a whole taka amount using digits only.'),
        findsOneWidget,
      );
      expect(repository.createCalls, 0);
    });

    testWidgets('the amount field refuses a decimal point outright', (
      tester,
    ) async {
      final repository = FakeExpenseRepository();
      await tester.pumpWidget(_formLauncher(repository));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      expect(find.text('Whole taka only'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('amount-field')), '100.01');
      await tester.pump();

      // The formatter drops the separator instead of validating it away later.
      expect(find.text('10001'), findsOneWidget);
      expect(find.text('100.01'), findsNothing);
    });

    testWidgets('adds offline immediately and prevents duplicate submission', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final repository = FakeExpenseRepository.blocking(saveGate.future);
      await tester.pumpWidget(_formLauncher(repository));
      await tester.tap(find.byKey(const Key('launch-form')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amount-field')), '1000');
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(repository.expenses.single.amountMinor, 100000);
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
      expect(find.text('50'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('amount-field')), '75');
      await tester.tap(find.byKey(const Key('save-expense-button')));
      await tester.pumpAndSettle();

      expect(repository.editCalls, 1);
      expect(repository.expenses.single.amountMinor, 7500);
    });
  });

  group('sync feedback', () {
    testWidgets('shows offline pending state without blocking local data', (
      tester,
    ) async {
      _useTallScreen(tester);
      final repository = FakeExpenseRepository(<Expense>[
        testExpense(
          id: 'pending',
          amountMinor: 1000,
          syncState: LocalSyncState.pending,
        ),
      ]);
      final overrides = _dataOverrides(
        repository,
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
      final overrides = _dataOverrides(repository)
        ..add(
          syncNoticesProvider.overrideWith(
            (ref) => Stream<SyncNotice>.value(
              const SyncNotice(
                kind: SyncNoticeKind.conflict,
                entityType: SyncEntityType.expense,
                entityId: 'conflict-id',
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

    testWidgets('names the ledger a loan notice came from', (tester) async {
      final overrides = _dataOverrides(FakeExpenseRepository())
        ..add(
          syncNoticesProvider.overrideWith(
            (ref) => Stream<SyncNotice>.value(
              const SyncNotice(
                kind: SyncNoticeKind.permanentFailure,
                entityType: SyncEntityType.loan,
                entityId: 'loan-id',
                message:
                    'This local change could not be synchronized '
                    '(INVALID_MUTATION).',
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
      expect(find.textContaining('INVALID_MUTATION'), findsOneWidget);
    });
  });

  group('home shell', () {
    testWidgets('gives each ledger its own tab and its own add button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          HomeShell(member: testIdentity),
          _dataOverrides(FakeExpenseRepository()),
        ),
      );
      await tester.pump();

      expect(_appBarTitle(tester), 'Dashboard');
      expect(find.byKey(const Key('add-expense-button')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.swap_horiz_outlined));
      await tester.pumpAndSettle();
      expect(_appBarTitle(tester), 'Lending');
      expect(find.byKey(const Key('add-loan-button')), findsOneWidget);
      expect(find.byKey(const Key('add-expense-button')), findsNothing);

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      expect(_appBarTitle(tester), 'Expense history');
      expect(find.byKey(const Key('add-expense-button')), findsOneWidget);

      // Settings is the only tab with no add button and no sync action.
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(_appBarTitle(tester), 'Settings');
      expect(find.byKey(const Key('add-expense-button')), findsNothing);
      expect(find.byKey(const Key('add-loan-button')), findsNothing);
      expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);
    });
  });

  group('settings notifications', () {
    // Each test opens its own in-memory database, so Drift's shared-executor
    // warning — and the page of stack trace it prints — is a false positive here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    late AppDatabase database;
    late FakeNotificationPermissions permissions;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      permissions = FakeNotificationPermissions();
      addTearDown(database.close);
    });

    /// Builds the real notification providers over an in-memory database, so a
    /// tap goes through the controller and Drift rather than a stub.
    Future<void> pumpSettings(WidgetTester tester) async {
      _useTallScreen(tester);
      await tester.pumpWidget(
        _testApp(
          const SettingsScreen(member: testIdentity),
          _dataOverrides(
            FakeExpenseRepository(),
            notifications: NotificationSettingsController(
              database: database,
              permissions: permissions,
            ),
          ),
        ),
      );
    }

    /// Takes the tree down while the test can still pump.
    ///
    /// Disposing the provider scope cancels the Drift stream behind the switch,
    /// and Drift schedules that cancellation on a zero-duration timer. Left to
    /// the framework's own teardown the timer never fires, which both fails the
    /// test and leaves `database.close()` waiting forever. The pump has to name
    /// a duration: a bare `pump()` only flushes microtasks and draws a frame,
    /// without moving the fake clock the timer is waiting on.
    Future<void> disposeTree(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets(
      'turning the switch off is recorded and reflected in the copy',
      (tester) async {
        await pumpSettings(tester);
        await tester.pumpAndSettle();

        // Announcements are on by default, and Android is allowing them, so the
        // card carries nothing but the switch.
        expect(_activitySwitch(tester).value, isTrue);
        expect(find.text('Android is blocking notifications'), findsNothing);

        await tester.tap(find.byKey(const Key('household-activity-switch')));
        await tester.pumpAndSettle();

        expect(_activitySwitch(tester).value, isFalse);
        expect(
          (await database.readSyncMetadata())
              .householdActivityNotificationsEnabled,
          isFalse,
        );
        // Turning announcements off must not read as turning sync off.
        expect(
          find.text('Nothing is announced. Sync keeps running as usual.'),
          findsOneWidget,
        );

        await disposeTree(tester);
      },
    );

    testWidgets('cannot be toggled before the stored preference arrives', (
      tester,
    ) async {
      await pumpSettings(tester);

      // The first frame renders while the preference is still being read, so a
      // tap then would write the optimistic "on" back over whatever is stored.
      expect(_activitySwitch(tester).onChanged, isNull);

      await tester.pumpAndSettle();
      expect(_activitySwitch(tester).onChanged, isNotNull);

      await disposeTree(tester);
    });

    testWidgets('spells out how to undo a denial, and re-checks on demand', (
      tester,
    ) async {
      permissions.enabled = false;
      await pumpSettings(tester);
      await tester.pumpAndSettle();

      expect(find.text('Android is blocking notifications'), findsOneWidget);
      final recheck = find.byKey(
        const Key('recheck-notification-permission-button'),
      );
      expect(recheck, findsOneWidget);

      // What a member does after following the instructions: allow the
      // permission in Android Settings, come back, and re-check.
      permissions.enabled = true;
      await tester.tap(recheck);
      await tester.pumpAndSettle();

      expect(find.text('Android is blocking notifications'), findsNothing);
      expect(recheck, findsNothing);
      // A blocked permission never touched the household preference, so the
      // switch is still where the member left it.
      expect(_activitySwitch(tester).value, isTrue);

      await disposeTree(tester);
    });
  });
}

Widget _testApp(Widget child, [List<Override> overrides = const <Override>[]]) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: ThemeData(useMaterial3: true), home: child),
  );
}

/// A viewport tall enough to render a whole dashboard, so a card below the fold
/// is reachable without scrolling a lazily built list.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The app bar title is what tells a member which tab they are on, so tab tests
/// read it rather than counting widgets an [IndexedStack] keeps alive off-screen.
String? _appBarTitle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
    )
    .data;

/// The household activity switch, read as a widget so a test can assert on both
/// its value and whether it currently accepts a tap.
SwitchListTile _activitySwitch(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const Key('household-activity-switch')));

List<Override> _dataOverrides(
  FakeExpenseRepository repository, {
  FakePeriodRepository? periods,
  FakeLoanRepository? loans,
  HistoryFilter? historyFilter,
  SyncOutcome syncOutcome = SyncOutcome.completed,
  NotificationSettingsController? notifications,
}) {
  final periodRepository =
      periods ??
      FakePeriodRepository(<SpendingPeriod>[
        testPeriod(id: closedPeriodId, closedAt: DateTime.utc(2026, 7, 31, 18)),
        testPeriod(id: openPeriodId, sequenceNumber: 2),
      ]);
  final loanRepository = loans ?? FakeLoanRepository();
  return <Override>[
    expenseRepositoryProvider.overrideWithValue(repository),
    periodRepositoryProvider.overrideWithValue(periodRepository),
    loanRepositoryProvider.overrideWithValue(loanRepository),
    visibleExpensesProvider.overrideWith(
      (ref) => repository.watchVisibleExpenses(),
    ),
    visiblePeriodsProvider.overrideWith(
      (ref) => periodRepository.watchPeriods(),
    ),
    openPeriodProvider.overrideWith(
      (ref) => periodRepository.watchOpenPeriod(),
    ),
    visibleLoansProvider.overrideWith(
      (ref) => loanRepository.watchVisibleLoans(),
    ),
    if (historyFilter != null)
      historyFilterProvider.overrideWith((ref) => historyFilter),
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
    // The settings tab is built alongside the others inside an IndexedStack, so
    // its debug diagnostics are stubbed too rather than opening a real database.
    syncCursorProvider.overrideWith(
      (ref) => Stream<String?>.value('cursor-42'),
    ),
    syncReportProvider.overrideWith((ref) => const Stream<SyncReport>.empty()),
    manualSyncControllerProvider.overrideWith(
      (ref) => ManualSyncController(
        synchronize: () async => SyncReport(syncOutcome),
      ),
    ),
    apiEnvironmentLabelProvider.overrideWithValue('Test · example.test'),
    // The notification card on that tab otherwise reads the device database and
    // asks Android about the permission, so both answers are stubbed. A test
    // that is about notifications injects a controller instead and lets the real
    // providers derive from it.
    if (notifications == null) ...<Override>[
      systemNotificationsEnabledProvider.overrideWith((ref) async => true),
      householdActivityNotificationsEnabledProvider.overrideWith(
        (ref) => Stream<bool>.value(true),
      ),
    ] else
      notificationSettingsControllerProvider.overrideWithValue(notifications),
  ];
}

Widget _launcher({
  required List<Override> overrides,
  required WidgetBuilder builder,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('launch-form'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: builder),
              ),
              child: const Text('Launch'),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _formLauncher(FakeExpenseRepository repository, {Expense? expense}) {
  return _launcher(
    overrides: <Override>[
      expenseRepositoryProvider.overrideWithValue(repository),
    ],
    builder: (context) => ExpenseFormScreen(
      defaultPayer: HouseholdMember.sumon,
      expense: expense,
    ),
  );
}

Widget _loanFormLauncher(FakeLoanRepository repository, {Loan? loan}) {
  return _launcher(
    overrides: <Override>[loanRepositoryProvider.overrideWithValue(repository)],
    builder: (context) =>
        LoanFormScreen(defaultDebtor: HouseholdMember.sumon, loan: loan),
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
  String? periodId = openPeriodId,
  DateTime? occurredAt,
  String? note,
}) {
  final at = occurredAt ?? DateTime.utc(2026, 8, 10, 12);
  return Expense(
    id: id,
    amountMinor: amountMinor,
    category: category,
    payer: payer,
    occurredAt: at,
    note: note,
    periodId: periodId,
    version: 1,
    updatedAt: at,
    syncState: syncState,
  );
}

SpendingPeriod testPeriod({
  required String id,
  int sequenceNumber = 1,
  DateTime? closedAt,
  int version = 1,
}) {
  return SpendingPeriod(
    id: id,
    sequenceNumber: sequenceNumber,
    startedAt: DateTime.utc(2026, 8, 1),
    closedAt: closedAt,
    version: version,
    updatedAt: DateTime.utc(2026, 8, 1),
    syncState: LocalSyncState.synced,
  );
}

Loan testLoan({
  required String id,
  required int amountMinor,
  HouseholdMember debtor = HouseholdMember.ebrahim,
  DateTime? occurredAt,
  String? note,
  LocalSyncState syncState = LocalSyncState.synced,
}) {
  final at = occurredAt ?? DateTime.utc(2026, 8, 10, 12);
  return Loan(
    id: id,
    debtor: debtor,
    amountMinor: amountMinor,
    occurredAt: at,
    note: note,
    version: 1,
    updatedAt: at,
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
      periodId: normalized.periodId ?? openPeriodId,
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
      periodId: current.periodId,
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
    _mutations.add(LocalMutationEvent(SyncEntityType.expense, id));
  }
}

final class FakePeriodRepository implements PeriodRepository {
  FakePeriodRepository([
    List<SpendingPeriod> initial = const <SpendingPeriod>[],
  ]) : periods = <SpendingPeriod>[...initial];

  final List<SpendingPeriod> periods;
  final StreamController<List<SpendingPeriod>> _changes =
      StreamController<List<SpendingPeriod>>.broadcast();
  final StreamController<LocalMutationEvent> _mutations =
      StreamController<LocalMutationEvent>.broadcast();
  int closeCalls = 0;
  Object? closeError;

  @override
  Stream<LocalMutationEvent> get localMutations => _mutations.stream;

  @override
  Stream<List<SpendingPeriod>> watchPeriods() async* {
    yield List<SpendingPeriod>.unmodifiable(periods);
    yield* _changes.stream;
  }

  @override
  Future<List<SpendingPeriod>> readPeriods() async =>
      List<SpendingPeriod>.unmodifiable(periods);

  @override
  Stream<SpendingPeriod?> watchOpenPeriod() =>
      watchPeriods().map((all) => _openIn(all));

  @override
  Future<SpendingPeriod?> readOpenPeriod() async => _openIn(periods);

  @override
  Future<PeriodRollover> closeAndOpenNext() async {
    closeCalls += 1;
    final error = closeError;
    if (error != null) {
      throw error;
    }
    final current = _openIn(periods);
    if (current == null) {
      throw const NoOpenPeriodException();
    }
    final now = DateTime.utc(2026, 8, 16, 6);
    final closed = SpendingPeriod(
      id: current.id,
      sequenceNumber: current.sequenceNumber,
      startedAt: current.startedAt,
      closedAt: now,
      note: current.note,
      version: current.version,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    final opened = SpendingPeriod(
      id: 'opened-$closeCalls',
      sequenceNumber: current.sequenceNumber + 1,
      startedAt: now,
      version: 0,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    periods[periods.indexOf(current)] = closed;
    periods.add(opened);
    _changes.add(List<SpendingPeriod>.unmodifiable(periods));
    _mutations.add(LocalMutationEvent(SyncEntityType.period, closed.id));
    _mutations.add(LocalMutationEvent(SyncEntityType.period, opened.id));
    return PeriodRollover(closed: closed, opened: opened);
  }

  static SpendingPeriod? _openIn(List<SpendingPeriod> all) {
    for (final period in all) {
      if (period.isOpen) {
        return period;
      }
    }
    return null;
  }
}

final class FakeLoanRepository implements LoanRepository {
  FakeLoanRepository([List<Loan> initial = const <Loan>[]])
    : loans = <Loan>[...initial];

  final List<Loan> loans;
  final StreamController<List<Loan>> _changes =
      StreamController<List<Loan>>.broadcast();
  final StreamController<LocalMutationEvent> _mutations =
      StreamController<LocalMutationEvent>.broadcast();
  int createCalls = 0;
  int editCalls = 0;
  int deleteCalls = 0;

  @override
  Stream<LocalMutationEvent> get localMutations => _mutations.stream;

  @override
  Stream<List<Loan>> watchVisibleLoans() async* {
    yield List<Loan>.unmodifiable(loans);
    yield* _changes.stream;
  }

  @override
  Future<List<Loan>> readVisibleLoans() async => List<Loan>.unmodifiable(loans);

  @override
  Future<Loan> create(LoanDraft draft) async {
    createCalls += 1;
    final normalized = draft.normalized();
    // Mirrors the real repository: the timestamp is stamped here, never asked
    // for on the form.
    final now = DateTime.now().toUtc();
    final loan = Loan(
      id: 'created-$createCalls',
      debtor: normalized.debtor,
      amountMinor: normalized.amountMinor,
      occurredAt: now,
      note: normalized.note,
      version: 0,
      updatedAt: now,
      syncState: LocalSyncState.pending,
    );
    loans.add(loan);
    _emit(loan.id);
    return loan;
  }

  @override
  Future<Loan> edit(String id, LoanDraft draft) async {
    editCalls += 1;
    final index = loans.indexWhere((loan) => loan.id == id);
    if (index < 0) {
      throw LoanNotFoundException(id);
    }
    final normalized = draft.normalized();
    final current = loans[index];
    final updated = Loan(
      id: current.id,
      debtor: normalized.debtor,
      amountMinor: normalized.amountMinor,
      occurredAt: current.occurredAt,
      note: normalized.note,
      version: current.version,
      updatedAt: DateTime.utc(2026, 8, 13),
      syncState: LocalSyncState.pending,
    );
    loans[index] = updated;
    _emit(id);
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls += 1;
    loans.removeWhere((loan) => loan.id == id);
    _emit(id);
  }

  void _emit(String id) {
    _changes.add(List<Loan>.unmodifiable(loans));
    _mutations.add(LocalMutationEvent(SyncEntityType.loan, id));
  }
}
