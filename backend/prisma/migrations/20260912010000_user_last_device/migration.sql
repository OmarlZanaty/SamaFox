-- F4: record the handset and network an account was last seen on, so an admin
-- has something to type into the device-ban form. The ban itself already
-- worked; nothing ever surfaced a device id.
ALTER TABLE "User" ADD COLUMN "lastDeviceId" TEXT;
ALTER TABLE "User" ADD COLUMN "lastIp" TEXT;
ALTER TABLE "User" ADD COLUMN "lastSeenAt" TIMESTAMP(3);

CREATE INDEX "User_lastDeviceId_idx" ON "User"("lastDeviceId");
CREATE INDEX "User_lastIp_idx" ON "User"("lastIp");
