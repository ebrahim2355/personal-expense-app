/// Money is stored as poisha, but only whole taka are ever accepted, so every
/// amount is a multiple of [poishaPerTaka]. The maximum is the largest whole
/// taka amount inside the API's `99_999_999_999` poisha ceiling.
const int poishaPerTaka = 100;
const int minimumAmountMinor = poishaPerTaka;
const int maximumAmountMinor = 99999999900;
const int maximumNoteCodePoints = 500;

enum HouseholdMember { sumon, ebrahim }

extension HouseholdMemberWire on HouseholdMember {
  String get wireName => switch (this) {
    HouseholdMember.sumon => 'SUMON',
    HouseholdMember.ebrahim => 'EBRAHIM',
  };

  String get displayName => switch (this) {
    HouseholdMember.sumon => 'Sumon',
    HouseholdMember.ebrahim => 'Ebrahim',
  };

  static HouseholdMember parse(String value) => switch (value) {
    'SUMON' => HouseholdMember.sumon,
    'EBRAHIM' => HouseholdMember.ebrahim,
    _ => throw FormatException('Unknown household member: $value'),
  };
}

enum ExpenseCategory {
  groceries,
  utilities,
  transport,
  household,
  medicine,
  other,
}

extension ExpenseCategoryWire on ExpenseCategory {
  String get wireName => switch (this) {
    ExpenseCategory.groceries => 'GROCERIES',
    ExpenseCategory.utilities => 'UTILITIES',
    ExpenseCategory.transport => 'TRANSPORT',
    ExpenseCategory.household => 'HOUSEHOLD',
    ExpenseCategory.medicine => 'MEDICINE',
    ExpenseCategory.other => 'OTHER',
  };

  String get displayName => switch (this) {
    ExpenseCategory.groceries => 'Groceries',
    ExpenseCategory.utilities => 'Utilities',
    ExpenseCategory.transport => 'Transport',
    ExpenseCategory.household => 'Household',
    ExpenseCategory.medicine => 'Medicine',
    ExpenseCategory.other => 'Other',
  };

  static ExpenseCategory parse(String value) => switch (value) {
    'GROCERIES' => ExpenseCategory.groceries,
    'UTILITIES' => ExpenseCategory.utilities,
    'TRANSPORT' => ExpenseCategory.transport,
    'HOUSEHOLD' => ExpenseCategory.household,
    'MEDICINE' => ExpenseCategory.medicine,
    'OTHER' => ExpenseCategory.other,
    _ => throw FormatException('Unknown expense category: $value'),
  };
}

enum LocalSyncState { synced, pending, needsAttention }

extension LocalSyncStateWire on LocalSyncState {
  String get storedName => switch (this) {
    LocalSyncState.synced => 'SYNCED',
    LocalSyncState.pending => 'PENDING',
    LocalSyncState.needsAttention => 'NEEDS_ATTENTION',
  };

  static LocalSyncState parse(String value) => switch (value) {
    'SYNCED' => LocalSyncState.synced,
    'PENDING' => LocalSyncState.pending,
    'NEEDS_ATTENTION' => LocalSyncState.needsAttention,
    _ => throw FormatException('Unknown local sync state: $value'),
  };
}

final class ExpenseDraft {
  const ExpenseDraft({
    required this.amountMinor,
    required this.category,
    required this.payer,
    required this.occurredAt,
    this.note,
    this.periodId,
  });

  final int amountMinor;
  final ExpenseCategory category;
  final HouseholdMember payer;
  final DateTime occurredAt;
  final String? note;

  /// The spending period this expense belongs to, or null when the device has
  /// not learned one yet. A null period leaves the choice to the server, which
  /// files the expense into whichever period is open when the mutation lands.
  final String? periodId;

  ExpenseDraft normalized() {
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
    if (!occurredAt.isUtc) {
      throw ArgumentError.value(
        occurredAt,
        'occurredAt',
        'Must be a UTC instant.',
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
    return ExpenseDraft(
      amountMinor: amountMinor,
      category: category,
      payer: payer,
      occurredAt: occurredAt,
      note: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
      periodId: periodId,
    );
  }

  ExpenseDraft withPeriodId(String? value) => ExpenseDraft(
    amountMinor: amountMinor,
    category: category,
    payer: payer,
    occurredAt: occurredAt,
    note: note,
    periodId: value,
  );

  Map<String, Object?> toWireJson() => <String, Object?>{
    'amountMinor': amountMinor,
    'category': category.wireName,
    'payer': payer.wireName,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'note': note,
    // Omitted rather than sent as null: the contract treats an absent periodId
    // as "file this into the open period", and rejects an explicit null.
    if (periodId != null) 'periodId': periodId,
  };
}

final class Expense {
  const Expense({
    required this.id,
    required this.amountMinor,
    required this.category,
    required this.payer,
    required this.occurredAt,
    required this.version,
    required this.updatedAt,
    required this.syncState,
    this.note,
    this.periodId,
    this.deletedAt,
  });

  final String id;
  final int amountMinor;
  final ExpenseCategory category;
  final HouseholdMember payer;
  final DateTime occurredAt;
  final String? note;
  final String? periodId;
  final int version;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final LocalSyncState syncState;

  bool get isDeleted => deletedAt != null;

  ExpenseDraft get draft => ExpenseDraft(
    amountMinor: amountMinor,
    category: category,
    payer: payer,
    occurredAt: occurredAt,
    note: note,
    periodId: periodId,
  );
}
