-- Group 7: dashboard lock on agency name + attribution of agency charges
ALTER TABLE "charging_agencies" ADD COLUMN "nameLocked" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "transactions" ADD COLUMN "agencyId" INTEGER;
ALTER TABLE "transactions" ADD COLUMN "senderId" INTEGER;
CREATE INDEX "transactions_agencyId_idx" ON "transactions"("agencyId");
