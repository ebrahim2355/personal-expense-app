-- CreateEnum
CREATE TYPE "MemberKey" AS ENUM ('SUMON', 'EBRAHIM');

-- CreateEnum
CREATE TYPE "ExpenseCategory" AS ENUM ('GROCERIES', 'UTILITIES', 'TRANSPORT', 'HOUSEHOLD', 'MEDICINE', 'OTHER');

-- CreateEnum
CREATE TYPE "MutationOperation" AS ENUM ('CREATE', 'UPDATE', 'DELETE');

-- CreateEnum
CREATE TYPE "ChangeOperation" AS ENUM ('CREATED', 'UPDATED', 'DELETED');

-- CreateTable
CREATE TABLE "Household" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "slug" VARCHAR(64) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Household_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Member" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "householdId" UUID NOT NULL,
    "key" "MemberKey" NOT NULL,
    "displayName" VARCHAR(50) NOT NULL,
    "pinHash" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "disabledAt" TIMESTAMPTZ(3),

    CONSTRAINT "Member_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefreshToken" (
    "id" UUID NOT NULL,
    "memberId" UUID NOT NULL,
    "familyId" UUID NOT NULL,
    "tokenHash" CHAR(64) NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMPTZ(3) NOT NULL,
    "lastUsedAt" TIMESTAMPTZ(3),
    "revokedAt" TIMESTAMPTZ(3),
    "replacedByTokenId" UUID,

    CONSTRAINT "RefreshToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Expense" (
    "id" UUID NOT NULL,
    "householdId" UUID NOT NULL,
    "amountMinor" BIGINT NOT NULL,
    "category" "ExpenseCategory" NOT NULL,
    "payerId" UUID NOT NULL,
    "occurredAt" TIMESTAMPTZ(3) NOT NULL,
    "note" VARCHAR(500),
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" TIMESTAMPTZ(3),
    "lastChangeSequence" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "Expense_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProcessedMutation" (
    "mutationId" UUID NOT NULL,
    "householdId" UUID NOT NULL,
    "memberId" UUID NOT NULL,
    "entityId" UUID NOT NULL,
    "operation" "MutationOperation" NOT NULL,
    "requestHash" CHAR(64) NOT NULL,
    "result" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProcessedMutation_pkey" PRIMARY KEY ("mutationId")
);

-- CreateTable
CREATE TABLE "ExpenseChange" (
    "sequence" BIGSERIAL NOT NULL,
    "householdId" UUID NOT NULL,
    "entityId" UUID NOT NULL,
    "entityVersion" INTEGER NOT NULL,
    "operation" "ChangeOperation" NOT NULL,
    "originMutationId" UUID NOT NULL,
    "snapshot" JSONB NOT NULL,
    "changedAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ExpenseChange_pkey" PRIMARY KEY ("sequence")
);

-- CreateIndex
CREATE UNIQUE INDEX "Household_slug_key" ON "Household"("slug");

-- CreateIndex
CREATE INDEX "Member_householdId_idx" ON "Member"("householdId");

-- CreateIndex
CREATE UNIQUE INDEX "Member_householdId_key_key" ON "Member"("householdId", "key");

-- CreateIndex
CREATE UNIQUE INDEX "Member_householdId_id_key" ON "Member"("householdId", "id");

-- CreateIndex
CREATE UNIQUE INDEX "RefreshToken_tokenHash_key" ON "RefreshToken"("tokenHash");

-- CreateIndex
CREATE UNIQUE INDEX "RefreshToken_replacedByTokenId_key" ON "RefreshToken"("replacedByTokenId");

-- CreateIndex
CREATE INDEX "RefreshToken_memberId_idx" ON "RefreshToken"("memberId");

-- CreateIndex
CREATE INDEX "RefreshToken_familyId_idx" ON "RefreshToken"("familyId");

-- CreateIndex
CREATE INDEX "RefreshToken_expiresAt_idx" ON "RefreshToken"("expiresAt");

-- CreateIndex
CREATE INDEX "Expense_householdId_occurredAt_idx" ON "Expense"("householdId", "occurredAt");

-- CreateIndex
CREATE INDEX "Expense_householdId_lastChangeSequence_idx" ON "Expense"("householdId", "lastChangeSequence");

-- CreateIndex
CREATE INDEX "Expense_householdId_payerId_idx" ON "Expense"("householdId", "payerId");

-- CreateIndex
CREATE INDEX "ProcessedMutation_householdId_createdAt_idx" ON "ProcessedMutation"("householdId", "createdAt");

-- CreateIndex
CREATE INDEX "ProcessedMutation_householdId_entityId_idx" ON "ProcessedMutation"("householdId", "entityId");

-- CreateIndex
CREATE UNIQUE INDEX "ExpenseChange_originMutationId_key" ON "ExpenseChange"("originMutationId");

-- CreateIndex
CREATE INDEX "ExpenseChange_householdId_sequence_idx" ON "ExpenseChange"("householdId", "sequence");

-- CreateIndex
CREATE INDEX "ExpenseChange_householdId_entityId_entityVersion_idx" ON "ExpenseChange"("householdId", "entityId", "entityVersion");

-- AddForeignKey
ALTER TABLE "Member" ADD CONSTRAINT "Member_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_memberId_fkey" FOREIGN KEY ("memberId") REFERENCES "Member"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefreshToken" ADD CONSTRAINT "RefreshToken_replacedByTokenId_fkey" FOREIGN KEY ("replacedByTokenId") REFERENCES "RefreshToken"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Expense" ADD CONSTRAINT "Expense_householdId_payerId_fkey" FOREIGN KEY ("householdId", "payerId") REFERENCES "Member"("householdId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProcessedMutation" ADD CONSTRAINT "ProcessedMutation_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ProcessedMutation" ADD CONSTRAINT "ProcessedMutation_householdId_memberId_fkey" FOREIGN KEY ("householdId", "memberId") REFERENCES "Member"("householdId", "id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ExpenseChange" ADD CONSTRAINT "ExpenseChange_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
