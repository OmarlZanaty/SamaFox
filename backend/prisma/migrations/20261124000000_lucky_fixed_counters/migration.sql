-- x5 / x10 are fixed, independent forever-counters (client rule 24/11): never blocked by the
-- bigger tiers. Idempotent; apply by hand BEFORE deploying the matching backend.
BEGIN;
ALTER TABLE "lucky_control_rows" ADD COLUMN IF NOT EXISTS "fixed5" INTEGER NOT NULL DEFAULT 0 CHECK ("fixed5" >= 0);
ALTER TABLE "lucky_control_rows" ADD COLUMN IF NOT EXISTS "fixed10" INTEGER NOT NULL DEFAULT 0 CHECK ("fixed10" >= 0);
ALTER TABLE "lucky_control_rows" ADD COLUMN IF NOT EXISTS "testFixed5" INTEGER NOT NULL DEFAULT 0 CHECK ("testFixed5" >= 0);
ALTER TABLE "lucky_control_rows" ADD COLUMN IF NOT EXISTS "testFixed10" INTEGER NOT NULL DEFAULT 0 CHECK ("testFixed10" >= 0);
COMMIT;
