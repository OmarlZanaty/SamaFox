-- Shared CAR WHEEL rounds and their chips. A chip row is written with the
-- balance charge; chips still "open" after a restart are refunded on boot.
CREATE TABLE "car_wheel_rounds" (
  "id" SERIAL NOT NULL,
  "seedHash" TEXT NOT NULL,
  "seed" TEXT NOT NULL,
  "result" TEXT,
  "totalBet" INTEGER NOT NULL DEFAULT 0,
  "players" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "settledAt" TIMESTAMP(3),
  CONSTRAINT "car_wheel_rounds_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "car_wheel_rounds_settledAt_idx" ON "car_wheel_rounds"("settledAt");

CREATE TABLE "car_wheel_stakes" (
  "id" SERIAL NOT NULL,
  "roundId" INTEGER NOT NULL,
  "userId" INTEGER NOT NULL,
  "betKey" TEXT NOT NULL,
  "amount" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'open',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "car_wheel_stakes_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "car_wheel_stakes_roundId_fkey" FOREIGN KEY ("roundId") REFERENCES "car_wheel_rounds"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "car_wheel_stakes_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "car_wheel_stakes_roundId_userId_idx" ON "car_wheel_stakes"("roundId", "userId");
CREATE INDEX "car_wheel_stakes_status_idx" ON "car_wheel_stakes"("status");
CREATE INDEX "car_wheel_stakes_userId_createdAt_idx" ON "car_wheel_stakes"("userId", "createdAt");
