-- Shared FRUIT WHEEL v2 rounds and their chips. A chip row is written with the
-- balance charge; chips still "open" after a restart are refunded on boot.
CREATE TABLE "fruit_wheel_shared_rounds" (
  "id" SERIAL NOT NULL,
  "seedHash" TEXT NOT NULL,
  "seed" TEXT NOT NULL,
  "result" TEXT,
  "totalBet" INTEGER NOT NULL DEFAULT 0,
  "players" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "settledAt" TIMESTAMP(3),
  CONSTRAINT "fruit_wheel_shared_rounds_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "fruit_wheel_shared_rounds_settledAt_idx" ON "fruit_wheel_shared_rounds"("settledAt");

CREATE TABLE "fruit_wheel_stakes" (
  "id" SERIAL NOT NULL,
  "roundId" INTEGER NOT NULL,
  "userId" INTEGER NOT NULL,
  "betKey" TEXT NOT NULL,
  "amount" INTEGER NOT NULL,
  "payout" INTEGER NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT 'open',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "fruit_wheel_stakes_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "fruit_wheel_stakes_roundId_fkey" FOREIGN KEY ("roundId") REFERENCES "fruit_wheel_shared_rounds"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "fruit_wheel_stakes_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "fruit_wheel_stakes_roundId_userId_idx" ON "fruit_wheel_stakes"("roundId", "userId");
CREATE INDEX "fruit_wheel_stakes_status_idx" ON "fruit_wheel_stakes"("status");
CREATE INDEX "fruit_wheel_stakes_userId_createdAt_idx" ON "fruit_wheel_stakes"("userId", "createdAt");
