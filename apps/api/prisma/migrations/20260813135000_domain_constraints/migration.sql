ALTER TABLE "Expense"
  ADD CONSTRAINT "Expense_amountMinor_range_check"
    CHECK ("amountMinor" BETWEEN 1 AND 99999999999),
  ADD CONSTRAINT "Expense_version_positive_check"
    CHECK ("version" >= 1),
  ADD CONSTRAINT "Expense_lastChangeSequence_nonnegative_check"
    CHECK ("lastChangeSequence" >= 0);

ALTER TABLE "ExpenseChange"
  ADD CONSTRAINT "ExpenseChange_entityVersion_positive_check"
    CHECK ("entityVersion" >= 1);

ALTER TABLE "ProcessedMutation"
  ADD CONSTRAINT "ProcessedMutation_requestHash_hex_check"
    CHECK ("requestHash" ~ '^[0-9a-f]{64}$');

ALTER TABLE "RefreshToken"
  ADD CONSTRAINT "RefreshToken_tokenHash_hex_check"
    CHECK ("tokenHash" ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT "RefreshToken_expiry_after_creation_check"
    CHECK ("expiresAt" > "createdAt");
