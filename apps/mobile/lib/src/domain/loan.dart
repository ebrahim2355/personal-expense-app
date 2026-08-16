import 'expense.dart';
import 'money.dart';

/// One hand-recorded loan between the two members.
///
/// Loans are entirely manual and deliberately separate from shared expenses:
/// they never move the expense settlement figure. The debtor owes the amount and
/// the other member is the creditor.
final class LoanDraft {
  const LoanDraft({required this.debtor, required this.amountMinor, this.note});

  final HouseholdMember debtor;
  final int amountMinor;
  final String? note;

  LoanDraft normalized() {
    if (amountMinor < minimumAmountMinor ||
        amountMinor > maximumAmountMinor ||
        amountMinor % poishaPerTaka != 0) {
      throw ArgumentError.value(
        amountMinor,
        'amountMinor',
        'Must be a whole number of taka from $minimumAmountMinor to '
            '$maximumAmountMinor poisha.',
      );
    }
    final normalizedNote = note?.trim();
    if (normalizedNote != null &&
        normalizedNote.runes.length > maximumNoteCodePoints) {
      throw ArgumentError.value(
        note,
        'note',
        'Must not exceed $maximumNoteCodePoints Unicode code points.',
      );
    }
    return LoanDraft(
      debtor: debtor,
      amountMinor: amountMinor,
      note: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
    );
  }

  /// The draft carries no timestamp of its own: `occurredAt` is stamped by the
  /// repository, which is also what keeps it read-only on the form.
  Map<String, Object?> toWireJson({required DateTime occurredAt}) =>
      <String, Object?>{
        'debtor': debtor.wireName,
        'amountMinor': amountMinor,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'note': note,
      };
}

final class Loan {
  const Loan({
    required this.id,
    required this.debtor,
    required this.amountMinor,
    required this.occurredAt,
    required this.version,
    required this.updatedAt,
    required this.syncState,
    this.note,
    this.deletedAt,
  });

  final String id;
  final HouseholdMember debtor;
  final int amountMinor;
  final DateTime occurredAt;
  final String? note;
  final int version;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final LocalSyncState syncState;

  bool get isDeleted => deletedAt != null;

  /// The member owed the money, which is simply the other one.
  HouseholdMember get creditor => switch (debtor) {
    HouseholdMember.sumon => HouseholdMember.ebrahim,
    HouseholdMember.ebrahim => HouseholdMember.sumon,
  };

  String get summaryText =>
      '${debtor.displayName} owes ${creditor.displayName} '
      '${formatBdt(amountMinor)}';

  LoanDraft get draft =>
      LoanDraft(debtor: debtor, amountMinor: amountMinor, note: note);
}

final class LoanSummary {
  const LoanSummary({
    required this.ebrahimOwesMinor,
    required this.sumonOwesMinor,
  });

  static const LoanSummary zero = LoanSummary(
    ebrahimOwesMinor: 0,
    sumonOwesMinor: 0,
  );

  /// Total of the entries where Ebrahim is the debtor.
  final int ebrahimOwesMinor;

  /// Total of the entries where Sumon is the debtor.
  final int sumonOwesMinor;

  /// Positive when Ebrahim is behind, negative when Sumon is.
  int get netMinor => ebrahimOwesMinor - sumonOwesMinor;

  /// Mirrors `ExpenseSummary.settlementText` so both figures read alike, but is
  /// computed only from manual loan entries.
  String get netText {
    if (netMinor > 0) {
      return 'Ebrahim owes Sumon ${formatBdt(netMinor)}';
    }
    if (netMinor < 0) {
      return 'Sumon owes Ebrahim ${formatBdt(-netMinor)}';
    }
    return 'No outstanding loans';
  }
}

LoanSummary summarizeLoans(Iterable<Loan> loans) {
  var ebrahimOwes = 0;
  var sumonOwes = 0;

  for (final loan in loans) {
    if (loan.isDeleted) {
      continue;
    }
    switch (loan.debtor) {
      case HouseholdMember.ebrahim:
        ebrahimOwes += loan.amountMinor;
      case HouseholdMember.sumon:
        sumonOwes += loan.amountMinor;
    }
  }

  return LoanSummary(ebrahimOwesMinor: ebrahimOwes, sumonOwesMinor: sumonOwes);
}
