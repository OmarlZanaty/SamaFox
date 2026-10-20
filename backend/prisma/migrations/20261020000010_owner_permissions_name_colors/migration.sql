-- SPEC52 #42/#43/#7 (2026-10-20): Owner flag, owner-issued permissions,
-- audit device, VIP name colours. Additive only; safe to re-run.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "isOwner" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS "admin_permission_grants" (
  "id" SERIAL PRIMARY KEY,
  "userId" INTEGER NOT NULL,
  "permission" TEXT NOT NULL,
  "grantedBy" INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revokedAt" TIMESTAMP(3),
  "revokedBy" INTEGER
);
CREATE INDEX IF NOT EXISTS "admin_permission_grants_userId_revokedAt_idx" ON "admin_permission_grants" ("userId", "revokedAt");
CREATE UNIQUE INDEX IF NOT EXISTS "admin_permission_grants_one_active" ON "admin_permission_grants" ("userId", "permission") WHERE "revokedAt" IS NULL;

ALTER TABLE "admin_audit_logs" ADD COLUMN IF NOT EXISTS "device" TEXT;

ALTER TABLE "vip_level_configs" ADD COLUMN IF NOT EXISTS "nameColor" TEXT;
ALTER TABLE "vip_level_configs" ADD COLUMN IF NOT EXISTS "nameGradient" JSONB;
-- Default colours only where the owner has not chosen one yet.
UPDATE "vip_level_configs" SET "nameColor" = CASE "level"
    WHEN 1 THEN '#FFFFFF' WHEN 2 THEN '#4CAF50' WHEN 3 THEN '#2196F3'
    WHEN 4 THEN '#9C27B0' WHEN 5 THEN '#FFD700' END
  WHERE "nameColor" IS NULL AND "level" BETWEEN 1 AND 5;
