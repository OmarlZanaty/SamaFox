-- CreateEnum
CREATE TYPE "BetaTesterStatus" AS ENUM ('invited', 'opted_in', 'installed', 'dropped');

-- CreateTable
CREATE TABLE "beta_testers" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "googleSub" TEXT,
    "status" "BetaTesterStatus" NOT NULL DEFAULT 'invited',
    "source" TEXT,
    "playSynced" BOOLEAN NOT NULL DEFAULT false,
    "playError" TEXT,
    "enrolledAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastCheckedAt" TIMESTAMP(3),

    CONSTRAINT "beta_testers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "beta_testers_email_key" ON "beta_testers"("email");

-- CreateIndex
CREATE UNIQUE INDEX "beta_testers_googleSub_key" ON "beta_testers"("googleSub");

-- CreateIndex
CREATE INDEX "beta_testers_status_idx" ON "beta_testers"("status");
