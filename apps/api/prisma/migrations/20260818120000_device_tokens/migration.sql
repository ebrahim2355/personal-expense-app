-- Registers the installed apps that may be woken by a push message.
--
-- Purely additive: no existing table is touched, so the deploy is safe against a
-- running API and an older client that knows nothing about devices. Until a
-- device registers, the table stays empty and every send is a no-op, which is
-- exactly the polling-only behaviour that shipped before this migration.
--
-- `token` is stored in the clear alongside its hash, unlike every other token in
-- this schema. It is an address the server must hand to Google verbatim, not a
-- credential: holding it allows sending a message *to* the device, never acting
-- *as* the member. `tokenHash` keeps the fixed-width uniqueness key so a
-- re-registration of an unchanged token upserts instead of inserting a duplicate.
--
-- The member foreign key is composite so a device row cannot name a member from
-- another household; the send query filters on `householdId` to decide who gets
-- woken, and that filter should be backed by the database rather than by
-- application care alone.

-- CreateEnum
CREATE TYPE "DevicePlatform" AS ENUM ('ANDROID');

-- CreateTable
CREATE TABLE "DeviceToken" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "householdId" UUID NOT NULL,
    "memberId" UUID NOT NULL,
    "platform" "DevicePlatform" NOT NULL DEFAULT 'ANDROID',
    "tokenHash" CHAR(64) NOT NULL,
    "token" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "disabledAt" TIMESTAMPTZ(3),

    CONSTRAINT "DeviceToken_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DeviceToken_tokenHash_key" ON "DeviceToken"("tokenHash");

-- CreateIndex
CREATE INDEX "DeviceToken_householdId_memberId_idx" ON "DeviceToken"("householdId", "memberId");

-- CreateIndex
CREATE INDEX "DeviceToken_memberId_idx" ON "DeviceToken"("memberId");

-- AddForeignKey
ALTER TABLE "DeviceToken" ADD CONSTRAINT "DeviceToken_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "Household"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceToken" ADD CONSTRAINT "DeviceToken_householdId_memberId_fkey" FOREIGN KEY ("householdId", "memberId") REFERENCES "Member"("householdId", "id") ON DELETE CASCADE ON UPDATE CASCADE;
