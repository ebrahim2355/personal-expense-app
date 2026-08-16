-- Adds spending periods, the manual loan ledger, and whole-taka amounts.
--
-- `Expense.periodId` is required, so it is added nullable, backfilled from a
-- generated first period per household, and only then made NOT NULL. The stored
-- `ExpenseChange.snapshot` and `ProcessedMutation.result` JSON documents are
-- rewritten in the same transaction, because both are parsed against the strict
-- schemas that now require `periodId` and whole-taka amounts.

-- CreateEnum
CREATE TYPE "SyncEntityType" AS ENUM ('EXPENSE', 'PERIOD', 'LOAN');

-- CreateTable
CREATE TABLE "SpendingPeriod" (
    "id" UUID NOT NULL,
    "householdId" UUID NOT NULL,
    "sequenceNumber" INTEGER NOT NULL,
    "startedAt" TIMESTAMPTZ(3) NOT NULL,
    "closedAt" TIMESTAMPTZ(3),
    "note" VARCHAR(500),
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastChangeSequence" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "SpendingPeriod_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LoanEntry" (
    "id" UUID NOT NULL,
    "householdId" UUID NOT NULL,
    "debtorId" UUID NOT NULL,
    "amountMinor" BIGINT NOT NULL,
    "occurredAt" TIMESTAMPTZ(3) NOT NULL,
    "note" VARCHAR(500),
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" TIMESTAMPTZ(3),
    "lastChangeSequence" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "LoanEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SpendingPeriod_householdId_startedAt_idx" ON "SpendingPeriod"("householdId", "startedAt");

-- CreateIndex
CREATE INDEX "SpendingPeriod_householdId_lastChangeSequence_idx" ON "SpendingPeriod"("householdId", "lastChangeSequence");

-- CreateIndex
CREATE UNIQUE INDEX "SpendingPeriod_householdId_id_key" ON "SpendingPeriod"("householdId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "SpendingPeriod_householdId_sequenceNumber_key" ON "SpendingPeriod"("householdId", "sequenceNumber");

-- CreateIndex
CREATE INDEX "LoanEntry_householdId_occurredAt_idx" ON "LoanEntry"("householdId", "occurredAt");

-- CreateIndex
CREATE INDEX "LoanEntry_householdId_lastChangeSequence_idx" ON "LoanEntry"("householdId", "lastChangeSequence");

-- CreateIndex
CREATE INDEX "LoanEntry_householdId_debtorId_idx" ON "LoanEntry"("householdId", "debtorId");

-- AddForeignKey
ALTER TABLE "SpendingPeriod" ADD CONSTRAINT "SpendingPeriod_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoanEntry" ADD CONSTRAINT "LoanEntry_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoanEntry" ADD CONSTRAINT "LoanEntry_householdId_debtorId_fkey" FOREIGN KEY ("householdId", "debtorId") REFERENCES "Member"("householdId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AlterTable
ALTER TABLE "ExpenseChange" ADD COLUMN     "entityType" "SyncEntityType" NOT NULL DEFAULT 'EXPENSE';

-- AlterTable
ALTER TABLE "ProcessedMutation" ADD COLUMN     "entityType" "SyncEntityType" NOT NULL DEFAULT 'EXPENSE';

-- AlterTable
ALTER TABLE "Expense" ADD COLUMN     "periodId" UUID;

-- Backfill: give every household one open period covering its existing history.
INSERT INTO "SpendingPeriod" (
    "id",
    "householdId",
    "sequenceNumber",
    "startedAt",
    "closedAt",
    "note",
    "version",
    "createdAt",
    "updatedAt",
    "lastChangeSequence"
)
SELECT
    gen_random_uuid(),
    "Household"."id",
    1,
    COALESCE(
        (
            SELECT MIN("Expense"."occurredAt")
            FROM "Expense"
            WHERE "Expense"."householdId" = "Household"."id"
        ),
        CURRENT_TIMESTAMP
    ),
    NULL,
    NULL,
    1,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0
FROM "Household";

-- Backfill: every existing expense belongs to its household's first period.
UPDATE "Expense"
SET "periodId" = "SpendingPeriod"."id"
FROM "SpendingPeriod"
WHERE "SpendingPeriod"."householdId" = "Expense"."householdId"
  AND "SpendingPeriod"."sequenceNumber" = 1;

-- Backfill: round any sub-taka amount to the nearest whole taka, minimum 1 taka.
UPDATE "Expense"
SET "amountMinor" = GREATEST(100, ROUND("amountMinor" / 100.0) * 100)
WHERE "amountMinor" % 100 <> 0;

-- Backfill: stored expense snapshots must satisfy the new strict shape.
UPDATE "ExpenseChange"
SET "snapshot" = jsonb_set(
        jsonb_set(
            "ExpenseChange"."snapshot",
            '{periodId}',
            to_jsonb("SpendingPeriod"."id"::text),
            true
        ),
        '{amountMinor}',
        to_jsonb(
            GREATEST(
                100,
                ROUND(("ExpenseChange"."snapshot" ->> 'amountMinor')::numeric / 100.0) * 100
            )::bigint
        ),
        true
    )
FROM "SpendingPeriod"
WHERE "SpendingPeriod"."householdId" = "ExpenseChange"."householdId"
  AND "SpendingPeriod"."sequenceNumber" = 1
  AND "ExpenseChange"."snapshot" ->> 'amountMinor' IS NOT NULL;

-- Backfill: stored mutation receipts must replay against the new result shape.
UPDATE "ProcessedMutation"
SET "result" = jsonb_set(
        jsonb_set(
            jsonb_set(
                "ProcessedMutation"."result",
                '{entityType}',
                '"EXPENSE"'::jsonb,
                true
            ),
            '{expense,periodId}',
            to_jsonb("SpendingPeriod"."id"::text),
            true
        ),
        '{expense,amountMinor}',
        to_jsonb(
            GREATEST(
                100,
                ROUND(("ProcessedMutation"."result" #>> '{expense,amountMinor}')::numeric / 100.0) * 100
            )::bigint
        ),
        true
    )
FROM "SpendingPeriod"
WHERE "SpendingPeriod"."householdId" = "ProcessedMutation"."householdId"
  AND "SpendingPeriod"."sequenceNumber" = 1
  AND "ProcessedMutation"."result" -> 'expense' IS NOT NULL;

-- AlterTable
ALTER TABLE "Expense" ALTER COLUMN "periodId" SET NOT NULL;

-- CreateIndex
CREATE INDEX "Expense_householdId_periodId_idx" ON "Expense"("householdId", "periodId");

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_householdId_periodId_fkey" FOREIGN KEY ("householdId", "periodId") REFERENCES "SpendingPeriod"("householdId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Domain constraints. A household may have at most one open period, so closing
-- and reopening cannot leave two periods accepting new expenses.
CREATE UNIQUE INDEX "SpendingPeriod_single_open_per_household_key"
    ON "SpendingPeriod"("householdId")
    WHERE "closedAt" IS NULL;

ALTER TABLE "Expense"
  ADD CONSTRAINT "Expense_amountMinor_whole_taka_check"
    CHECK ("amountMinor" % 100 = 0);

ALTER TABLE "SpendingPeriod"
  ADD CONSTRAINT "SpendingPeriod_sequenceNumber_positive_check"
    CHECK ("sequenceNumber" >= 1),
  ADD CONSTRAINT "SpendingPeriod_version_positive_check"
    CHECK ("version" >= 1),
  ADD CONSTRAINT "SpendingPeriod_lastChangeSequence_nonnegative_check"
    CHECK ("lastChangeSequence" >= 0),
  ADD CONSTRAINT "SpendingPeriod_closedAt_not_before_startedAt_check"
    CHECK ("closedAt" IS NULL OR "closedAt" >= "startedAt");

ALTER TABLE "LoanEntry"
  ADD CONSTRAINT "LoanEntry_amountMinor_range_check"
    CHECK ("amountMinor" BETWEEN 100 AND 99999999999),
  ADD CONSTRAINT "LoanEntry_amountMinor_whole_taka_check"
    CHECK ("amountMinor" % 100 = 0),
  ADD CONSTRAINT "LoanEntry_version_positive_check"
    CHECK ("version" >= 1),
  ADD CONSTRAINT "LoanEntry_lastChangeSequence_nonnegative_check"
    CHECK ("lastChangeSequence" >= 0);
