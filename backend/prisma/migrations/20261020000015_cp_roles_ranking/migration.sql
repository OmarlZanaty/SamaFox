-- SPEC52 #8/#10/#34 (2026-10-20): CP gift roles + CP ranking fields.
-- Additive; existing CP gifts keep doing both (activate + level up).
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "cpActivate" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "gifts" ADD COLUMN IF NOT EXISTS "cpLevelUp" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "cp_value_events" ADD COLUMN IF NOT EXISTS "coins" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "cp_pairs" ADD COLUMN IF NOT EXISTS "cpCoins" BIGINT NOT NULL DEFAULT 0;
ALTER TABLE "cp_pairs" ADD COLUMN IF NOT EXISTS "lastLevel" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "cp_pairs" ADD COLUMN IF NOT EXISTS "levelReachedAt" TIMESTAMP(3);

-- Backfill coins from the committed gift each CP event points to (once).
UPDATE "cp_value_events" e SET "coins" = COALESCE(NULLIF(g."paidCoins", 0), g."totalCoins")
  FROM "gift_transactions" g
  WHERE e."giftTransactionId" = g."id" AND e."coins" = 0;
UPDATE "cp_pairs" p SET "cpCoins" = s.total
  FROM (SELECT "pairId", SUM("coins")::BIGINT AS total FROM "cp_value_events" GROUP BY "pairId") s
  WHERE s."pairId" = p."id" AND p."cpCoins" = 0;
-- Historical level-reached time cannot be reconstructed exactly; the last CP
-- event (or the pairing) is the best honest approximation.
UPDATE "cp_pairs" p SET "levelReachedAt" = COALESCE(
    (SELECT MAX(e."createdAt") FROM "cp_value_events" e WHERE e."pairId" = p."id"), p."createdAt")
  WHERE p."levelReachedAt" IS NULL;
CREATE INDEX IF NOT EXISTS "cp_pairs_rank_idx" ON "cp_pairs" ("cpValue" DESC, "cpCoins" DESC);

-- SPEC52 #38 — gift lists get a picture; «عام» becomes a real list.
ALTER TABLE "gift_categories" ADD COLUMN IF NOT EXISTS "imageUrl" TEXT;
INSERT INTO "gift_categories" ("id", "key", "nameAr", "sortOrder", "isActive", "createdAt", "updatedAt")
  SELECT 'general_list', 'general', 'عام', -100, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  WHERE NOT EXISTS (SELECT 1 FROM "gift_categories" WHERE "key" = 'general');
