-- Per-member target goal (#13, #24). Additive & safe: new column, default 0,
-- so existing rows are unaffected and no data is rewritten.
ALTER TABLE "AgencyMember" ADD COLUMN "targetGoalCoins" BIGINT NOT NULL DEFAULT 0;
