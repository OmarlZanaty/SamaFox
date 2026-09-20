-- قفل الرسائل الخاصة — public / friends-only / paid DMs. The fee for a paid
-- lock goes to the platform (Transaction type DM_FEE), never to the user who
-- set the lock. Additive only.

ALTER TABLE "users" ADD COLUMN "dmPrivacy" TEXT NOT NULL DEFAULT 'public';
ALTER TABLE "users" ADD COLUMN "dmPriceCoins" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "Conversation" ADD COLUMN "unlockedByUserId" INTEGER;
ALTER TABLE "Conversation" ADD COLUMN "unlockedAt" TIMESTAMP(3);
