ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "videoFallbackUrl" TEXT;
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "videoMeta" JSONB;
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "hasSound" BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "effectType" TEXT;
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "soundUrl" TEXT;
ALTER TABLE "gift_transactions" ADD COLUMN IF NOT EXISTS "clientRequestId" TEXT;
ALTER TABLE "gift_transactions" ADD COLUMN IF NOT EXISTS "operationId" TEXT;
ALTER TABLE "gift_transactions" ADD COLUMN IF NOT EXISTS "seatNumber" INTEGER;
ALTER TABLE "gift_transactions" ADD COLUMN IF NOT EXISTS "targetType" TEXT;
ALTER TABLE "gift_transactions" ADD COLUMN IF NOT EXISTS "eventSnapshot" JSONB;
CREATE UNIQUE INDEX IF NOT EXISTS "gift_transactions_clientRequestId_key" ON "gift_transactions" ("clientRequestId");
CREATE TABLE IF NOT EXISTS "gift_operations" (
  "id" TEXT PRIMARY KEY, "senderId" INTEGER NOT NULL, "requestHash" TEXT NOT NULL,
  "responseBody" JSONB NOT NULL, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS "gift_deliveries" (
  "transactionId" TEXT PRIMARY KEY, "payload" JSONB NOT NULL, "deliveredAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "gift_deliveries_deliveredAt_createdAt_idx" ON "gift_deliveries" ("deliveredAt", "createdAt");
