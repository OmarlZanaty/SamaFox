-- F4: record the handset and network an account was last seen on, so an admin
-- has something to type into the device-ban form. The ban itself already
-- worked; nothing ever surfaced a device id.
--
-- Table is `users` (the User model is @@map'd), and the index names follow it.
ALTER TABLE "users" ADD COLUMN "lastDeviceId" TEXT;
ALTER TABLE "users" ADD COLUMN "lastIp" TEXT;
ALTER TABLE "users" ADD COLUMN "lastSeenAt" TIMESTAMP(3);

CREATE INDEX "users_lastDeviceId_idx" ON "users"("lastDeviceId");
CREATE INDEX "users_lastIp_idx" ON "users"("lastIp");
