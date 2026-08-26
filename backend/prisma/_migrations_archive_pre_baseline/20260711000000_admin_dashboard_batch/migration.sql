-- Admin dashboard batch: timed bans, name lock, target->dollar tiers

ALTER TABLE "users" ADD COLUMN "banExpiresAt" TIMESTAMP(3);
ALTER TABLE "users" ADD COLUMN "banSource" TEXT;
ALTER TABLE "users" ADD COLUMN "nameLocked" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE "target_tiers" (
    "id" SERIAL NOT NULL,
    "coins" BIGINT NOT NULL,
    "dollars" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "target_tiers_pkey" PRIMARY KEY ("id")
);
