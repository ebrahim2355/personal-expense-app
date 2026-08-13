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

int parseBdtToMinor(String input) {
  final value = input.trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
  if (match == null) {
    throw const AmountValidationException(
      'Enter a positive BDT amount with at most two decimal places.',
    );
  }

  final whole = int.tryParse(match.group(1)!);
  final fractionText = match.group(2) ?? '';
  final fraction = fractionText.isEmpty
      ? 0
      : int.parse(fractionText.padRight(2, '0'));
  if (whole == null || whole > maximumAmountMinor ~/ 100) {
    throw const AmountValidationException(
      'Amount is above the allowed maximum.',
    );
  }
  final amountMinor = whole * 100 + fraction;
  if (amountMinor < 1 || amountMinor > maximumAmountMinor) {
    throw const AmountValidationException(
      'Amount must be at least ৳0.01 and within the allowed maximum.',
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
  final whole = (amountMinor ~/ 100).toString();
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index += 1) {
    if (index > 0 && (whole.length - index) % 3 == 0) {
      grouped.write(',');
    }
    grouped.write(whole[index]);
  }
  final fraction = (amountMinor % 100).toString().padLeft(2, '0');
  return '৳$grouped.$fraction';
}

String formatBdtInput(int amountMinor) {
  if (amountMinor < 0) {
    throw ArgumentError.value(
      amountMinor,
      'amountMinor',
      'Must not be negative.',
    );
  }
  final whole = amountMinor ~/ 100;
  final fraction = (amountMinor % 100).toString().padLeft(2, '0');
  return '$whole.$fraction';
}

final class ExpenseAllocation {
  const ExpenseAllocation({
    required this.sumonMinor,
    required this.ebrahimMinor,
  });

  final int sumonMinor;
  final int ebrahimMinor;
}

ExpenseAllocation splitExpense(int amountMinor, HouseholdMember payer) {
  if (amountMinor < 1 || amountMinor > maximumAmountMinor) {
    throw ArgumentError.value(
      amountMinor,
      'amountMinor',
      'Outside valid range.',
    );
  }
  final lowerHalf = amountMinor ~/ 2;
  final payerShare = lowerHalf + amountMinor % 2;
  return switch (payer) {
    HouseholdMember.sumon => ExpenseAllocation(
      sumonMinor: payerShare,
      ebrahimMinor: lowerHalf,
    ),
    HouseholdMember.ebrahim => ExpenseAllocation(
      sumonMinor: lowerHalf,
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
