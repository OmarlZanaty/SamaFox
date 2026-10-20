-- SPEC52 #12 (2026-10-20): friendships + visit de-duplication. Additive; safe to re-run.
CREATE TABLE IF NOT EXISTS "friendships" (
  "id" SERIAL PRIMARY KEY,
  "requesterId" INTEGER NOT NULL,
  "receiverId" INTEGER NOT NULL,
  "userLowId" INTEGER NOT NULL,
  "userHighId" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "acceptedAt" TIMESTAMP(3),
  "blockedAt" TIMESTAMP(3),
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS "friendships_userLowId_userHighId_key" ON "friendships" ("userLowId", "userHighId");
CREATE INDEX IF NOT EXISTS "friendships_receiverId_status_idx" ON "friendships" ("receiverId", "status");
CREATE INDEX IF NOT EXISTS "friendships_requesterId_status_idx" ON "friendships" ("requesterId", "status");
-- People who already follow each other were shown as «أصدقاء»; keep them friends.
INSERT INTO "friendships" ("requesterId", "receiverId", "userLowId", "userHighId", "status", "createdAt", "acceptedAt", "updatedAt")
SELECT a."followerId", a."followingId", LEAST(a."followerId", a."followingId"), GREATEST(a."followerId", a."followingId"),
       'accepted', GREATEST(a."createdAt", b."createdAt"), GREATEST(a."createdAt", b."createdAt"), CURRENT_TIMESTAMP
FROM "Follow" a JOIN "Follow" b ON b."followerId" = a."followingId" AND b."followingId" = a."followerId"
WHERE a."followerId" < a."followingId" AND upper(a."status") = 'ACCEPTED' AND upper(b."status") = 'ACCEPTED'
ON CONFLICT ("userLowId", "userHighId") DO NOTHING;

ALTER TABLE "profile_visits" ADD COLUMN IF NOT EXISTS "lastVisitAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "profile_visits" ADD COLUMN IF NOT EXISTS "visitCount" INTEGER NOT NULL DEFAULT 1;
UPDATE "profile_visits" SET "lastVisitAt" = "createdAt" WHERE "lastVisitAt" > "createdAt" + interval '1 second' AND "visitCount" = 1;
CREATE INDEX IF NOT EXISTS "profile_visits_viewerId_profileId_idx" ON "profile_visits" ("viewerId", "profileId");
