-- Group 10: multiple store items (badge/frame/entrance) auto-granted per VIP level
ALTER TABLE "vip_level_configs" ADD COLUMN "rewardItemIds" TEXT[] NOT NULL DEFAULT '{}';
