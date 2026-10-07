-- YUMMY daily missions: one row per claimed mission per Cairo day. Progress is
-- derived from yummy_rounds / game_ledger, so only the claim is stored.
CREATE TABLE "yummy_mission_claims" (
  "id" SERIAL NOT NULL,
  "userId" INTEGER NOT NULL,
  "day" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "xp" INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "yummy_mission_claims_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "yummy_mission_claims_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "yummy_mission_claims_userId_day_key_key" ON "yummy_mission_claims"("userId", "day", "key");
