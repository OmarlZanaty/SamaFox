-- Gift System V2 — production gift catalog
-- Adds new tables in parallel to legacy `gifts` / `gift_logs`.
-- PostgreSQL only.

-- CreateEnum
CREATE TYPE "GiftFormat" AS ENUM ('SVG_CSS', 'VIDEO');

-- CreateEnum
CREATE TYPE "GiftTier" AS ENUM ('SMALL', 'MEDIUM', 'LARGE', 'LEGENDARY');

-- CreateEnum
CREATE TYPE "GiftAuditAction" AS ENUM ('CREATE', 'UPDATE', 'DELETE', 'ACTIVATE', 'DEACTIVATE', 'REORDER');

-- CreateTable
CREATE TABLE "gifts_v2" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "nameAr" TEXT,
    "iconUrl" TEXT NOT NULL,
    "format" "GiftFormat" NOT NULL,
    "animationHtml" TEXT,
    "animationUrl" TEXT,
    "videoHasAlpha" BOOLEAN NOT NULL DEFAULT false,
    "fireworksEnabled" BOOLEAN NOT NULL DEFAULT false,
    "fireworksColors" JSONB,
    "coinCost" INTEGER NOT NULL,
    "tier" "GiftTier" NOT NULL,
    "animationMs" INTEGER NOT NULL DEFAULT 3000,
    "isComboEligible" BOOLEAN NOT NULL DEFAULT true,
    "broadcastGlobal" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "category" TEXT,
    "createdBy" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "gifts_v2_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "gifts_v2_tier_isActive_sortOrder_idx" ON "gifts_v2"("tier", "isActive", "sortOrder");
CREATE INDEX "gifts_v2_category_isActive_idx" ON "gifts_v2"("category", "isActive");

-- CreateTable
CREATE TABLE "gift_v2_transactions" (
    "id" TEXT NOT NULL,
    "senderId" INTEGER NOT NULL,
    "recipientId" INTEGER NOT NULL,
    "roomId" INTEGER,
    "giftId" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "totalCoins" INTEGER NOT NULL,
    "comboKey" TEXT,
    "comboCount" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gift_v2_transactions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "gift_v2_transactions_roomId_createdAt_idx" ON "gift_v2_transactions"("roomId", "createdAt");
CREATE INDEX "gift_v2_transactions_senderId_createdAt_idx" ON "gift_v2_transactions"("senderId", "createdAt");
CREATE INDEX "gift_v2_transactions_recipientId_createdAt_idx" ON "gift_v2_transactions"("recipientId", "createdAt");

-- AddForeignKey
ALTER TABLE "gift_v2_transactions"
  ADD CONSTRAINT "gift_v2_transactions_senderId_fkey"
  FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "gift_v2_transactions"
  ADD CONSTRAINT "gift_v2_transactions_recipientId_fkey"
  FOREIGN KEY ("recipientId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "gift_v2_transactions"
  ADD CONSTRAINT "gift_v2_transactions_giftId_fkey"
  FOREIGN KEY ("giftId") REFERENCES "gifts_v2"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "gift_v2_transactions"
  ADD CONSTRAINT "gift_v2_transactions_roomId_fkey"
  FOREIGN KEY ("roomId") REFERENCES "rooms"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "gift_v2_broadcasts" (
    "id" TEXT NOT NULL,
    "transactionId" TEXT NOT NULL,
    "fromRoomId" INTEGER,
    "giftId" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gift_v2_broadcasts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "gift_v2_broadcasts_transactionId_key" ON "gift_v2_broadcasts"("transactionId");
CREATE INDEX "gift_v2_broadcasts_expiresAt_idx" ON "gift_v2_broadcasts"("expiresAt");

-- CreateTable
CREATE TABLE "gift_v2_admin_audits" (
    "id" TEXT NOT NULL,
    "adminId" INTEGER NOT NULL,
    "giftId" TEXT,
    "action" "GiftAuditAction" NOT NULL,
    "diff" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gift_v2_admin_audits_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "gift_v2_admin_audits_giftId_createdAt_idx" ON "gift_v2_admin_audits"("giftId", "createdAt");
CREATE INDEX "gift_v2_admin_audits_adminId_createdAt_idx" ON "gift_v2_admin_audits"("adminId", "createdAt");
