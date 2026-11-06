ALTER TABLE "pk_configs" ADD COLUMN "minTotalCoins" BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN "viewerGiftCoins" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "viewerGiftItem" JSONB;
CREATE TABLE "pk_prize_boxes" (
  "pkId" TEXT PRIMARY KEY REFERENCES "pk_battles"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  "winnerUserId" INTEGER NOT NULL, "winnerName" TEXT NOT NULL, "winnerAvatar" TEXT,
  "room1Id" INTEGER NOT NULL, "room2Id" INTEGER NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL, "configSnapshot" JSONB NOT NULL
);
CREATE TABLE "pk_claims" (
  "id" SERIAL PRIMARY KEY, "pkId" TEXT NOT NULL REFERENCES "pk_prize_boxes"("pkId") ON DELETE RESTRICT ON UPDATE CASCADE,
  "userId" INTEGER NOT NULL, "rewardJson" JSONB NOT NULL, "claimedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "pk_claims_pkId_userId_key" ON "pk_claims"("pkId", "userId");
