-- Add user ban fields
ALTER TABLE "users" ADD COLUMN "isBanned" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "users" ADD COLUMN "bannedAt" DATETIME;
ALTER TABLE "users" ADD COLUMN "banReason" TEXT;
