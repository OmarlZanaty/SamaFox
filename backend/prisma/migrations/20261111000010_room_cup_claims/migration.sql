-- Client 10/11 19:02: the room-cup reward must appear under the owner's name in
-- the cup and be collected by him, and the panel must show whether it was paid
-- out and whether he took it. Rewards stop going straight into the wallet.
CREATE TABLE IF NOT EXISTS room_cup_claims (
  id          SERIAL PRIMARY KEY,
  "roomId"    INTEGER      NOT NULL,
  "userId"    INTEGER      NOT NULL,
  coins       BIGINT       NOT NULL,
  -- 'rung' = كأس الروم levels for every room (refId = room_cup_reward_payouts.id)
  -- 'cup'  = كأس الغرفة بالـ ID (refId = "RoomCup".id, level = its level index)
  source      TEXT         NOT NULL,
  "refId"     INTEGER      NOT NULL,
  level       INTEGER      NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "claimedAt" TIMESTAMP(3)
);
CREATE UNIQUE INDEX IF NOT EXISTS room_cup_claims_source_ref_level_key ON room_cup_claims (source, "refId", level);
CREATE INDEX IF NOT EXISTS room_cup_claims_user_room_idx ON room_cup_claims ("userId", "roomId", "claimedAt");
CREATE INDEX IF NOT EXISTS room_cup_claims_created_idx ON room_cup_claims ("createdAt");

-- كأس الغرفة بالـ ID with several levels: [{ "targetCoins": "1000000", "rewardCoins": "30000" }, …].
-- Empty = the single targetCoins/ownerRewardCoins level, as before.
ALTER TABLE "RoomCup" ADD COLUMN IF NOT EXISTS levels JSONB NOT NULL DEFAULT '[]';
