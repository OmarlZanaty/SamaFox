-- SPEC52 #39 (2026-10-20): announced game wins for the room strip. New table only.
CREATE TABLE IF NOT EXISTS "game_win_events" (
  "id" SERIAL PRIMARY KEY,
  "ledgerId" INTEGER NOT NULL,
  "userId" INTEGER NOT NULL,
  "roomId" INTEGER,
  "gameId" TEXT NOT NULL,
  "gameName" TEXT NOT NULL,
  "winCoins" INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS "game_win_events_ledgerId_key" ON "game_win_events" ("ledgerId");
CREATE INDEX IF NOT EXISTS "game_win_events_roomId_id_idx" ON "game_win_events" ("roomId", "id");
