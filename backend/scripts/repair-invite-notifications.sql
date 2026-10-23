BEGIN;

-- 2026-10-23 — restore the action buttons only on the newest live invite notice.
WITH latest AS (
  SELECT DISTINCT ON (i.id) n.id
  FROM notifications n
  JOIN "AgencyInvite" i ON i.id = (n.data->>'inviteId')::int
    AND n."userId" = i."inviteeId"
  WHERE n.type = 'AGENCY_INVITE'
    AND i.status = 'pending'
    AND (i."expiresAt" IS NULL OR i."expiresAt" > now())
  ORDER BY i.id, n."createdAt" DESC, n.id DESC
), repaired AS (
  UPDATE notifications n
  SET "isRead" = false, "readAt" = NULL
  FROM latest
  WHERE n.id = latest.id
    AND (n."isRead" = true OR n."readAt" IS NOT NULL)
  RETURNING n.id, n."userId", n.data, n."isRead", n."readAt"
)
SELECT * FROM repaired ORDER BY id;

COMMIT;
