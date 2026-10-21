-- 2026-10-21 — undo the target that charging credited (client rule: only gifts
-- and bought target feed a وكيل شحن's target). One reversal row per membership,
-- logged in target_movements (سجل تعديلات التارجت). Idempotent: a membership that
-- already has a charge_reversal is skipped. Run with psql -1 (single transaction).
\pset pager off
CREATE TEMP TABLE rev AS
SELECT t."memberId", t."userId", t."agencyId", SUM(t."amountCoins")::bigint AS coins
FROM target_movements t
WHERE t.kind = 'charge'
  AND NOT EXISTS (SELECT 1 FROM target_movements r WHERE r."memberId" = t."memberId" AND r.kind = 'charge_reversal')
GROUP BY 1, 2, 3;

SELECT r.*, u."displayId", u.name, m."targetAdjustmentCoins" AS adj_before, m."targetAdjustmentCoins" - r.coins AS adj_after
FROM rev r JOIN users u ON u.id = r."userId" JOIN "AgencyMember" m ON m.id = r."memberId" ORDER BY r.coins DESC;

UPDATE "AgencyMember" m SET "targetAdjustmentCoins" = m."targetAdjustmentCoins" - r.coins
FROM rev r WHERE m.id = r."memberId";

INSERT INTO target_movements ("memberId", "userId", "agencyId", kind, "amountCoins", "actorId", note, "createdAt")
SELECT r."memberId", r."userId", r."agencyId", 'charge_reversal', -r.coins, NULL,
       'إلغاء تارجت الشحن (قاعدة العميل 2026-10-21)', now()
FROM rev r;
