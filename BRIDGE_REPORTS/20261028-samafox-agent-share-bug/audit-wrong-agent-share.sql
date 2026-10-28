-- READ-ONLY audit: who received the 20% agent share without being the registered
-- hosts-agency agent. SELECT only. NOT run against any database by the author.
-- Run manually on the server inside a read-only transaction, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'BEGIN READ ONLY;' -f audit-wrong-agent-share.sql
-- Table names follow prisma/schema.prisma ("AgencyMember" and "User" have no @@map).

-- Q1. Any non-OWNER seat that holds agent-commission target. Must be 0 rows.
--     (BRANCH/MEMBER rows should always have commissionTargetCoins = 0.)
SELECT m.id AS member_id, m."agencyId", a."agencyName", a.type, m."userId", u.name,
       m.role, m."commissionTargetCoins"
FROM "AgencyMember" m
JOIN charging_agencies a ON a.id = m."agencyId"
JOIN "User" u ON u.id = m."userId"
WHERE m.role <> 'OWNER' AND m."commissionTargetCoins" > 0
ORDER BY m."commissionTargetCoins" DESC;

-- Q2. OWNER seats held by someone other than the registered agent
--     (ChargingAgency.userId), and agencies with more than one OWNER seat.
SELECT m.id AS member_id, m."agencyId", a."agencyName", a."userId" AS registered_agent,
       m."userId" AS owner_seat_holder, m."commissionTargetCoins"
FROM "AgencyMember" m
JOIN charging_agencies a ON a.id = m."agencyId"
WHERE m.role = 'OWNER' AND m."userId" <> a."userId"
ORDER BY m."agencyId";

SELECT "agencyId", count(*) AS owner_seats
FROM "AgencyMember" WHERE role = 'OWNER'
GROUP BY "agencyId" HAVING count(*) > 1;

-- Q3. Commission notifications (one per gift) paid to anyone who is not the
--     registered agent of the agency named in the notification. Per-user total
--     = the amount wrongly accrued as target.
SELECT n."userId", u.name, a."agencyName", a."userId" AS registered_agent,
       count(*) AS gifts, sum((n.data->>'amount')::bigint) AS wrong_commission_coins,
       min(n."createdAt") AS first_at, max(n."createdAt") AS last_at
FROM notifications n
JOIN "User" u ON u.id = n."userId"
JOIN charging_agencies a ON a.id = (n.data->>'agencyId')::int
WHERE n.type = 'AGENCY_COMMISSION' AND n."userId" <> a."userId"
GROUP BY n."userId", u.name, a."agencyName", a."userId"
ORDER BY wrong_commission_coins DESC;

-- Q4. Everyone who holds commission target on a hosting agency, with how they
--     were appointed (assignedByAdminId set = admin-appointed agent). Compare
--     against the list of REAL hosts-agency agents to spot appointees.
SELECT m."userId", u.name, u."displayId", m.role, a.id AS agency_id, a."agencyName",
       a."assignedByAdminId", m."commissionTargetCoins", m."convertedTargetCoins"
FROM "AgencyMember" m
JOIN charging_agencies a ON a.id = m."agencyId" AND a.type = 'HOSTING'
JOIN "User" u ON u.id = m."userId"
WHERE m."commissionTargetCoins" > 0
ORDER BY m."commissionTargetCoins" DESC;

-- Q5. Of the wrong amount, how much was already cashed out (تبديل/بيع)?
--     Cashing out books negative movements on the same seat.
SELECT t."userId", t.kind, count(*) AS n, sum(t."amountCoins") AS coins
FROM target_movements t
WHERE t.kind IN ('convert','sale_out')
  AND t."userId" IN (
    SELECT m."userId" FROM "AgencyMember" m
    WHERE m.role <> 'OWNER' AND m."commissionTargetCoins" > 0
  )
GROUP BY t."userId", t.kind;
