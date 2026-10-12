-- نظام الإدارة والصلاحيات: Manager / Super Admin / Admin, their permissions,
-- agency scope, temporary grants and the ban record. New tables only.
CREATE TABLE IF NOT EXISTS "staff_roles" (
  "id" SERIAL PRIMARY KEY,
  "userId" INTEGER NOT NULL,
  "role" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "assignedById" INTEGER,
  "parentUserId" INTEGER,
  "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "endedAt" TIMESTAMP(3),
  "endedById" INTEGER,
  "endReason" TEXT,
  "allowedItemIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "rewardItemIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "staff_roles_userId_status_idx" ON "staff_roles" ("userId", "status");
CREATE INDEX IF NOT EXISTS "staff_roles_parentUserId_status_idx" ON "staff_roles" ("parentUserId", "status");
CREATE INDEX IF NOT EXISTS "staff_roles_status_expiresAt_idx" ON "staff_roles" ("status", "expiresAt");
-- One live appointment per user, held by the database as well as the code.
CREATE UNIQUE INDEX IF NOT EXISTS "staff_roles_one_active_per_user" ON "staff_roles" ("userId") WHERE "status" = 'ACTIVE';

CREATE TABLE IF NOT EXISTS "staff_permissions" (
  "id" SERIAL PRIMARY KEY,
  "userId" INTEGER NOT NULL,
  "staffRoleId" INTEGER,
  "permission" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "grantedById" INTEGER,
  "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3),
  "endedAt" TIMESTAMP(3),
  "endedById" INTEGER
);
CREATE INDEX IF NOT EXISTS "staff_permissions_userId_status_idx" ON "staff_permissions" ("userId", "status");
CREATE INDEX IF NOT EXISTS "staff_permissions_staffRoleId_idx" ON "staff_permissions" ("staffRoleId");
CREATE INDEX IF NOT EXISTS "staff_permissions_status_expiresAt_idx" ON "staff_permissions" ("status", "expiresAt");
CREATE UNIQUE INDEX IF NOT EXISTS "staff_permissions_one_active" ON "staff_permissions" ("userId", "permission") WHERE "status" = 'ACTIVE';

CREATE TABLE IF NOT EXISTS "staff_agency_scopes" (
  "id" SERIAL PRIMARY KEY,
  "staffUserId" INTEGER NOT NULL,
  "agencyId" INTEGER NOT NULL,
  "kind" TEXT NOT NULL DEFAULT 'CREATED',
  "assignedById" INTEGER,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS "staff_agency_scopes_staffUserId_agencyId_key" ON "staff_agency_scopes" ("staffUserId", "agencyId");
CREATE INDEX IF NOT EXISTS "staff_agency_scopes_agencyId_idx" ON "staff_agency_scopes" ("agencyId");

CREATE TABLE IF NOT EXISTS "temporary_entitlements" (
  "id" SERIAL PRIMARY KEY,
  "userId" INTEGER NOT NULL,
  "type" TEXT NOT NULL,
  "value" INTEGER,
  "itemId" TEXT,
  "itemType" TEXT,
  "previousValue" TEXT,
  "source" TEXT NOT NULL DEFAULT 'GRANT',
  "staffRoleId" INTEGER,
  "grantedById" INTEGER,
  "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "endedAt" TIMESTAMP(3),
  "endedById" INTEGER
);
CREATE INDEX IF NOT EXISTS "temporary_entitlements_userId_type_status_idx" ON "temporary_entitlements" ("userId", "type", "status");
CREATE INDEX IF NOT EXISTS "temporary_entitlements_status_expiresAt_idx" ON "temporary_entitlements" ("status", "expiresAt");
CREATE INDEX IF NOT EXISTS "temporary_entitlements_grantedById_startedAt_idx" ON "temporary_entitlements" ("grantedById", "startedAt");
CREATE INDEX IF NOT EXISTS "temporary_entitlements_staffRoleId_idx" ON "temporary_entitlements" ("staffRoleId");

CREATE TABLE IF NOT EXISTS "ban_records" (
  "id" SERIAL PRIMARY KEY,
  "userId" INTEGER NOT NULL,
  "bannedById" INTEGER NOT NULL,
  "duration" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3),
  "status" TEXT NOT NULL DEFAULT 'ACTIVE',
  "liftedAt" TIMESTAMP(3),
  "liftedById" INTEGER
);
CREATE INDEX IF NOT EXISTS "ban_records_userId_status_idx" ON "ban_records" ("userId", "status");
CREATE INDEX IF NOT EXISTS "ban_records_bannedById_startedAt_idx" ON "ban_records" ("bannedById", "startedAt");
