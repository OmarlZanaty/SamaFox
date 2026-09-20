-- هدايا الحظ — lucky gifts. The host keeps 10%, the sender rolls for a
-- multiple of that 10%, every payout comes out of a pool fed by the other 90%.
-- Additive only: nothing here changes a column an installed app reads.

ALTER TABLE "gifts" ADD COLUMN "isLucky" BOOLEAN NOT NULL DEFAULT false;

-- What the sender paid. For every existing row that is exactly totalCoins.
ALTER TABLE "gift_transactions" ADD COLUMN "paidCoins" INTEGER NOT NULL DEFAULT 0;
UPDATE "gift_transactions" SET "paidCoins" = "totalCoins";

CREATE TABLE "lucky_pool" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "balance" BIGINT NOT NULL DEFAULT 0,
    "totalIn" BIGINT NOT NULL DEFAULT 0,
    "totalOut" BIGINT NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "lucky_pool_pkey" PRIMARY KEY ("id")
);
INSERT INTO "lucky_pool" ("id", "updatedAt") VALUES (1, CURRENT_TIMESTAMP);

CREATE TABLE "lucky_tiers" (
    "id" SERIAL NOT NULL,
    "multiplier" INTEGER NOT NULL,
    "weightBp" INTEGER NOT NULL,
    "minPoolCoins" BIGINT NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT "lucky_tiers_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "lucky_tiers_multiplier_key" ON "lucky_tiers"("multiplier");

-- The default table: 75% of rolls win something, E[multiplier] = 7.82, so the
-- sender gets back 78% on average, the host 10%, and ~12% stays in the pool as
-- the float that funds the big multipliers. minPoolCoins keeps 100x+ out of the draw until
-- the pool can absorb one.
INSERT INTO "lucky_tiers" ("multiplier", "weightBp", "minPoolCoins") VALUES
  (5,   4000, 0),
  (10,  2500, 0),
  (20,   800, 0),
  (50,   200, 5000),
  (100,   35, 20000),
  (200,   10, 60000),
  (300,    4, 120000),
  (500,    1, 250000);

CREATE TABLE "lucky_rolls" (
    "id" SERIAL NOT NULL,
    "giftTxId" TEXT NOT NULL,
    "senderId" INTEGER NOT NULL,
    "recipientId" INTEGER NOT NULL,
    "roomId" INTEGER,
    "giftCoins" INTEGER NOT NULL,
    "hostCoins" INTEGER NOT NULL,
    "multiplier" INTEGER NOT NULL,
    "payoutCoins" INTEGER NOT NULL,
    "poolBefore" BIGINT NOT NULL,
    "poolAfter" BIGINT NOT NULL,
    "serverSeed" TEXT NOT NULL,
    "serverSeedHash" TEXT NOT NULL,
    "tiersSnapshot" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "lucky_rolls_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "lucky_rolls_giftTxId_key" ON "lucky_rolls"("giftTxId");
CREATE INDEX "lucky_rolls_senderId_createdAt_idx" ON "lucky_rolls"("senderId", "createdAt");
CREATE INDEX "lucky_rolls_createdAt_idx" ON "lucky_rolls"("createdAt");
CREATE INDEX "lucky_rolls_multiplier_createdAt_idx" ON "lucky_rolls"("multiplier", "createdAt");
ALTER TABLE "lucky_rolls" ADD CONSTRAINT "lucky_rolls_giftTxId_fkey"
  FOREIGN KEY ("giftTxId") REFERENCES "gift_transactions"("id") ON DELETE CASCADE ON UPDATE CASCADE;
