-- Records which member authored each change-feed row.
--
-- A pulling device must tell the other member's activity apart from its own
-- writes echoing back, and the outbox row that would identify its own mutation
-- is already deleted by the time that change arrives. `ProcessedMutation` is
-- written atomically with every accepted mutation and is never pruned, so the
-- column is added nullable, backfilled by joining each change to its origin
-- mutation's member, and only then made NOT NULL. A row surviving the backfill
-- without an author would mean a change stored without its receipt; failing
-- here is correct rather than recording an ambiguous author.

-- AlterTable
ALTER TABLE "ExpenseChange" ADD COLUMN     "actorMemberKey" "MemberKey";

-- Backfill: every change inherits the member named by its origin mutation.
UPDATE "ExpenseChange"
SET "actorMemberKey" = "Member"."key"
FROM "ProcessedMutation"
    JOIN "Member" ON "Member"."id" = "ProcessedMutation"."memberId"
WHERE "ProcessedMutation"."mutationId" = "ExpenseChange"."originMutationId";

-- AlterTable
ALTER TABLE "ExpenseChange" ALTER COLUMN "actorMemberKey" SET NOT NULL;
