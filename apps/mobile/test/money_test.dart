import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/domain/expense.dart';
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

void main() {
  group('BDT parsing', () {
    test('converts ordinary decimal strings without floating point', () {
      expect(parseBdtToMinor('1'), 100);
      expect(parseBdtToMinor('1.2'), 120);
      expect(parseBdtToMinor('1.20'), 120);
      expect(parseBdtToMinor('0.01'), 1);
      expect(parseBdtToMinor('999999999.99'), maximumAmountMinor);
    });

    test('rejects invalid, signed, exponential, zero, and overflow input', () {
      for (final value in <String>[
        '',
        '0',
        '0.00',
        '-1',
        '+1',
        '1e2',
        'NaN',
        'Infinity',
        '1.001',
        '1.',
        '.50',
        '1,000',
        '1000000000.00',
      ]) {
        expect(
          () => parseBdtToMinor(value),
          throwsA(isA<AmountValidationException>()),
          reason: value,
        );
      }
    });
  });

  test('formats BDT deterministically with grouping and two decimals', () {
    expect(formatBdt(0), '৳0.00');
    expect(formatBdt(1), '৳0.01');
    expect(formatBdt(40000), '৳400.00');
    expect(formatBdt(120000), '৳1,200.00');
    expect(formatBdtInput(10001), '100.01');
  });

  test('payer receives the odd-poisha remainder', () {
    final sumon = splitExpense(10001, HouseholdMember.sumon);
    expect(sumon.sumonMinor, 5001);
    expect(sumon.ebrahimMinor, 5000);

    final ebrahim = splitExpense(101, HouseholdMember.ebrahim);
    expect(ebrahim.sumonMinor, 50);
    expect(ebrahim.ebrahimMinor, 51);
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
    expect(summary.settlementText, 'Ebrahim owes Sumon ৳400.00');
  });

  test('summarizes the odd-poisha acceptance example per expense', () {
    final summary = summarizeExpenses(<Expense>[
      expense(id: 'odd', amountMinor: 10001, payer: HouseholdMember.sumon),
    ]);

    expect(summary.sumonAllocatedMinor, 5001);
    expect(summary.ebrahimAllocatedMinor, 5000);
    expect(summary.settlementText, 'Ebrahim owes Sumon ৳50.00');
  });

  test('equal paid and allocated totals are all settled', () {
    final summary = summarizeExpenses(<Expense>[
      expense(id: 'one', amountMinor: 20000, payer: HouseholdMember.sumon),
      expense(id: 'two', amountMinor: 20000, payer: HouseholdMember.ebrahim),
      expense(
        id: 'deleted',
        amountMinor: 99999,
        payer: HouseholdMember.sumon,
        deletedAt: DateTime.utc(2026, 8, 13),
      ),
    ]);

    expect(summary.totalMinor, 40000);
    expect(summary.sumonBalanceMinor, 0);
    expect(summary.ebrahimBalanceMinor, 0);
    expect(summary.settlementText, 'All settled');
  });
}
