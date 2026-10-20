CREATE TABLE IF NOT EXISTS "agency_profile_changes" (
  "id" SERIAL PRIMARY KEY, "agencyId" INTEGER NOT NULL REFERENCES "charging_agencies"("id"),
  "field" TEXT NOT NULL CHECK ("field" IN ('name','image')),
  "oldValue" TEXT NOT NULL, "newValue" TEXT NOT NULL,
  "changedBy" INTEGER NOT NULL REFERENCES "users"("id"), "changedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "agency_profile_changes_agencyId_changedAt_idx" ON "agency_profile_changes"("agencyId","changedAt");

ALTER TABLE "AgencyInvite" ADD COLUMN IF NOT EXISTS "resentAt" TIMESTAMP(3);
ALTER TABLE "AgencyInvite" ADD COLUMN IF NOT EXISTS "resendCount" INTEGER NOT NULL DEFAULT 0;
DROP INDEX IF EXISTS "AgencyInvite_agencyId_inviteeId_key";
CREATE INDEX IF NOT EXISTS "AgencyInvite_agencyId_inviteeId_idx" ON "AgencyInvite"("agencyId","inviteeId");
CREATE INDEX IF NOT EXISTS "AgencyInvite_status_expiresAt_idx" ON "AgencyInvite"("status","expiresAt");
CREATE UNIQUE INDEX IF NOT EXISTS "AgencyInvite_pending_pair_key" ON "AgencyInvite"("agencyId","inviteeId") WHERE "status" = 'pending';

CREATE TABLE IF NOT EXISTS "agency_branches" (
  "id" SERIAL PRIMARY KEY, "parentAgencyId" INTEGER NOT NULL REFERENCES "charging_agencies"("id"),
  "name" TEXT NOT NULL, "ownerUserId" INTEGER NOT NULL REFERENCES "users"("id"),
  "status" TEXT NOT NULL DEFAULT 'ACTIVE' CHECK ("status" IN ('ACTIVE','SUSPENDED','CLOSED')),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS "agency_branches_parentAgencyId_ownerUserId_key" ON "agency_branches"("parentAgencyId","ownerUserId");
INSERT INTO "agency_branches" ("parentAgencyId","ownerUserId","name","createdAt","updatedAt")
SELECT m."agencyId",m."userId",u."name",m."joinedAt",CURRENT_TIMESTAMP
FROM "AgencyMember" m JOIN "users" u ON u."id"=m."userId"
JOIN "charging_agencies" a ON a."id"=m."agencyId"
WHERE m."role"='BRANCH' AND a."type"='CHARGING'
ON CONFLICT ("parentAgencyId","ownerUserId") DO NOTHING;

ALTER TABLE "agency_transfers" ADD COLUMN IF NOT EXISTS "branchId" INTEGER REFERENCES "agency_branches"("id");
ALTER TABLE "agency_transfers" ADD COLUMN IF NOT EXISTS "actorUserId" INTEGER REFERENCES "users"("id");
ALTER TABLE "agency_transfers" ADD COLUMN IF NOT EXISTS "transactionId" INTEGER REFERENCES "transactions"("id");
CREATE UNIQUE INDEX IF NOT EXISTS "agency_transfers_transactionId_key" ON "agency_transfers"("transactionId");
CREATE INDEX IF NOT EXISTS "agency_transfers_agencyId_branchId_idx" ON "agency_transfers"("agencyId","branchId");
ALTER TABLE "agency_topup_requests" ADD COLUMN IF NOT EXISTS "branchId" INTEGER REFERENCES "agency_branches"("id");
ALTER TABLE "agency_topup_requests" ADD COLUMN IF NOT EXISTS "transactionId" INTEGER REFERENCES "transactions"("id");
CREATE UNIQUE INDEX IF NOT EXISTS "agency_topup_requests_transactionId_key" ON "agency_topup_requests"("transactionId");

CREATE TABLE IF NOT EXISTS "user_auth_methods" (
  "id" SERIAL PRIMARY KEY, "userId" INTEGER NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "provider" TEXT NOT NULL CHECK ("provider" IN ('google','phone','email','facebook')),
  "providerUserId" TEXT, "phoneNumber" TEXT, "verified" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS "user_auth_methods_provider_providerUserId_key" ON "user_auth_methods"("provider","providerUserId");
CREATE UNIQUE INDEX IF NOT EXISTS "user_auth_methods_phoneNumber_key" ON "user_auth_methods"("phoneNumber") WHERE "phoneNumber" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "user_auth_methods_userId_provider_idx" ON "user_auth_methods"("userId","provider");
INSERT INTO "user_auth_methods" ("userId","provider","providerUserId","verified")
SELECT "id",'google',"googleId",true FROM "users" WHERE "googleId" IS NOT NULL
ON CONFLICT ("provider","providerUserId") DO NOTHING;

CREATE TABLE IF NOT EXISTS "phone_otp_challenges" (
  "id" SERIAL PRIMARY KEY, "userId" INTEGER NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "phoneNumber" TEXT NOT NULL, "codeHash" TEXT NOT NULL, "salt" TEXT NOT NULL,
  "provider" TEXT NOT NULL DEFAULT 'local', "providerReference" TEXT,
  "expiresAt" TIMESTAMP(3) NOT NULL, "attempts" INTEGER NOT NULL DEFAULT 0,
  "consumedAt" TIMESTAMP(3), "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "phone_otp_challenges_userId_createdAt_idx" ON "phone_otp_challenges"("userId","createdAt");
CREATE INDEX IF NOT EXISTS "phone_otp_challenges_phoneNumber_createdAt_idx" ON "phone_otp_challenges"("phoneNumber","createdAt");
