-- ============================================================
-- 2026-09-26 — economy (lucky rounds, game pools, idempotency), CP break fees
-- and levels, locked/official rooms, hidden mode, host targets, agency invites,
-- audit reason.
--
-- ADDITIVE ONLY: new tables and new nullable/defaulted columns. Nothing an
-- installed app reads is renamed, dropped or retyped, so rolling the code back
-- needs no down-migration (the old code simply ignores all of this).
-- Take a pg_dump before applying (see docs/delivery-2026-09-26.md).
-- ============================================================

-- ── admin audit: why, and from which session/device ─────────
ALTER TABLE "admin_audit_logs" ADD COLUMN IF NOT EXISTS "reason" TEXT;
ALTER TABLE "admin_audit_logs" ADD COLUMN IF NOT EXISTS "sessionId" TEXT;
ALTER TABLE "admin_audit_logs" ADD COLUMN IF NOT EXISTS "userAgent" TEXT;

-- ── idempotency keys ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "idempotency_keys" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "key" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'processing',
    "responseStatus" INTEGER,
    "responseBody" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    CONSTRAINT "idempotency_keys_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "idempotency_keys_userId_key_key" ON "idempotency_keys"("userId", "key");
CREATE INDEX IF NOT EXISTS "idempotency_keys_createdAt_idx" ON "idempotency_keys"("createdAt");

-- ── user features / permissions ──────────────────────────────
CREATE TABLE IF NOT EXISTS "user_features" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "featureKey" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "userOn" BOOLEAN NOT NULL DEFAULT false,
    "grantedBy" INTEGER,
    "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3),
    "note" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "user_features_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "user_features_userId_featureKey_key" ON "user_features"("userId", "featureKey");
CREATE INDEX IF NOT EXISTS "user_features_featureKey_idx" ON "user_features"("featureKey");

-- ── room entry log (hidden entries, password bypasses) ──────
CREATE TABLE IF NOT EXISTS "room_entry_logs" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "roomId" INTEGER NOT NULL,
    "hidden" BOOLEAN NOT NULL DEFAULT false,
    "lockBypass" TEXT,
    "enteredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "exitedAt" TIMESTAMP(3),
    CONSTRAINT "room_entry_logs_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "room_entry_logs_roomId_enteredAt_idx" ON "room_entry_logs"("roomId", "enteredAt");
CREATE INDEX IF NOT EXISTS "room_entry_logs_userId_enteredAt_idx" ON "room_entry_logs"("userId", "enteredAt");
CREATE INDEX IF NOT EXISTS "room_entry_logs_hidden_enteredAt_idx" ON "room_entry_logs"("hidden", "enteredAt");

-- ── rooms: official type, hidden-entry allowance ─────────────
ALTER TABLE "rooms" ADD COLUMN IF NOT EXISTS "roomType" TEXT NOT NULL DEFAULT 'USER';
ALTER TABLE "rooms" ADD COLUMN IF NOT EXISTS "allowHiddenEntry" BOOLEAN NOT NULL DEFAULT true;
-- The pinned «الإدارة» room (room.controller FEATURED_ROOM_ID) is the
-- programme's own room.
UPDATE "rooms" SET "roomType" = 'OFFICIAL_ROOM' WHERE "id" = 100000;

-- ── host targets: the single source ──────────────────────────
CREATE TABLE IF NOT EXISTS "host_targets" (
    "id" SERIAL NOT NULL,
    "hostId" INTEGER NOT NULL,
    "agencyId" INTEGER,
    "targetCoins" BIGINT NOT NULL,
    "targetUsd" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "periodStart" TIMESTAMP(3) NOT NULL,
    "periodEnd" TIMESTAMP(3) NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "source" TEXT NOT NULL DEFAULT 'ADMIN',
    "note" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "updatedBy" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "host_targets_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "host_targets_hostId_status_periodStart_idx" ON "host_targets"("hostId", "status", "periodStart");

-- ── agency invites: lifecycle ────────────────────────────────
ALTER TABLE "AgencyInvite" ADD COLUMN IF NOT EXISTS "expiresAt" TIMESTAMP(3);
ALTER TABLE "AgencyInvite" ADD COLUMN IF NOT EXISTS "respondedAt" TIMESTAMP(3);
ALTER TABLE "AgencyInvite" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
-- Invites still pending get a deadline, but never one that has already passed:
-- nobody's open invite disappears the moment this deploys.
UPDATE "AgencyInvite"
   SET "expiresAt" = GREATEST("createdAt" + INTERVAL '7 days', CURRENT_TIMESTAMP + INTERVAL '3 days')
 WHERE "status" = 'pending' AND "expiresAt" IS NULL;

-- ── economy bookkeeping ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS "economy_accounts" (
    "key" TEXT NOT NULL,
    "balance" BIGINT NOT NULL DEFAULT 0,
    "totalIn" BIGINT NOT NULL DEFAULT 0,
    "totalOut" BIGINT NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "economy_accounts_pkey" PRIMARY KEY ("key")
);
INSERT INTO "economy_accounts" ("key") VALUES ('PROGRAM') ON CONFLICT ("key") DO NOTHING;

CREATE TABLE IF NOT EXISTS "economy_ledger" (
    "id" SERIAL NOT NULL,
    "account" TEXT NOT NULL,
    "delta" BIGINT NOT NULL,
    "balanceAfter" BIGINT NOT NULL,
    "kind" TEXT NOT NULL,
    "refType" TEXT,
    "refId" TEXT,
    "userId" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "economy_ledger_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "economy_ledger_account_createdAt_idx" ON "economy_ledger"("account", "createdAt");
CREATE INDEX IF NOT EXISTS "economy_ledger_kind_createdAt_idx" ON "economy_ledger"("kind", "createdAt");
CREATE INDEX IF NOT EXISTS "economy_ledger_refType_refId_idx" ON "economy_ledger"("refType", "refId");

-- ── game ledger: split and caps ──────────────────────────────
ALTER TABLE "game_ledger" ADD COLUMN IF NOT EXISTS "programShare" INTEGER;
ALTER TABLE "game_ledger" ADD COLUMN IF NOT EXISTS "poolShare" INTEGER;
ALTER TABLE "game_ledger" ADD COLUMN IF NOT EXISTS "requested" INTEGER;
ALTER TABLE "game_ledger" ADD COLUMN IF NOT EXISTS "capped" BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS "game_ledger_game_kind_createdAt_idx" ON "game_ledger"("game", "kind", "createdAt");

-- ── lucky rounds ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "lucky_rounds" (
    "id" SERIAL NOT NULL,
    "code" TEXT NOT NULL,
    "roomId" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "closedAt" TIMESTAMP(3),
    "playerCount" INTEGER NOT NULL DEFAULT 0,
    "entryCount" INTEGER NOT NULL DEFAULT 0,
    "totalEntry" BIGINT NOT NULL DEFAULT 0,
    "hostShare" BIGINT NOT NULL DEFAULT 0,
    "programShare" BIGINT NOT NULL DEFAULT 0,
    "prizePool" BIGINT NOT NULL DEFAULT 0,
    "totalWin" BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT "lucky_rounds_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "lucky_rounds_code_key" ON "lucky_rounds"("code");
CREATE INDEX IF NOT EXISTS "lucky_rounds_roomId_status_idx" ON "lucky_rounds"("roomId", "status");
CREATE INDEX IF NOT EXISTS "lucky_rounds_startedAt_idx" ON "lucky_rounds"("startedAt");

ALTER TABLE "lucky_rolls" ADD COLUMN IF NOT EXISTS "roundId" INTEGER;
ALTER TABLE "lucky_rolls" ADD COLUMN IF NOT EXISTS "programCoins" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "lucky_rolls" ADD COLUMN IF NOT EXISTS "poolCoins" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "lucky_rolls" ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'SETTLED';
ALTER TABLE "lucky_rolls" ADD COLUMN IF NOT EXISTS "settledAt" TIMESTAMP(3);
CREATE INDEX IF NOT EXISTS "lucky_rolls_roundId_idx" ON "lucky_rolls"("roundId");
CREATE INDEX IF NOT EXISTS "lucky_rolls_roomId_createdAt_idx" ON "lucky_rolls"("roomId", "createdAt");

-- x30 joins the multiplier set.
INSERT INTO "lucky_tiers" ("multiplier", "weightBp", "minPoolCoins") VALUES (30, 150, 10000)
ON CONFLICT ("multiplier") DO NOTHING;

-- The shipped table returned E[m] × 10% = 78.2% of every lucky gift to the
-- sender, more than the 70% the new split puts in the prize pool — the pool
-- would drain. Rebalance to E[m] = 6.39 (RTP 63.9%) ONLY if the table is still
-- exactly the shipped default; an admin-tuned table is left alone (the
-- dashboard refuses to save it again until it fits, and says why).
DO $$
DECLARE untouched BOOLEAN;
BEGIN
  SELECT COUNT(*) = 8 INTO untouched FROM "lucky_tiers"
   WHERE ("multiplier","weightBp") IN ((5,4000),(10,2500),(20,800),(50,200),(100,35),(200,10),(300,4),(500,1));
  IF untouched THEN
    UPDATE "lucky_tiers" SET "weightBp" = CASE "multiplier"
      WHEN 5 THEN 3500 WHEN 10 THEN 2000 WHEN 20 THEN 700 WHEN 30 THEN 150
      WHEN 50 THEN 80 WHEN 100 THEN 20 WHEN 200 THEN 4 WHEN 300 THEN 2 WHEN 500 THEN 1
      ELSE "weightBp" END;
  END IF;
END $$;

-- ── CP: break fees, levels, effects ──────────────────────────
CREATE TABLE IF NOT EXISTS "cp_break_custom_fees" (
    "userId" INTEGER NOT NULL,
    "programFee" BIGINT NOT NULL DEFAULT 0,
    "partnerFee" BIGINT NOT NULL DEFAULT 0,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "note" TEXT,
    "updatedBy" INTEGER,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "cp_break_custom_fees_pkey" PRIMARY KEY ("userId")
);

CREATE TABLE IF NOT EXISTS "cp_break_logs" (
    "id" SERIAL NOT NULL,
    "pairId" INTEGER NOT NULL,
    "requesterId" INTEGER NOT NULL,
    "partnerId" INTEGER NOT NULL,
    "programFee" BIGINT NOT NULL,
    "partnerFee" BIGINT NOT NULL,
    "feeSource" TEXT NOT NULL,
    "cpValue" INTEGER NOT NULL DEFAULT 0,
    "pairCreatedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "cp_break_logs_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "cp_break_logs_requesterId_createdAt_idx" ON "cp_break_logs"("requesterId", "createdAt");
CREATE INDEX IF NOT EXISTS "cp_break_logs_partnerId_createdAt_idx" ON "cp_break_logs"("partnerId", "createdAt");

CREATE TABLE IF NOT EXISTS "cp_levels" (
    "level" INTEGER NOT NULL,
    "requiredCoins" BIGINT NOT NULL,
    "name" TEXT,
    "badgeUrl" TEXT,
    "frameUrl" TEXT,
    "effectKey" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "cp_levels_pkey" PRIMARY KEY ("level")
);
-- No rows on purpose: while cp_levels is empty every pair keeps the level it
-- has today (cp_level_step_coins / days ladder). The admin fills it in.

CREATE TABLE IF NOT EXISTS "cp_effects" (
    "id" SERIAL NOT NULL,
    "effectKey" TEXT NOT NULL,
    "name" TEXT,
    "requiredLevel" INTEGER NOT NULL DEFAULT 1,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "durationSec" INTEGER NOT NULL DEFAULT 0,
    "animationSpeed" DOUBLE PRECISION NOT NULL DEFAULT 1,
    "priority" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "cp_effects_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "cp_effects_effectKey_key" ON "cp_effects"("effectKey");
-- The one effect the app ships (a 3D heart around the two seats). Off until the
-- admin switches it on.
INSERT INTO "cp_effects" ("effectKey", "name", "requiredLevel", "enabled", "durationSec", "animationSpeed", "priority")
VALUES ('heart3d', 'قلب ثلاثي الأبعاد', 3, false, 0, 1, 10)
ON CONFLICT ("effectKey") DO NOTHING;
