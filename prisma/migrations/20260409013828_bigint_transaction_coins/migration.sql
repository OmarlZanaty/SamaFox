/*
  Warnings:

  - You are about to alter the column `amountCoins` on the `transactions` table. The data in that column could be lost. The data in that column will be cast from `BigInt` to `Int`.
  - You are about to alter the column `coinsBalance` on the `users` table. The data in that column could be lost. The data in that column will be cast from `BigInt` to `Int`.

*/
-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_transactions" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "userId" INTEGER NOT NULL,
    "type" TEXT NOT NULL,
    "amountCoins" INTEGER NOT NULL,
    "externalId" TEXT,
    "paymentMethod" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "transactions_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
INSERT INTO "new_transactions" ("amountCoins", "createdAt", "externalId", "id", "paymentMethod", "status", "type", "userId") SELECT "amountCoins", "createdAt", "externalId", "id", "paymentMethod", "status", "type", "userId" FROM "transactions";
DROP TABLE "transactions";
ALTER TABLE "new_transactions" RENAME TO "transactions";
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
    "coinsBalance" INTEGER NOT NULL DEFAULT 0,
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
