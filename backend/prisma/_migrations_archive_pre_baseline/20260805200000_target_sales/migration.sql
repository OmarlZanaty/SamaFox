-- بيع التارجيت: target can now be sold from one account to another, so a
-- member's target is no longer just "gifts received since joining".
ALTER TABLE "AgencyMember" ADD COLUMN IF NOT EXISTS "targetAdjustmentCoins" BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "target_sales" (
    "id" SERIAL NOT NULL,
    "sellerId" INTEGER NOT NULL,
    "buyerId" INTEGER NOT NULL,
    "amountCoins" BIGINT NOT NULL,
    "sellerAgencyId" INTEGER NOT NULL,
    "buyerAgencyId" INTEGER NOT NULL,
    "dollarsValue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "target_sales_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "target_sales_sellerId_idx" ON "target_sales"("sellerId");
CREATE INDEX IF NOT EXISTS "target_sales_buyerId_idx" ON "target_sales"("buyerId");
