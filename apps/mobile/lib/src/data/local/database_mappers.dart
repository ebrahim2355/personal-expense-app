import 'package:drift/drift.dart';

import '../../domain/expense.dart';
import '../../domain/loan.dart';
import '../../domain/spending_period.dart';
import '../remote/api_models.dart';
import 'app_database.dart';

Expense expenseFromRow(LocalExpenseRow row) => Expense(
  id: row.id,
  amountMinor: row.amountMinor,
  category: ExpenseCategoryWire.parse(row.category),
  payer: HouseholdMemberWire.parse(row.payer),
  occurredAt: row.occurredAt.toUtc(),
  note: row.note,
  periodId: row.periodId,
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
  periodId: Value<String?>(expense.periodId),
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

SpendingPeriod periodFromRow(LocalPeriodRow row) => SpendingPeriod(
  id: row.id,
  sequenceNumber: row.sequenceNumber,
  startedAt: row.startedAt.toUtc(),
  closedAt: row.closedAt?.toUtc(),
  note: row.note,
  version: row.version,
  updatedAt: row.updatedAt.toUtc(),
  syncState: LocalSyncStateWire.parse(row.syncState),
);

LocalPeriodsCompanion periodCompanion(
  SpendingPeriod period, {
  DateTime? localModifiedAt,
}) => LocalPeriodsCompanion(
  id: Value<String>(period.id),
  sequenceNumber: Value<int>(period.sequenceNumber),
  startedAt: Value<DateTime>(period.startedAt.toUtc()),
  closedAt: Value<DateTime?>(period.closedAt?.toUtc()),
  note: Value<String?>(period.note),
  version: Value<int>(period.version),
  updatedAt: Value<DateTime>(period.updatedAt.toUtc()),
  syncState: Value<String>(period.syncState.storedName),
  localModifiedAt: Value<DateTime>(
    (localModifiedAt ?? period.updatedAt).toUtc(),
  ),
);

SpendingPeriod periodFromDto(
  PeriodDto dto, {
  LocalSyncState syncState = LocalSyncState.synced,
}) => dto.toDomain(syncState: syncState);

Loan loanFromRow(LocalLoanRow row) => Loan(
  id: row.id,
  debtor: HouseholdMemberWire.parse(row.debtor),
  amountMinor: row.amountMinor,
  occurredAt: row.occurredAt.toUtc(),
  note: row.note,
  version: row.version,
  updatedAt: row.updatedAt.toUtc(),
  deletedAt: row.deletedAt?.toUtc(),
  syncState: LocalSyncStateWire.parse(row.syncState),
);

LocalLoansCompanion loanCompanion(Loan loan, {DateTime? localModifiedAt}) =>
    LocalLoansCompanion(
      id: Value<String>(loan.id),
      debtor: Value<String>(loan.debtor.wireName),
      amountMinor: Value<int>(loan.amountMinor),
      occurredAt: Value<DateTime>(loan.occurredAt.toUtc()),
      note: Value<String?>(loan.note),
      version: Value<int>(loan.version),
      updatedAt: Value<DateTime>(loan.updatedAt.toUtc()),
      deletedAt: Value<DateTime?>(loan.deletedAt?.toUtc()),
      syncState: Value<String>(loan.syncState.storedName),
      localModifiedAt: Value<DateTime>(
        (localModifiedAt ?? loan.updatedAt).toUtc(),
      ),
    );

Loan loanFromDto(
  LoanDto dto, {
  LocalSyncState syncState = LocalSyncState.synced,
}) => dto.toDomain(syncState: syncState);
