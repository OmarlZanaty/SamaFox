/*
  Warnings:

  - You are about to alter the column `coinsBalance` on the `users` table. The data in that column could be lost. The data in that column will be cast from `Int` to `BigInt`.

*/
-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_users" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "email" TEXT,
    "phone" TEXT,
    "googleId" TEXT,
    "name" TEXT NOT NULL,
    "avatarUrl" TEXT,
    "countryCode" TEXT,
    "gender" TEXT,
    "bio" TEXT,
    "coinsBalance" BIGINT NOT NULL DEFAULT 0,
    "level" INTEGER NOT NULL DEFAULT 1,
    "xp" INTEGER NOT NULL DEFAULT 0,
    "vipLevel" INTEGER NOT NULL DEFAULT 0,
    "isAdmin" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "passwordHash" TEXT,
    "isVerified" BOOLEAN NOT NULL DEFAULT false,
    "lastLoginAt" DATETIME,
    "country" TEXT,
    "avatarFrameUrl" TEXT
);
INSERT INTO "new_users" ("avatarFrameUrl", "avatarUrl", "bio", "coinsBalance", "country", "countryCode", "createdAt", "email", "gender", "googleId", "id", "isAdmin", "isVerified", "lastLoginAt", "level", "name", "passwordHash", "phone", "updatedAt", "vipLevel", "xp") SELECT "avatarFrameUrl", "avatarUrl", "bio", "coinsBalance", "country", "countryCode", "createdAt", "email", "gender", "googleId", "id", "isAdmin", "isVerified", "lastLoginAt", "level", "name", "passwordHash", "phone", "updatedAt", "vipLevel", "xp" FROM "users";
DROP TABLE "users";
ALTER TABLE "new_users" RENAME TO "users";
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");
CREATE UNIQUE INDEX "users_googleId_key" ON "users"("googleId");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
