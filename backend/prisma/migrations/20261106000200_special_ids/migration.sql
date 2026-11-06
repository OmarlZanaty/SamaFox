CREATE TABLE "user_special_ids" (
  "id" SERIAL PRIMARY KEY,
  "userId" INTEGER NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "displayId" INTEGER NOT NULL,
  "originalDisplayId" INTEGER,
  "expiresAt" TIMESTAMP(3),
  "source" TEXT NOT NULL DEFAULT 'store' CHECK ("source" IN ('store', 'gift', 'admin')),
  "grantedBy" INTEGER,
  "status" TEXT NOT NULL DEFAULT 'active' CHECK ("status" IN ('active', 'revoked', 'expired')),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "user_special_ids_userId_status_idx" ON "user_special_ids"("userId", "status");
CREATE INDEX "user_special_ids_status_expiresAt_idx" ON "user_special_ids"("status", "expiresAt");
CREATE UNIQUE INDEX "user_special_ids_active_user" ON "user_special_ids"("userId") WHERE "status" = 'active';
CREATE UNIQUE INDEX "user_special_ids_active_display" ON "user_special_ids"("displayId") WHERE "status" = 'active';
ALTER TABLE "store_orders" ADD COLUMN "recipientUserId" INTEGER;
-- Accounts without an original display ID must be restorable to NULL too.
ALTER TABLE "display_id_history" ALTER COLUMN "newId" DROP NOT NULL;

-- Protect original IDs even from existing allocators/manual assignment paths.
CREATE FUNCTION "protect_special_original_id"() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW."displayId" IS NOT NULL AND EXISTS (
    SELECT 1 FROM "user_special_ids" WHERE "status" = 'active'
      AND "originalDisplayId" = NEW."displayId" AND "userId" <> NEW."id"
  ) THEN
    RAISE EXCEPTION 'Display ID reserved for restoration' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER "protect_special_original_id" BEFORE INSERT OR UPDATE OF "displayId" ON "users"
FOR EACH ROW EXECUTE FUNCTION "protect_special_original_id"();
