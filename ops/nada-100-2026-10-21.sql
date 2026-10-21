\pset pager off
SELECT id, "targetAdjustmentCoins" FROM "AgencyMember" WHERE id = 64 AND "userId" = 335;
UPDATE "AgencyMember" SET "targetAdjustmentCoins" = "targetAdjustmentCoins" - 100
WHERE id = 64 AND "userId" = 335 AND "targetAdjustmentCoins" = 100;
INSERT INTO target_movements ("memberId", "userId", "agencyId", kind, "amountCoins", "actorId", note, "createdAt")
SELECT 64, 335, 33, 'admin_deduct', -100, NULL, 'قبل 100 ← بعد 0 (بقايا تارجت الشحن، 2026-10-21)', now()
WHERE EXISTS (SELECT 1 FROM "AgencyMember" WHERE id = 64 AND "targetAdjustmentCoins" = 0);
SELECT id, "targetAdjustmentCoins" FROM "AgencyMember" WHERE id = 64;
