-- Unify gift system: drop legacy `gifts` / `gift_logs` tables and rename the
-- v2 tables to drop the V2 suffix so there is a single canonical gift system.
-- PostgreSQL only. Builds on top of 20260516000000_gift_v2.

-- 1) Drop legacy tables.
DROP TABLE IF EXISTS "gift_logs";
DROP TABLE IF EXISTS "gifts";

-- 2) Rename v2 tables to their canonical names.
ALTER TABLE "gifts_v2" RENAME TO "gifts";
ALTER TABLE "gift_v2_transactions" RENAME TO "gift_transactions";
ALTER TABLE "gift_v2_broadcasts" RENAME TO "gift_broadcasts";
ALTER TABLE "gift_v2_admin_audits" RENAME TO "gift_admin_audits";

-- 3) Rename primary key / unique / index constraints to match the new table names.
ALTER TABLE "gifts" RENAME CONSTRAINT "gifts_v2_pkey" TO "gifts_pkey";
ALTER INDEX "gifts_v2_tier_isActive_sortOrder_idx" RENAME TO "gifts_tier_isActive_sortOrder_idx";
ALTER INDEX "gifts_v2_category_isActive_idx" RENAME TO "gifts_category_isActive_idx";

ALTER TABLE "gift_transactions" RENAME CONSTRAINT "gift_v2_transactions_pkey" TO "gift_transactions_pkey";
ALTER INDEX "gift_v2_transactions_roomId_createdAt_idx" RENAME TO "gift_transactions_roomId_createdAt_idx";
ALTER INDEX "gift_v2_transactions_senderId_createdAt_idx" RENAME TO "gift_transactions_senderId_createdAt_idx";
ALTER INDEX "gift_v2_transactions_recipientId_createdAt_idx" RENAME TO "gift_transactions_recipientId_createdAt_idx";

ALTER TABLE "gift_broadcasts" RENAME CONSTRAINT "gift_v2_broadcasts_pkey" TO "gift_broadcasts_pkey";
ALTER INDEX "gift_v2_broadcasts_transactionId_key" RENAME TO "gift_broadcasts_transactionId_key";
ALTER INDEX "gift_v2_broadcasts_expiresAt_idx" RENAME TO "gift_broadcasts_expiresAt_idx";

ALTER TABLE "gift_admin_audits" RENAME CONSTRAINT "gift_v2_admin_audits_pkey" TO "gift_admin_audits_pkey";
ALTER INDEX "gift_v2_admin_audits_giftId_createdAt_idx" RENAME TO "gift_admin_audits_giftId_createdAt_idx";
ALTER INDEX "gift_v2_admin_audits_adminId_createdAt_idx" RENAME TO "gift_admin_audits_adminId_createdAt_idx";

-- 4) Rename foreign-key constraints.
ALTER TABLE "gift_transactions" RENAME CONSTRAINT "gift_v2_transactions_senderId_fkey" TO "gift_transactions_senderId_fkey";
ALTER TABLE "gift_transactions" RENAME CONSTRAINT "gift_v2_transactions_recipientId_fkey" TO "gift_transactions_recipientId_fkey";
ALTER TABLE "gift_transactions" RENAME CONSTRAINT "gift_v2_transactions_giftId_fkey" TO "gift_transactions_giftId_fkey";
ALTER TABLE "gift_transactions" RENAME CONSTRAINT "gift_v2_transactions_roomId_fkey" TO "gift_transactions_roomId_fkey";
