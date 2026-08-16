import 'expense.dart';

final class AmountValidationException implements FormatException {
  const AmountValidationException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => message;
}

/// Matches a bare whole-taka amount: digits only, no separator and no decimal
/// point. Nine digits is the widest amount the poisha ceiling admits.
final RegExp _wholeTakaPattern = RegExp(r'^\d{1,9}$');

int parseBdtToMinor(String input) {
  final value = input.trim();
  if (!_wholeTakaPattern.hasMatch(value)) {
    throw const AmountValidationException(
      'Enter a whole taka amount using digits only.',
    );
  }

  final taka = int.parse(value);
  final amountMinor = taka * poishaPerTaka;
  if (amountMinor < minimumAmountMinor || amountMinor > maximumAmountMinor) {
    throw const AmountValidationException(
      'Amount must be at least ৳1 and within the allowed maximum.',
    );
  }
  return amountMinor;
}

String formatBdt(int amountMinor) {
  if (amountMinor < 0) {
    throw ArgumentError.value(
      amountMinor,
      'amountMinor',
      'Must not be negative.',
    );
  }
  final whole = (amountMinor ~/ poishaPerTaka).toString();
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index += 1) {
    if (index > 0 && (whole.length - index) % 3 == 0) {
      grouped.write(',');
    }
    grouped.write(whole[index]);
  }
  return '৳$grouped';
}

String formatBdtInput(int amountMinor) {
  if (amountMinor < 0) {
    throw ArgumentError.value(
      amountMinor,
      'amountMinor',
      'Must not be negative.',
    );
  }
  return (amountMinor ~/ poishaPerTaka).toString();
}

final class ExpenseAllocation {
  const ExpenseAllocation({
    required this.sumonMinor,
    required this.ebrahimMinor,
  });

  final int sumonMinor;
  final int ebrahimMinor;
}

/// Splits a shared expense in half at whole-taka precision, mirroring
/// `splitAmountMinor` in `apps/api/src/domain/money.ts`. An odd number of taka
/// cannot be halved evenly, so the extra taka goes to the payer: the two shares
/// still sum exactly to the total, and the asymmetry shows up only in the
/// settlement figure.
ExpenseAllocation splitExpense(int amountMinor, HouseholdMember payer) {
  if (amountMinor < minimumAmountMinor ||
      amountMinor > maximumAmountMinor ||
      amountMinor % poishaPerTaka != 0) {
    throw ArgumentError.value(
      amountMinor,
      'amountMinor',
      'Must be a whole taka amount in poisha.',
    );
  }
  final taka = amountMinor ~/ poishaPerTaka;
  final otherShare = (taka ~/ 2) * poishaPerTaka;
  final payerShare = (taka ~/ 2 + taka % 2) * poishaPerTaka;
  return switch (payer) {
    HouseholdMember.sumon => ExpenseAllocation(
      sumonMinor: payerShare,
      ebrahimMinor: otherShare,
    ),
    HouseholdMember.ebrahim => ExpenseAllocation(
      sumonMinor: otherShare,
      ebrahimMinor: payerShare,
    ),
  };
}

final class ExpenseSummary {
  const ExpenseSummary({
    required this.totalMinor,
    required this.sumonPaidMinor,
    required this.ebrahimPaidMinor,
    required this.sumonAllocatedMinor,
    required this.ebrahimAllocatedMinor,
  });

  static const ExpenseSummary zero = ExpenseSummary(
    totalMinor: 0,
    sumonPaidMinor: 0,
    ebrahimPaidMinor: 0,
    sumonAllocatedMinor: 0,
    ebrahimAllocatedMinor: 0,
  );

  final int totalMinor;
  final int sumonPaidMinor;
  final int ebrahimPaidMinor;
  final int sumonAllocatedMinor;
  final int ebrahimAllocatedMinor;

  int get sumonBalanceMinor => sumonPaidMinor - sumonAllocatedMinor;
  int get ebrahimBalanceMinor => ebrahimPaidMinor - ebrahimAllocatedMinor;

  String get settlementText {
    if (sumonBalanceMinor > 0) {
      return 'Ebrahim owes Sumon ${formatBdt(sumonBalanceMinor)}';
    }
    if (sumonBalanceMinor < 0) {
      return 'Sumon owes Ebrahim ${formatBdt(-sumonBalanceMinor)}';
    }
    return 'All settled';
  }
}

ExpenseSummary summarizeExpenses(Iterable<Expense> expenses) {
  var total = 0;
  var sumonPaid = 0;
  var ebrahimPaid = 0;
  var sumonAllocated = 0;
  var ebrahimAllocated = 0;

  for (final expense in expenses) {
    if (expense.isDeleted) {
      continue;
    }
    total += expense.amountMinor;
    switch (expense.payer) {
      case HouseholdMember.sumon:
        sumonPaid += expense.amountMinor;
      case HouseholdMember.ebrahim:
        ebrahimPaid += expense.amountMinor;
    }
    final allocation = splitExpense(expense.amountMinor, expense.payer);
    sumonAllocated += allocation.sumonMinor;
    ebrahimAllocated += allocation.ebrahimMinor;
  }

  return ExpenseSummary(
    totalMinor: total,
    sumonPaidMinor: sumonPaid,
    ebrahimPaidMinor: ebrahimPaid,
    sumonAllocatedMinor: sumonAllocated,
    ebrahimAllocatedMinor: ebrahimAllocated,
  );
}
