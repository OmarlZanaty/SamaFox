CREATE TABLE IF NOT EXISTS "room_share_tokens" (
  "id" SERIAL PRIMARY KEY,
  "token" TEXT NOT NULL,
  "roomId" INTEGER NOT NULL,
  "inviterId" INTEGER NOT NULL,
  "roomName" TEXT NOT NULL,
  "roomImageUrl" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '7 days'),
  "revokedAt" TIMESTAMP(3),
  "useCount" INTEGER NOT NULL DEFAULT 0,
  "lastUsedAt" TIMESTAMP(3)
);
CREATE UNIQUE INDEX IF NOT EXISTS "room_share_tokens_token_key" ON "room_share_tokens" ("token");
CREATE INDEX IF NOT EXISTS "room_share_tokens_roomId_expiresAt_idx" ON "room_share_tokens" ("roomId", "expiresAt");
ALTER TABLE "DirectMessage" ADD COLUMN IF NOT EXISTS "metadata" JSONB;
ALTER TABLE "room_entry_logs" ADD COLUMN IF NOT EXISTS "invitedBy" INTEGER;
