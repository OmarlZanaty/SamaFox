-- Rocket tiers + top-3 supporter prizes held until claimed (client 10/11 19:48).
ALTER TABLE "rocket_configs" ADD COLUMN IF NOT EXISTS "tiers" JSONB NOT NULL DEFAULT '[]';
ALTER TABLE "rocket_events" ADD COLUMN IF NOT EXISTS "tier" INTEGER NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS "rocket_top_prizes" (
    "id" SERIAL NOT NULL,
    "eventId" TEXT NOT NULL,
    "roomId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "rank" INTEGER NOT NULL,
    "coins" INTEGER NOT NULL,
    "rewardJson" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimedAt" TIMESTAMP(3),
    CONSTRAINT "rocket_top_prizes_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "rocket_top_prizes_eventId_rank_key" ON "rocket_top_prizes"("eventId", "rank");
CREATE INDEX IF NOT EXISTS "rocket_top_prizes_userId_claimedAt_idx" ON "rocket_top_prizes"("userId", "claimedAt");
