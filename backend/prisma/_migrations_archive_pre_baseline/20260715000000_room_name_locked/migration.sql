-- Dashboard can lock a room's name so the owner cannot rename it (group 6)
ALTER TABLE "rooms" ADD COLUMN "nameLocked" BOOLEAN NOT NULL DEFAULT false;
