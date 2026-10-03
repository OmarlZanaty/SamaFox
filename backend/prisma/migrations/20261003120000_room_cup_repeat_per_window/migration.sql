-- A room cup rung now pays once per support window, not once per room forever.
DROP INDEX IF EXISTS "room_cup_reward_payouts_rewardId_roomId_key";
CREATE INDEX IF NOT EXISTS "room_cup_reward_payouts_rewardId_roomId_paidAt_idx"
  ON "room_cup_reward_payouts" ("rewardId", "roomId", "paidAt");
