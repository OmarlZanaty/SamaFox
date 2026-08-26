-- 2026-08-23 — تبديل التارجيت now DEDUCTS from the target (client request:
-- "عند تبديل التارجيت او بيعه يخصم العدد الذي قمت بتبديله او بيعه من التارجيت
-- عندي وايضا يخصم قيمته بالدولار").
--
-- Until now a conversion only incremented `convertedTargetCoins`, which acted
-- as a spending cap while the displayed target stayed put. The controller now
-- books the withdrawal on `targetAdjustmentCoins` instead and no longer
-- subtracts `convertedTargetCoins` when computing what is still convertible.
--
-- This one-off reconciles history: every past conversion is applied to the
-- adjustment column so it is not handed back a second time. `convertedTargetCoins`
-- is left intact — it is now purely the lifetime "كم بدّلت" counter the target
-- card shows.
UPDATE "AgencyMember"
SET "targetAdjustmentCoins" = "targetAdjustmentCoins" - "convertedTargetCoins"
WHERE "convertedTargetCoins" > 0;
