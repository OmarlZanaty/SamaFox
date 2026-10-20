-- SPEC52 #28/#29 (2026-10-20): gift rocket, PK, durable room-gift outbox.
-- Additive; existing pk_battles rows become status CANCELLED (inactive). Safe to re-run.
-- AlterTable
ALTER TABLE "pk_battles" ADD COLUMN IF NOT EXISTS "configSnapshot" JSONB NOT NULL DEFAULT '{}',
ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN IF NOT EXISTS "createdBy" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "durationSec" INTEGER NOT NULL DEFAULT 300,
ADD COLUMN IF NOT EXISTS "scoreReachedA" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "scoreReachedB" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "sideAUserId" INTEGER,
ADD COLUMN IF NOT EXISTS "sideBUserId" INTEGER,
ADD COLUMN IF NOT EXISTS "startedAt" TIMESTAMP(3),
ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'CANCELLED',
ADD COLUMN IF NOT EXISTS "type" TEXT NOT NULL DEFAULT 'GLOBAL',
ADD COLUMN IF NOT EXISTS "winner" TEXT;

-- CreateTable
CREATE TABLE IF NOT EXISTS "rocket_configs" (
    "id" SERIAL NOT NULL,
    "targetCoins" INTEGER NOT NULL DEFAULT 1000000,
    "roomCupPercent" INTEGER NOT NULL DEFAULT 1000,
    "durationMinutes" INTEGER NOT NULL DEFAULT 30,
    "winnersCount" INTEGER NOT NULL DEFAULT 10,
    "maxRewardPerUserCoins" INTEGER NOT NULL DEFAULT 1000,
    "claimWindowSeconds" INTEGER NOT NULL DEFAULT 90,
    "rewards" JSONB NOT NULL DEFAULT '[]',
    "isActive" BOOLEAN NOT NULL DEFAULT false,
    "updatedBy" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "rocket_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "rocket_events" (
    "id" TEXT NOT NULL,
    "roomId" INTEGER NOT NULL,
    "configSnapshot" JSONB NOT NULL,
    "targetCoins" INTEGER NOT NULL,
    "currentCoins" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "launchedAt" TIMESTAMP(3),

    CONSTRAINT "rocket_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "rocket_contributions" (
    "id" SERIAL NOT NULL,
    "eventId" TEXT NOT NULL,
    "giftTransactionId" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "coins" INTEGER NOT NULL,

    CONSTRAINT "rocket_contributions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "rocket_claims" (
    "id" SERIAL NOT NULL,
    "rocketEventId" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "rewardJson" JSONB NOT NULL,
    "claimedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "rocket_claims_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "pk_configs" (
    "id" SERIAL NOT NULL,
    "allowedDurations" JSONB NOT NULL DEFAULT '[180,300,600]',
    "countedGiftIds" JSONB NOT NULL DEFAULT '[]',
    "pointsPerCoin" INTEGER NOT NULL DEFAULT 1,
    "winCondition" TEXT NOT NULL DEFAULT 'HIGHER_SCORE',
    "tieRule" TEXT NOT NULL DEFAULT 'TIE',
    "rewards" JSONB NOT NULL DEFAULT '{}',
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "updatedBy" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pk_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "pk_contributions" (
    "id" SERIAL NOT NULL,
    "pkId" TEXT NOT NULL,
    "giftTransactionId" TEXT NOT NULL,
    "side" TEXT NOT NULL,
    "points" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pk_contributions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "pk_room_locks" (
    "roomId" INTEGER NOT NULL,
    "pkId" TEXT NOT NULL,

    CONSTRAINT "pk_room_locks_pkey" PRIMARY KEY ("roomId")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "room_gift_jobs" (
    "giftTransactionId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMP(3),

    CONSTRAINT "room_gift_jobs_pkey" PRIMARY KEY ("giftTransactionId")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "rocket_events_roomId_status_idx" ON "rocket_events"("roomId", "status");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "rocket_contributions_giftTransactionId_key" ON "rocket_contributions"("giftTransactionId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "rocket_claims_rocketEventId_userId_key" ON "rocket_claims"("rocketEventId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "pk_contributions_giftTransactionId_key" ON "pk_contributions"("giftTransactionId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "room_gift_jobs_processedAt_createdAt_idx" ON "room_gift_jobs"("processedAt", "createdAt");

-- AddForeignKey
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rocket_contributions_eventId_fkey') THEN ALTER TABLE "rocket_contributions" ADD CONSTRAINT "rocket_contributions_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "rocket_events"("id") ON DELETE RESTRICT ON UPDATE CASCADE; END IF; END $$;

-- AddForeignKey
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rocket_claims_rocketEventId_fkey') THEN ALTER TABLE "rocket_claims" ADD CONSTRAINT "rocket_claims_rocketEventId_fkey" FOREIGN KEY ("rocketEventId") REFERENCES "rocket_events"("id") ON DELETE RESTRICT ON UPDATE CASCADE; END IF; END $$;

-- AddForeignKey
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_contributions_pkId_fkey') THEN ALTER TABLE "pk_contributions" ADD CONSTRAINT "pk_contributions_pkId_fkey" FOREIGN KEY ("pkId") REFERENCES "pk_battles"("id") ON DELETE RESTRICT ON UPDATE CASCADE; END IF; END $$;

-- AddForeignKey
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pk_room_locks_pkId_fkey') THEN ALTER TABLE "pk_room_locks" ADD CONSTRAINT "pk_room_locks_pkId_fkey" FOREIGN KEY ("pkId") REFERENCES "pk_battles"("id") ON DELETE RESTRICT ON UPDATE CASCADE; END IF; END $$;

