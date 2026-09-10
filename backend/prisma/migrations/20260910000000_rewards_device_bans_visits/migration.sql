-- A15 / F4 / C16 — rewards, device bans, profile visitors.
--
-- Additive only: new tables, no column changed on an existing one, every
-- statement IF NOT EXISTS. Safe to replay on a database that already has them.

-- ── A15a: مكافأة كأس الروم ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "room_cup_rewards" (
  "id"             SERIAL PRIMARY KEY,
  "thresholdCoins" BIGINT       NOT NULL,
  "rewardCoins"    BIGINT       NOT NULL,
  "isActive"       BOOLEAN      NOT NULL DEFAULT true,
  "createdAt"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "room_cup_rewards_thresholdCoins_idx"
  ON "room_cup_rewards" ("thresholdCoins");

CREATE TABLE IF NOT EXISTS "room_cup_reward_payouts" (
  "id"       SERIAL PRIMARY KEY,
  "rewardId" INTEGER      NOT NULL,
  "roomId"   INTEGER      NOT NULL,
  "userId"   INTEGER      NOT NULL,
  "coins"    BIGINT       NOT NULL,
  "paidAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "room_cup_reward_payouts_rewardId_fkey"
    FOREIGN KEY ("rewardId") REFERENCES "room_cup_rewards"("id") ON DELETE CASCADE
);
-- One rung pays a given room exactly once. This constraint IS the idempotency.
CREATE UNIQUE INDEX IF NOT EXISTS "room_cup_reward_payouts_rewardId_roomId_key"
  ON "room_cup_reward_payouts" ("rewardId", "roomId");
CREATE INDEX IF NOT EXISTS "room_cup_reward_payouts_roomId_idx"
  ON "room_cup_reward_payouts" ("roomId");

-- ── A15b: مكافأة الداعمين ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "supporter_rewards" (
  "id"          SERIAL PRIMARY KEY,
  "targetCoins" BIGINT       NOT NULL,
  "rewardCoins" BIGINT       NOT NULL,
  "roomId"      INTEGER,
  "isActive"    BOOLEAN      NOT NULL DEFAULT true,
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "supporter_rewards_targetCoins_idx"
  ON "supporter_rewards" ("targetCoins");

CREATE TABLE IF NOT EXISTS "supporter_reward_claims" (
  "id"        SERIAL PRIMARY KEY,
  "rewardId"  INTEGER      NOT NULL,
  "userId"    INTEGER      NOT NULL,
  "roomId"    INTEGER,
  "coins"     BIGINT       NOT NULL,
  "claimedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "supporter_reward_claims_rewardId_fkey"
    FOREIGN KEY ("rewardId") REFERENCES "supporter_rewards"("id") ON DELETE CASCADE,
  CONSTRAINT "supporter_reward_claims_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE
);
-- A supporter claims each rung once, and this is what stops a double-tap on
-- "مكافأة لك" from paying twice.
CREATE UNIQUE INDEX IF NOT EXISTS "supporter_reward_claims_rewardId_userId_key"
  ON "supporter_reward_claims" ("rewardId", "userId");
CREATE INDEX IF NOT EXISTS "supporter_reward_claims_userId_idx"
  ON "supporter_reward_claims" ("userId");

-- ── F4: حظر الجهاز / الشبكة ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "device_bans" (
  "id"        SERIAL PRIMARY KEY,
  "deviceId"  TEXT,
  "ipAddress" TEXT,
  "reason"    TEXT,
  "expiresAt" TIMESTAMP(3),
  "bannedBy"  INTEGER,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS "device_bans_deviceId_key"  ON "device_bans" ("deviceId");
CREATE UNIQUE INDEX IF NOT EXISTS "device_bans_ipAddress_key" ON "device_bans" ("ipAddress");
CREATE INDEX IF NOT EXISTS "device_bans_expiresAt_idx"        ON "device_bans" ("expiresAt");

-- ── C16: الزوار ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "profile_visits" (
  "id"        SERIAL PRIMARY KEY,
  "profileId" INTEGER      NOT NULL,
  "viewerId"  INTEGER      NOT NULL,
  "source"    TEXT         NOT NULL DEFAULT 'home',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "profile_visits_profileId_fkey"
    FOREIGN KEY ("profileId") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "profile_visits_viewerId_fkey"
    FOREIGN KEY ("viewerId") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "profile_visits_profileId_createdAt_idx"
  ON "profile_visits" ("profileId", "createdAt");
CREATE INDEX IF NOT EXISTS "profile_visits_viewerId_idx"
  ON "profile_visits" ("viewerId");
