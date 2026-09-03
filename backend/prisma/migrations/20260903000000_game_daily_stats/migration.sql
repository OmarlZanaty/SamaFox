-- ============================================================
-- 2026-09-03 — persistent "today" board for the wager games
--
-- القط الجشع shipped with its daily leaderboard (أرباح اليوم / سجلي /
-- ترتيب اليوم) held in a process-local Map, so every deploy wiped the board
-- mid-day and a restart lost every player's running total. This is that state,
-- durably.
--
-- `game` is a discriminator: the sibling wager games have the identical need
-- and can adopt this table without another migration.
--
-- `day` is a UTC "YYYY-MM-DD" string, not a timestamp — the reset is defined as
-- UTC midnight, and a string makes that unambiguous and indexes cleanly.
--
-- Purely additive: a new table, no existing row touched.
-- ============================================================

CREATE TABLE IF NOT EXISTS "game_daily_stats" (
  "id"          TEXT NOT NULL,
  "game"        TEXT NOT NULL,
  "day"         TEXT NOT NULL,
  "userId"      INTEGER NOT NULL,
  "net"         INTEGER NOT NULL DEFAULT 0,
  "wagered"     INTEGER NOT NULL DEFAULT 0,
  "best"        INTEGER NOT NULL DEFAULT 0,
  "countryCode" TEXT,
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"   TIMESTAMP(3) NOT NULL,
  CONSTRAINT "game_daily_stats_pkey" PRIMARY KEY ("id")
);

-- One row per player per game per day; this is also what the upsert keys on.
CREATE UNIQUE INDEX IF NOT EXISTS "game_daily_stats_game_day_userId_key"
  ON "game_daily_stats" ("game", "day", "userId");

-- The global board: top net for a game on a day.
CREATE INDEX IF NOT EXISTS "game_daily_stats_game_day_net_idx"
  ON "game_daily_stats" ("game", "day", "net");

-- The regional board: same, narrowed to one country.
CREATE INDEX IF NOT EXISTS "game_daily_stats_game_day_countryCode_net_idx"
  ON "game_daily_stats" ("game", "day", "countryCode", "net");

DO $$
BEGIN
  ALTER TABLE "game_daily_stats"
    ADD CONSTRAINT "game_daily_stats_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
