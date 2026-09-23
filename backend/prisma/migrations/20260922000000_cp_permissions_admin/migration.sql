-- ============================================================
-- 2026-09-22 — صلاحيات فتح CP + إدارة نظام CP والخلفيات
--
-- Every statement is additive and idempotent (IF NOT EXISTS / defaults), so
-- it is safe on the live database:
--   * no row in "users", "user_items" (background ownership) or "cp_pairs"
--     is deleted or has an existing column rewritten;
--   * the level shown for every existing pair does not move: the new
--     cp_level_step_coins setting defaults to 0, which keeps the days-based
--     ladder the app already uses;
--   * the system unlock policy defaults to "free", i.e. exactly today's
--     behaviour, until an admin changes it from the dashboard.
-- ============================================================

-- "مستخدم CP الظاهر" moves from the device to the server.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "cpFeaturedPartnerId" INTEGER;

-- CP level value + admin override on the pair.
ALTER TABLE "cp_pairs" ADD COLUMN IF NOT EXISTS "cpValue" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "cp_pairs" ADD COLUMN IF NOT EXISTS "levelOverride" INTEGER;
ALTER TABLE "cp_pairs" ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Per-user unlock permission ("فتح CP مجانًا" / "فتح CP برسوم").
CREATE TABLE IF NOT EXISTS "cp_unlock_grants" (
  "id"          SERIAL NOT NULL,
  "userId"      INTEGER NOT NULL,
  "mode"        TEXT NOT NULL,
  "feeCoins"    INTEGER NOT NULL DEFAULT 0,
  "note"        TEXT,
  "grantedById" INTEGER NOT NULL,
  "grantedAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cp_unlock_grants_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "cp_unlock_grants_userId_key" ON "cp_unlock_grants"("userId");
CREATE INDEX IF NOT EXISTS "cp_unlock_grants_grantedById_idx" ON "cp_unlock_grants"("grantedById");

-- Grant / change / revoke history — never deleted.
CREATE TABLE IF NOT EXISTS "cp_unlock_grant_history" (
  "id"        SERIAL NOT NULL,
  "userId"    INTEGER NOT NULL,
  "action"    TEXT NOT NULL,
  "mode"      TEXT NOT NULL,
  "feeCoins"  INTEGER NOT NULL DEFAULT 0,
  "note"      TEXT,
  "adminId"   INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cp_unlock_grant_history_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "cp_unlock_grant_history_userId_createdAt_idx"
  ON "cp_unlock_grant_history"("userId", "createdAt");

-- The account has opened CP (and what it paid for that).
CREATE TABLE IF NOT EXISTS "cp_unlocks" (
  "id"            SERIAL NOT NULL,
  "userId"        INTEGER NOT NULL,
  "paidCoins"     INTEGER NOT NULL DEFAULT 0,
  "source"        TEXT NOT NULL,
  "transactionId" INTEGER,
  "grantedById"   INTEGER,
  "createdAt"     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cp_unlocks_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "cp_unlocks_userId_key" ON "cp_unlocks"("userId");

-- Generic admin audit log.
CREATE TABLE IF NOT EXISTS "admin_audit_logs" (
  "id"           SERIAL NOT NULL,
  "adminId"      INTEGER NOT NULL,
  "action"       TEXT NOT NULL,
  "targetUserId" INTEGER,
  "targetType"   TEXT,
  "targetId"     TEXT,
  "before"       JSONB,
  "after"        JSONB,
  "ip"           TEXT,
  "createdAt"    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "admin_audit_logs_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "admin_audit_logs_adminId_createdAt_idx" ON "admin_audit_logs"("adminId", "createdAt");
CREATE INDEX IF NOT EXISTS "admin_audit_logs_targetUserId_createdAt_idx" ON "admin_audit_logs"("targetUserId", "createdAt");
CREATE INDEX IF NOT EXISTS "admin_audit_logs_action_createdAt_idx" ON "admin_audit_logs"("action", "createdAt");

-- هدايا CP ← مستوى CP (2026-09-24): per-gift level amount + the send log.
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "cpLevelPoints" INTEGER;

CREATE TABLE IF NOT EXISTS "cp_value_events" (
  "id"                SERIAL NOT NULL,
  "pairId"            INTEGER NOT NULL,
  "senderId"          INTEGER NOT NULL,
  "recipientId"       INTEGER NOT NULL,
  "giftId"            TEXT NOT NULL,
  "quantity"          INTEGER NOT NULL DEFAULT 1,
  "points"            INTEGER NOT NULL DEFAULT 0,
  "cpValueAfter"      INTEGER,
  "source"            TEXT NOT NULL,
  "giftTransactionId" TEXT,
  "requestKey"        TEXT,
  "createdAt"         TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cp_value_events_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "cp_value_events_giftTransactionId_key" ON "cp_value_events"("giftTransactionId");
CREATE UNIQUE INDEX IF NOT EXISTS "cp_value_events_senderId_requestKey_key" ON "cp_value_events"("senderId", "requestKey");
CREATE INDEX IF NOT EXISTS "cp_value_events_pairId_createdAt_idx" ON "cp_value_events"("pairId", "createdAt");
CREATE INDEX IF NOT EXISTS "cp_value_events_recipientId_createdAt_idx" ON "cp_value_events"("recipientId", "createdAt");

DO $$ BEGIN
  ALTER TABLE "cp_unlock_grants" ADD CONSTRAINT "cp_unlock_grants_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE "cp_unlocks" ADD CONSTRAINT "cp_unlocks_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ------------------------------------------------------------
-- Backfill — preserve what every existing user already has.
-- ------------------------------------------------------------

-- 1. cpValue: the coins of the gift that created each pair, read from the
--    accepted request (most recent accepted request between the two users).
--    Best effort: a pair with no matching request stays at 0, which with
--    cp_level_step_coins = 0 still displays exactly as before.
UPDATE "cp_pairs" p
SET "cpValue" = r."totalCoins"
FROM (
  SELECT DISTINCT ON (LEAST("senderId","recipientId"), GREATEST("senderId","recipientId"))
         LEAST("senderId","recipientId")    AS a,
         GREATEST("senderId","recipientId") AS b,
         "totalCoins"
  FROM "cp_requests"
  WHERE "status" = 'accepted'
  ORDER BY LEAST("senderId","recipientId"), GREATEST("senderId","recipientId"), "resolvedAt" DESC NULLS LAST, "id" DESC
) r
WHERE p."userAId" = r.a AND p."userBId" = r.b AND p."cpValue" = 0;

-- 2. Everyone who already has a pair, or ever sent an accepted CP request,
--    has CP open at no cost — a policy change later must not lock them out.
INSERT INTO "cp_unlocks" ("userId", "paidCoins", "source", "createdAt")
SELECT DISTINCT u.id, 0, 'legacy', CURRENT_TIMESTAMP
FROM "users" u
WHERE EXISTS (SELECT 1 FROM "cp_pairs" p WHERE p."userAId" = u.id OR p."userBId" = u.id)
   OR EXISTS (SELECT 1 FROM "cp_requests" r WHERE r."senderId" = u.id AND r."status" = 'accepted')
ON CONFLICT ("userId") DO NOTHING;

-- 2b. "مستخدم CP الظاهر": pin, for everyone who has a pair and no stored
--     choice, the partner visitors see TODAY (the newest pair). From here on
--     a new pair never takes the spot — only the owner (or an admin) changes
--     it. A choice the owner made on his phone is uploaded by the app once.
UPDATE "users" u
SET "cpFeaturedPartnerId" = x.partner
FROM (
  SELECT DISTINCT ON (me) me, partner
  FROM (
    SELECT "userAId" AS me, "userBId" AS partner, "createdAt", "id" FROM "cp_pairs"
    UNION ALL
    SELECT "userBId" AS me, "userAId" AS partner, "createdAt", "id" FROM "cp_pairs"
  ) s
  ORDER BY me, "createdAt" DESC, "id" DESC
) x
WHERE u."id" = x.me AND u."cpFeaturedPartnerId" IS NULL;

-- 3. System policy rows, only if absent: free (today's behaviour), 0 coins,
--    days-based level ladder.
INSERT INTO "app_settings" ("key", "value", "updatedAt") VALUES
  ('cp_unlock_mode',      'free', CURRENT_TIMESTAMP),
  ('cp_unlock_fee_coins', '0',    CURRENT_TIMESTAMP),
  ('cp_level_step_coins', '0',    CURRENT_TIMESTAMP),
  ('cp_level_max',        '5',    CURRENT_TIMESTAMP)
ON CONFLICT ("key") DO NOTHING;
