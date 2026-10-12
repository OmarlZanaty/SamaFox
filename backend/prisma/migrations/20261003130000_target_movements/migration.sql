-- سجل تعديلات التارجت: every movement of a membership's target, with who did it.
CREATE TABLE IF NOT EXISTS "target_movements" (
  "id" SERIAL PRIMARY KEY,
  "memberId" INTEGER NOT NULL,
  "userId" INTEGER NOT NULL,
  "agencyId" INTEGER NOT NULL,
  "kind" TEXT NOT NULL,
  "amountCoins" BIGINT NOT NULL,
  "actorId" INTEGER,
  "counterpartId" INTEGER,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS "target_movements_userId_createdAt_idx" ON "target_movements" ("userId", "createdAt");
CREATE INDEX IF NOT EXISTS "target_movements_createdAt_idx" ON "target_movements" ("createdAt");

-- Backfill what history already holds, once (only into an empty table).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "target_movements") THEN
    RETURN;
  END IF;

  -- Admin adjustments on a membership row (logged generically by the dashboard).
  INSERT INTO "target_movements" ("memberId", "userId", "agencyId", "kind", "amountCoins", "actorId", "note", "createdAt")
  SELECT m."id", m."userId", m."agencyId",
         CASE WHEN (l."after"->'body'->>'amountCoins')::numeric > 0 THEN 'admin_add' ELSE 'admin_deduct' END,
         (l."after"->'body'->>'amountCoins')::numeric::bigint,
         l."adminId", 'من سجل المراجعة', l."createdAt"
  FROM "admin_audit_logs" l
  JOIN "AgencyMember" m
    ON m."id" = substring(l."targetId" from '^/agency-members/([0-9]+)/target-adjust$')::int
  WHERE l."targetId" ~ '^/agency-members/[0-9]+/target-adjust$'
    AND (l."after"->>'status') = '200'
    AND (l."after"->'body'->>'amountCoins') ~ '^-?[0-9]+(\.[0-9]+)?$';

  -- Admin adjustments addressed by user ID (displayId first, then the row id),
  -- landed on the membership the handler picks.
  INSERT INTO "target_movements" ("memberId", "userId", "agencyId", "kind", "amountCoins", "actorId", "note", "createdAt")
  SELECT m."id", m."userId", m."agencyId",
         CASE WHEN (l."after"->'body'->>'amountCoins')::numeric > 0 THEN 'admin_add' ELSE 'admin_deduct' END,
         (l."after"->'body'->>'amountCoins')::numeric::bigint,
         l."adminId", 'من سجل المراجعة', l."createdAt"
  FROM "admin_audit_logs" l
  JOIN LATERAL (
    SELECT u."id" FROM "users" u
    WHERE u."displayId" = substring(l."targetId" from '^/users/([0-9]+)/target-adjust$')::int
       OR u."id" = substring(l."targetId" from '^/users/([0-9]+)/target-adjust$')::int
    ORDER BY (u."displayId" = substring(l."targetId" from '^/users/([0-9]+)/target-adjust$')::int) DESC
    LIMIT 1
  ) u ON TRUE
  JOIN LATERAL (
    SELECT am.* FROM "AgencyMember" am JOIN "charging_agencies" a ON a."id" = am."agencyId"
    WHERE am."userId" = u."id"
      AND a."status" = 'approved'
      AND (a."type" = 'HOSTING' OR (a."type" = 'CHARGING' AND am."role" IN ('OWNER', 'BRANCH')))
    ORDER BY am."role" DESC, am."joinedAt" ASC
    LIMIT 1
  ) m ON TRUE
  WHERE l."targetId" ~ '^/users/[0-9]+/target-adjust$'
    AND (l."after"->>'status') = '200'
    AND (l."after"->'body'->>'amountCoins') ~ '^-?[0-9]+(\.[0-9]+)?$';

  -- Target sales: the seller's side and the buyer's side.
  INSERT INTO "target_movements" ("memberId", "userId", "agencyId", "kind", "amountCoins", "actorId", "counterpartId", "createdAt")
  SELECT m."id", s."sellerId", s."sellerAgencyId", 'sale_out', -s."amountCoins", s."sellerId", s."buyerId", s."createdAt"
  FROM "target_sales" s
  JOIN LATERAL (
    SELECT am."id" FROM "AgencyMember" am
    WHERE am."userId" = s."sellerId" AND am."agencyId" = s."sellerAgencyId" LIMIT 1
  ) m ON TRUE;

  INSERT INTO "target_movements" ("memberId", "userId", "agencyId", "kind", "amountCoins", "actorId", "counterpartId", "createdAt")
  SELECT m."id", s."buyerId", s."buyerAgencyId", 'sale_in', s."amountCoins", s."sellerId", s."sellerId", s."createdAt"
  FROM "target_sales" s
  JOIN LATERAL (
    SELECT am."id" FROM "AgencyMember" am
    WHERE am."userId" = s."buyerId" AND am."agencyId" = s."buyerAgencyId" LIMIT 1
  ) m ON TRUE;
END $$;
