-- Durable FRUIT WHEEL history; result and coin settlement commit together.
-- GameFairSeed and economy accounts already accept arbitrary game keys.
CREATE TABLE "fruit_wheel_rounds" (
  "id" TEXT NOT NULL,
  "userId" INTEGER NOT NULL,
  "requestId" TEXT NOT NULL,
  "round" INTEGER NOT NULL,
  "result" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "fruit_wheel_rounds_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "fruit_wheel_rounds_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "fruit_wheel_rounds_userId_requestId_key" ON "fruit_wheel_rounds"("userId", "requestId");
CREATE INDEX "fruit_wheel_rounds_userId_createdAt_idx" ON "fruit_wheel_rounds"("userId", "createdAt");
CREATE INDEX "fruit_wheel_rounds_createdAt_idx" ON "fruit_wheel_rounds"("createdAt");
