-- Agent commission goes to the agent's TARGET only, never to his wallet.
-- Accumulator lives on the OWNER's AgencyMember row; stays 0 for everyone else.
ALTER TABLE "AgencyMember" ADD COLUMN IF NOT EXISTS "commissionTargetCoins" BIGINT NOT NULL DEFAULT 0;

-- Mirror of the same commission on the member who GENERATED it, so the payout
-- can be gated per host on that host completing their target.
ALTER TABLE "AgencyMember" ADD COLUMN IF NOT EXISTS "commissionGeneratedCoins" BIGINT NOT NULL DEFAULT 0;
