import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/loan.dart';
import 'package:houseexpenses/src/domain/money.dart';

Expense expense({
  required String id,
  required int amountMinor,
  required HouseholdMember payer,
  DateTime? deletedAt,
}) => Expense(
  id: id,
  amountMinor: amountMinor,
  category: ExpenseCategory.other,
  payer: payer,
  occurredAt: DateTime.utc(2026, 8, 13),
  version: 1,
  updatedAt: DateTime.utc(2026, 8, 13),
  deletedAt: deletedAt,
  syncState: LocalSyncState.synced,
);

Loan loan({
  required String id,
  required int amountMinor,
  required HouseholdMember debtor,
  DateTime? deletedAt,
}) => Loan(
  id: id,
  debtor: debtor,
  amountMinor: amountMinor,
  occurredAt: DateTime.utc(2026, 8, 13),
  version: 1,
  updatedAt: DateTime.utc(2026, 8, 13),
  deletedAt: deletedAt,
  syncState: LocalSyncState.synced,
);

void main() {
  group('BDT parsing', () {
    test('accepts whole taka and scales them to poisha', () {
      expect(parseBdtToMinor('1'), 100);
      expect(parseBdtToMinor('800'), 80000);
      expect(parseBdtToMinor(' 1200 '), 120000);
      expect(parseBdtToMinor('999999999'), maximumAmountMinor);
    });

    test('rejects any decimal point, because taka are whole', () {
      for (final value in <String>[
        '1.2',
        '1.20',
        '1.00',
        '0.01',
        '800.00',
        '1.',
        '.50',
      ]) {
        expect(
          () => parseBdtToMinor(value),
          throwsA(isA<AmountValidationException>()),
          reason: value,
        );
      }
    });

    test('rejects invalid, signed, exponential, zero, and overflow input', () {
      for (final value in <String>[
        '',
        '0',
        '-1',
        '+1',
        '1e2',
        'NaN',
        'Infinity',
        '1,000',
        '1000000000',
      ]) {
        expect(
          () => parseBdtToMinor(value),
          throwsA(isA<AmountValidationException>()),
          reason: value,
        );
      }
    });
  });

  test('formats BDT with grouping and no decimal point', () {
    expect(formatBdt(0), '৳0');
    expect(formatBdt(100), '৳1');
    expect(formatBdt(40000), '৳400');
    expect(formatBdt(120000), '৳1,200');
    expect(formatBdt(maximumAmountMinor), '৳999,999,999');
    expect(formatBdtInput(40000), '400');
  });

  test('payer receives the odd-taka remainder', () {
    final sumon = splitExpense(10100, HouseholdMember.sumon);
    expect(sumon.sumonMinor, 5100);
    expect(sumon.ebrahimMinor, 5000);

    final ebrahim = splitExpense(10100, HouseholdMember.ebrahim);
    expect(ebrahim.sumonMinor, 5000);
    expect(ebrahim.ebrahimMinor, 5100);
  });

  test('splitting refuses an amount that is not whole taka', () {
    expect(
      () => splitExpense(10001, HouseholdMember.sumon),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('summarizes the ৳1,000 and ৳200 acceptance example', () {
    final summary = summarizeExpenses(<Expense>[
      expense(id: 'sumon', amountMinor: 100000, payer: HouseholdMember.sumon),
      expense(
        id: 'ebrahim',
        amountMinor: 20000,
        payer: HouseholdMember.ebrahim,
      ),
    ]);

    expect(summary.totalMinor, 120000);
    expect(summary.sumonPaidMinor, 100000);
    expect(summary.ebrahimPaidMinor, 20000);
    expect(summary.sumonAllocatedMinor, 60000);
    expect(summary.ebrahimAllocatedMinor, 60000);
    expect(summary.settlementText, 'Ebrahim owes Sumon ৳400');
  });

  test('summarizes the odd-taka acceptance example per expense', () {
    final summary = summarizeExpenses(<Expense>[
      expense(id: 'odd', amountMinor: 10100, payer: HouseholdMember.sumon),
    ]);

    expect(summary.sumonAllocatedMinor, 5100);
    expect(summary.ebrahimAllocatedMinor, 5000);
    expect(summary.settlementText, 'Ebrahim owes Sumon ৳50');
  });

  test('equal paid and allocated totals are all settled', () {
    final summary = summarizeExpenses(<Expense>[
      expense(id: 'one', amountMinor: 20000, payer: HouseholdMember.sumon),
      expense(id: 'two', amountMinor: 20000, payer: HouseholdMember.ebrahim),
      expense(
        id: 'deleted',
        amountMinor: 99900,
        payer: HouseholdMember.sumon,
        deletedAt: DateTime.utc(2026, 8, 13),
      ),
    ]);

    expect(summary.totalMinor, 40000);
    expect(summary.sumonBalanceMinor, 0);
    expect(summary.ebrahimBalanceMinor, 0);
    expect(summary.settlementText, 'All settled');
  });

  group('lending ledger', () {
    test('nets the manual entries in each direction', () {
      final summary = summarizeLoans(<Loan>[
        loan(id: 'a', amountMinor: 50000, debtor: HouseholdMember.ebrahim),
        loan(id: 'b', amountMinor: 20000, debtor: HouseholdMember.ebrahim),
        loan(id: 'c', amountMinor: 30000, debtor: HouseholdMember.sumon),
        loan(
          id: 'gone',
          amountMinor: 90000,
          debtor: HouseholdMember.sumon,
          deletedAt: DateTime.utc(2026, 8, 14),
        ),
      ]);

      expect(summary.ebrahimOwesMinor, 70000);
      expect(summary.sumonOwesMinor, 30000);
      expect(summary.netMinor, 40000);
      expect(summary.netText, 'Ebrahim owes Sumon ৳400');
    });

    test('reads the other way round when Sumon is behind', () {
      final summary = summarizeLoans(<Loan>[
        loan(id: 'a', amountMinor: 60000, debtor: HouseholdMember.sumon),
        loan(id: 'b', amountMinor: 10000, debtor: HouseholdMember.ebrahim),
      ]);

      expect(summary.netMinor, -50000);
      expect(summary.netText, 'Sumon owes Ebrahim ৳500');
    });

    test('an empty or balanced ledger has nothing outstanding', () {
      expect(summarizeLoans(const <Loan>[]).netText, 'No outstanding loans');
      expect(
        summarizeLoans(<Loan>[
          loan(id: 'a', amountMinor: 25000, debtor: HouseholdMember.sumon),
          loan(id: 'b', amountMinor: 25000, debtor: HouseholdMember.ebrahim),
        ]).netText,
        'No outstanding loans',
      );
    });

    test('an entry names its own creditor and reads as one line', () {
      final entry = loan(
        id: 'a',
        amountMinor: 50000,
        debtor: HouseholdMember.ebrahim,
      );
      expect(entry.creditor, HouseholdMember.sumon);
      expect(entry.summaryText, 'Ebrahim owes Sumon ৳500');
    });

    test('a draft keeps whole taka and trims the note away when blank', () {
      final normalized = const LoanDraft(
        debtor: HouseholdMember.sumon,
        amountMinor: 50000,
        note: '   ',
      ).normalized();
      expect(normalized.note, isNull);

      expect(
        () => const LoanDraft(
          debtor: HouseholdMember.sumon,
          amountMinor: 50001,
        ).normalized(),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
