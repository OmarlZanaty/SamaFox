-- Durable Fruit Jackpot history; result and coin settlement commit together.
-- GameFairSeed and economy accounts already accept arbitrary game keys.
CREATE TABLE "fruit_jackpot_rounds" (
  "id" TEXT NOT NULL,
  "userId" INTEGER NOT NULL,
  "requestId" TEXT NOT NULL,
  "result" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "fruit_jackpot_rounds_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "fruit_jackpot_rounds_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "fruit_jackpot_rounds_userId_requestId_key" ON "fruit_jackpot_rounds"("userId", "requestId");
CREATE INDEX "fruit_jackpot_rounds_userId_createdAt_idx" ON "fruit_jackpot_rounds"("userId", "createdAt");
