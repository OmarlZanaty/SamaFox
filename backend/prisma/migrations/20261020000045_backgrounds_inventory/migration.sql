-- SPEC52 #22 (2026-10-20): provenance on owned items + the named views.
ALTER TABLE "user_items" ADD COLUMN IF NOT EXISTS "source" TEXT;
ALTER TABLE "user_items" ADD COLUMN IF NOT EXISTS "grantedBy" INTEGER;
ALTER TABLE "user_items" ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'active';
-- Read-only views with the names the spec uses (no duplicated data).
CREATE OR REPLACE VIEW "room_backgrounds" AS
  SELECT "id", "name", "assetUrl", "previewUrl", "priceCoins", "isPurchasable", "durationDays"
  FROM "items" WHERE lower("type") = 'background';
CREATE OR REPLACE VIEW "user_background_inventory" AS
  SELECT ui."userId" AS "user_id", ui."itemId" AS "background_id", ui."source", ui."grantedBy" AS "granted_by",
         ui."acquiredAt" AS "purchased_at", ui."expiresAt" AS "expires_at",
         CASE WHEN ui."expiresAt" IS NOT NULL AND ui."expiresAt" < now() THEN 'expired' ELSE ui."status" END AS "status"
  FROM "user_items" ui JOIN "items" i ON i."id" = ui."itemId" WHERE lower(i."type") = 'background';
