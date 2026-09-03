-- Provably-fair seed state for بلينكو, نيون فورتشن and أثيرفول.
--
-- All three kept this in a module-level Map, which made the commitment hollow:
-- a restart or a deploy threw away the server seed whose hash a player had
-- already been shown, so nothing they had played could be verified afterwards,
-- and the nonce went back to zero — which on a fixed seed pair replays results.
-- It also meant the games could never run on more than one process.
--
-- serverSeed is the secret half. It must only ever leave the server through a
-- deliberate rotation, which reveals the retired seed and commits to a new one.
CREATE TABLE IF NOT EXISTS "game_fair_seeds" (
    "id"             TEXT NOT NULL,
    "userId"         INTEGER NOT NULL,
    "game"           TEXT NOT NULL,
    "serverSeed"     TEXT NOT NULL,
    "serverSeedHash" TEXT NOT NULL,
    "clientSeed"     TEXT NOT NULL,
    "nonce"          INTEGER NOT NULL DEFAULT 0,
    "createdAt"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"      TIMESTAMP(3) NOT NULL,

    CONSTRAINT "game_fair_seeds_pkey" PRIMARY KEY ("id")
);

-- One seed pair per player per game; this is also the lookup the hot path uses.
CREATE UNIQUE INDEX IF NOT EXISTS "game_fair_seeds_userId_game_key"
    ON "game_fair_seeds"("userId", "game");

ALTER TABLE "game_fair_seeds"
    ADD CONSTRAINT "game_fair_seeds_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
