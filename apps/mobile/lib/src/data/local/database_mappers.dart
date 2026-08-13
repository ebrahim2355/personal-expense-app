import 'package:drift/drift.dart';

import '../../domain/expense.dart';
import '../remote/api_models.dart';
import 'app_database.dart';

Expense expenseFromRow(LocalExpenseRow row) => Expense(
  id: row.id,
  amountMinor: row.amountMinor,
  category: ExpenseCategoryWire.parse(row.category),
  payer: HouseholdMemberWire.parse(row.payer),
  occurredAt: row.occurredAt.toUtc(),
  note: row.note,
  version: row.version,
  updatedAt: row.updatedAt.toUtc(),
  deletedAt: row.deletedAt?.toUtc(),
  syncState: LocalSyncStateWire.parse(row.syncState),
);

LocalExpensesCompanion expenseCompanion(
  Expense expense, {
  DateTime? localModifiedAt,
}) => LocalExpensesCompanion(
  id: Value<String>(expense.id),
  amountMinor: Value<int>(expense.amountMinor),
  category: Value<String>(expense.category.wireName),
  payer: Value<String>(expense.payer.wireName),
  occurredAt: Value<DateTime>(expense.occurredAt.toUtc()),
  note: Value<String?>(expense.note),
  version: Value<int>(expense.version),
  updatedAt: Value<DateTime>(expense.updatedAt.toUtc()),
  deletedAt: Value<DateTime?>(expense.deletedAt?.toUtc()),
  syncState: Value<String>(expense.syncState.storedName),
  localModifiedAt: Value<DateTime>(
    (localModifiedAt ?? expense.updatedAt).toUtc(),
  ),
);

Expense expenseFromDto(
  ExpenseDto dto, {
  LocalSyncState syncState = LocalSyncState.synced,
}) => dto.toDomain(syncState: syncState);
