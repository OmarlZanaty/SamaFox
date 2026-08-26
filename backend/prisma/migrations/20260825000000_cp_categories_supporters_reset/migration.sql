-- ============================================================
-- 2026-08-25 client batch (WhatsApp 17/08 → 24/08)
--   B9  supporters-board counter reset
--   A16 animated-avatar permission per VIP tier
--   B4/B5/B6 gift lists (categories) as data instead of a hard-coded dropdown
--   A15 CP (couple pairing) requests + pairs
-- Every column is additive with a default, so the deploy is safe to run on the
-- live database without touching a single existing row's behaviour.
-- ============================================================

-- B9 — "تصفير العداد" in أعلى المستويات. Non-permanent by design: the board
-- counts gifts sent after this timestamp, so a reset account climbs straight
-- back with whatever it genuinely earns afterwards.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "supportersResetAt" TIMESTAMP(3);

-- A16 — animated (GIF/WEBP) profile photo, granted per VIP tier.
ALTER TABLE "vip_level_configs"
  ADD COLUMN IF NOT EXISTS "allowAnimatedAvatar" BOOLEAN NOT NULL DEFAULT false;

-- B4/B5/B6 — gift lists.
CREATE TABLE IF NOT EXISTS "gift_categories" (
  "id"        TEXT NOT NULL,
  "key"       TEXT NOT NULL,
  "nameAr"    TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "isActive"  BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "gift_categories_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "gift_categories_key_key" ON "gift_categories"("key");
CREATE INDEX IF NOT EXISTS "gift_categories_isActive_sortOrder_idx"
  ON "gift_categories"("isActive", "sortOrder");

-- Seed the lists the app already ships as a const map, using the SAME keys that
-- are already stored in gifts.category. Nothing is re-categorised; the tabs the
-- user sees today simply become editable rows.
INSERT INTO "gift_categories" ("id", "key", "nameAr", "sortOrder", "isActive", "createdAt", "updatedAt")
VALUES
  ('cat_love',          'love',          'العلاقة',        10, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_luxury',        'luxury',        'خاص',            20, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_lucky',         'lucky',         'محظوظ',          30, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_magic',         'magic',         'ماجيك',          40, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_flag',          'flag',          'علم',            50, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_bag',           'bag',           'كيس',            60, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_fun',           'fun',           'مرح',            70, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_festive',       'festive',       'مناسبات',        80, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_cp',            'cp',            'CP',             90, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_vip',           'vip',           'VIP',           100, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('cat_relation_ring', 'RELATION_RING', 'خاتم العلاقة',  110, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("key") DO NOTHING;

-- Any category key already sitting on a gift but missing from the seed above
-- becomes a list too, so no gift is orphaned into an invisible tab.
INSERT INTO "gift_categories" ("id", "key", "nameAr", "sortOrder", "isActive", "createdAt", "updatedAt")
SELECT 'cat_' || md5(g."category"), g."category", g."category", 500, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM (SELECT DISTINCT "category" FROM "gifts" WHERE "category" IS NOT NULL AND "category" <> '') g
ON CONFLICT ("key") DO NOTHING;

-- A15 — CP pairing.
CREATE TABLE IF NOT EXISTS "cp_pairs" (
  "id"        SERIAL NOT NULL,
  "userAId"   INTEGER NOT NULL,
  "userBId"   INTEGER NOT NULL,
  "giftId"    TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "cp_pairs_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "cp_pairs_userAId_userBId_key" ON "cp_pairs"("userAId", "userBId");
CREATE INDEX IF NOT EXISTS "cp_pairs_userAId_idx" ON "cp_pairs"("userAId");
CREATE INDEX IF NOT EXISTS "cp_pairs_userBId_idx" ON "cp_pairs"("userBId");

CREATE TABLE IF NOT EXISTS "cp_requests" (
  "id"          SERIAL NOT NULL,
  "senderId"    INTEGER NOT NULL,
  "recipientId" INTEGER NOT NULL,
  "giftId"      TEXT NOT NULL,
  "quantity"    INTEGER NOT NULL DEFAULT 1,
  "totalCoins"  INTEGER NOT NULL,
  "roomId"      INTEGER,
  "status"      TEXT NOT NULL DEFAULT 'pending',
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "resolvedAt"  TIMESTAMP(3),
  CONSTRAINT "cp_requests_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "cp_requests_recipientId_status_idx" ON "cp_requests"("recipientId", "status");
CREATE INDEX IF NOT EXISTS "cp_requests_senderId_status_idx" ON "cp_requests"("senderId", "status");

DO $$ BEGIN
  ALTER TABLE "cp_pairs" ADD CONSTRAINT "cp_pairs_userAId_fkey"
    FOREIGN KEY ("userAId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE "cp_pairs" ADD CONSTRAINT "cp_pairs_userBId_fkey"
    FOREIGN KEY ("userBId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE "cp_requests" ADD CONSTRAINT "cp_requests_senderId_fkey"
    FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE "cp_requests" ADD CONSTRAINT "cp_requests_recipientId_fkey"
    FOREIGN KEY ("recipientId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
