CREATE TABLE IF NOT EXISTS "room_sessions" (
  "id" TEXT PRIMARY KEY,
  "userId" INTEGER NOT NULL,
  "roomId" INTEGER NOT NULL,
  "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "lastHeartbeat" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "wsState" TEXT NOT NULL DEFAULT 'connected',
  "voiceState" TEXT NOT NULL DEFAULT 'listening',
  "seatNumber" INTEGER,
  "lastApi" TEXT,
  "disconnectReason" TEXT,
  "reconnectCount" INTEGER NOT NULL DEFAULT 0,
  "leftAt" TIMESTAMP(3),
  "leaveReason" TEXT
);
CREATE INDEX IF NOT EXISTS "room_sessions_userId_joinedAt_idx" ON "room_sessions" ("userId", "joinedAt");
CREATE INDEX IF NOT EXISTS "room_sessions_roomId_joinedAt_idx" ON "room_sessions" ("roomId", "joinedAt");
CREATE INDEX IF NOT EXISTS "room_sessions_joinedAt_idx" ON "room_sessions" ("joinedAt");
