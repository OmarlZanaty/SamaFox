-- Shared ROULETTE rounds and their chips. A chip row is written with the
-- balance charge; chips still "open" after a restart are refunded on boot.
CREATE TABLE "roulette_rounds" (
  "id" SERIAL NOT NULL,
  "seedHash" TEXT NOT NULL,
  "seed" TEXT NOT NULL,
  "result" INTEGER,
  "totalBet" INTEGER NOT NULL DEFAULT 0,
  "players" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "settledAt" TIMESTAMP(3),
  CONSTRAINT "roulette_rounds_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "roulette_rounds_settledAt_idx" ON "roulette_rounds"("settledAt");

CREATE TABLE "roulette_stakes" (
  "id" SERIAL NOT NULL,
  "roundId" INTEGER NOT NULL,
  "userId" INTEGER NOT NULL,
  "betKey" TEXT NOT NULL,
  "amount" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'open',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "roulette_stakes_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "roulette_stakes_roundId_fkey" FOREIGN KEY ("roundId") REFERENCES "roulette_rounds"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "roulette_stakes_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "roulette_stakes_roundId_userId_idx" ON "roulette_stakes"("roundId", "userId");
CREATE INDEX "roulette_stakes_status_idx" ON "roulette_stakes"("status");
CREATE INDEX "roulette_stakes_userId_createdAt_idx" ON "roulette_stakes"("userId", "createdAt");
