ALTER TABLE "users"
  ADD COLUMN "receivedXp" BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN "supportedLevel" INTEGER NOT NULL DEFAULT 1;

-- Hide reset history without deleting financial or fairness evidence.
ALTER TABLE "lucky_rolls" ADD COLUMN "archived" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "lucky_rounds" ADD COLUMN "archived" BOOLEAN NOT NULL DEFAULT false;
