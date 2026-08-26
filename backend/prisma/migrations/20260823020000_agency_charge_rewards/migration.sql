-- B10: how many times each agency charged ITSELF, so the dashboard can rank
-- them and the owner can reward the biggest charger.
ALTER TABLE "charging_agencies" ADD COLUMN "selfChargeCount" INTEGER NOT NULL DEFAULT 0;
-- Highest reward rung already paid, so a ladder never pays the same rung twice.
ALTER TABLE "charging_agencies" ADD COLUMN "rewardedUpToCoins" BIGINT NOT NULL DEFAULT 0;

-- B11: dashboard-configured automatic reward when an agency's self-charging
-- passes a threshold.
CREATE TABLE "agency_charge_rewards" (
  "id"             SERIAL PRIMARY KEY,
  "thresholdCoins" BIGINT NOT NULL,
  "rewardCoins"    INTEGER NOT NULL DEFAULT 0,
  "rewardItemIds"  TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "agencyId"       INTEGER,
  "isActive"       BOOLEAN NOT NULL DEFAULT true,
  "createdAt"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"      TIMESTAMP(3) NOT NULL
);
CREATE INDEX "agency_charge_rewards_agencyId_idx" ON "agency_charge_rewards"("agencyId");

-- Backfill the counter from the top-up history that already exists.
UPDATE "charging_agencies" ca
SET "selfChargeCount" = sub.n
FROM (
  SELECT "agencyId", COUNT(*)::int AS n
  FROM "agency_topup_requests"
  WHERE status = 'approved'
  GROUP BY "agencyId"
) sub
WHERE ca.id = sub."agencyId";
