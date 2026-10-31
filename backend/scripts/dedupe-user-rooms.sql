-- One room per account (client rule 31/10). Run by hand on deploy, once.
-- Keeps each owner's most used USER room (highest xp, then newest) and closes
-- the others (isActive = false). Nothing is deleted, so a closed room can be
-- reopened from the dashboard.
--
-- 1) Preview: psql ... -f dedupe-user-rooms.sql  (runs inside one transaction
--    and prints what it closes; change ROLLBACK to COMMIT to apply.)
BEGIN;

WITH ranked AS (
  SELECT id, "ownerId", name, xp, "createdAt",
         row_number() OVER (PARTITION BY "ownerId" ORDER BY xp DESC, id DESC) AS rn
  FROM rooms
  WHERE "roomType" = 'USER' AND "isActive" = true
)
SELECT r."ownerId", u."displayId", r.id AS room_id, r.name, r.xp, r.rn = 1 AS kept
FROM ranked r JOIN users u ON u.id = r."ownerId"
WHERE r."ownerId" IN (SELECT "ownerId" FROM ranked WHERE rn > 1)
ORDER BY r."ownerId", r.rn;

UPDATE rooms SET "isActive" = false
WHERE id IN (
  SELECT id FROM (
    SELECT id, row_number() OVER (PARTITION BY "ownerId" ORDER BY xp DESC, id DESC) AS rn
    FROM rooms
    WHERE "roomType" = 'USER' AND "isActive" = true
  ) t WHERE rn > 1
);

ROLLBACK;
