-- CreateTable
CREATE TABLE "UserIdSequence" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT DEFAULT 1,
    "nextId" INTEGER NOT NULL DEFAULT 10000
);

-- CreateTable
CREATE TABLE "Follow" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "followerId" INTEGER NOT NULL,
    "followingId" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Follow_followerId_fkey" FOREIGN KEY ("followerId") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Follow_followingId_fkey" FOREIGN KEY ("followingId") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Relation" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "user1Id" INTEGER NOT NULL,
    "user2Id" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "requestedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "acceptedAt" DATETIME,
    CONSTRAINT "Relation_user1Id_fkey" FOREIGN KEY ("user1Id") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Relation_user2Id_fkey" FOREIGN KEY ("user2Id") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "AgencyRequest" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "userId" INTEGER NOT NULL,
    "type" TEXT NOT NULL,
    "agencyName" TEXT NOT NULL,
    "imageUrl" TEXT,
    "contactInfo" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "reviewedBy" INTEGER,
    "reviewedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AgencyRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "AgencyMember" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "agencyId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'MEMBER',
    "joinedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AgencyMember_agencyId_fkey" FOREIGN KEY ("agencyId") REFERENCES "charging_agencies" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "AgencyMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "AgencyInvite" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "agencyId" INTEGER NOT NULL,
    "inviterId" INTEGER NOT NULL,
    "inviteeId" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AgencyInvite_agencyId_fkey" FOREIGN KEY ("agencyId") REFERENCES "charging_agencies" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_charging_agencies" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "userId" INTEGER NOT NULL,
    "agencyName" TEXT NOT NULL,
    "phoneNumber" TEXT NOT NULL,
    "agencyImageUrl" TEXT NOT NULL,
    "idFrontUrl" TEXT NOT NULL,
    "idBackUrl" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "type" TEXT NOT NULL DEFAULT 'CHARGING',
    "contactInfo" TEXT,
    "logoUrl" TEXT,
    "targetCoins" BIGINT NOT NULL DEFAULT 0,
    "earnedCoins" BIGINT NOT NULL DEFAULT 0,
    "balanceCoins" INTEGER NOT NULL DEFAULT 0,
    "totalSentCoins" INTEGER NOT NULL DEFAULT 0,
    "totalTopupCoins" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "charging_agencies_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
INSERT INTO "new_charging_agencies" ("agencyImageUrl", "agencyName", "balanceCoins", "createdAt", "id", "idBackUrl", "idFrontUrl", "phoneNumber", "status", "totalSentCoins", "totalTopupCoins", "updatedAt", "userId") SELECT "agencyImageUrl", "agencyName", "balanceCoins", "createdAt", "id", "idBackUrl", "idFrontUrl", "phoneNumber", "status", "totalSentCoins", "totalTopupCoins", "updatedAt", "userId" FROM "charging_agencies";
DROP TABLE "charging_agencies";
ALTER TABLE "new_charging_agencies" RENAME TO "charging_agencies";
CREATE INDEX "charging_agencies_userId_idx" ON "charging_agencies"("userId");
CREATE INDEX "charging_agencies_status_idx" ON "charging_agencies"("status");
CREATE TABLE "new_gifts" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "name" TEXT NOT NULL,
    "nameAr" TEXT NOT NULL DEFAULT '',
    "imageUrl" TEXT NOT NULL,
    "animationUrl" TEXT,
    "coinsValue" INTEGER NOT NULL DEFAULT 0,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "priceCoins" INTEGER NOT NULL,
    "category" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "xp" INTEGER NOT NULL DEFAULT 0,
    "level" INTEGER NOT NULL DEFAULT 1,
    "isComboFriendly" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "new_gifts" ("animationUrl", "category", "coinsValue", "id", "imageUrl", "isActive", "isComboFriendly", "level", "name", "nameAr", "priceCoins", "sortOrder", "xp") SELECT "animationUrl", "category", "coinsValue", "id", "imageUrl", "isActive", "isComboFriendly", "level", "name", "nameAr", "priceCoins", "sortOrder", "xp" FROM "gifts";
DROP TABLE "gifts";
ALTER TABLE "new_gifts" RENAME TO "gifts";
CREATE TABLE "new_items" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "itemType" TEXT NOT NULL DEFAULT 'AVATAR',
    "assetUrl" TEXT NOT NULL,
    "priceCoins" INTEGER NOT NULL DEFAULT 0,
    "isPurchasable" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "new_items" ("assetUrl", "createdAt", "description", "id", "isPurchasable", "name", "priceCoins", "type") SELECT "assetUrl", "createdAt", "description", "id", "isPurchasable", "name", "priceCoins", "type" FROM "items";
DROP TABLE "items";
ALTER TABLE "new_items" RENAME TO "items";
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
    "isBanned" BOOLEAN NOT NULL DEFAULT false,
    "bannedAt" DATETIME,
    "banReason" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "passwordHash" TEXT,
    "isVerified" BOOLEAN NOT NULL DEFAULT false,
    "lastLoginAt" DATETIME,
    "country" TEXT,
    "avatarFrameUrl" TEXT,
    "displayId" INTEGER,
    "activeFrameId" TEXT,
    "relationId" INTEGER,
    CONSTRAINT "users_activeFrameId_fkey" FOREIGN KEY ("activeFrameId") REFERENCES "items" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_users" ("activeFrameId", "avatarFrameUrl", "avatarUrl", "banReason", "bannedAt", "bio", "coinsBalance", "country", "countryCode", "createdAt", "email", "gender", "googleId", "id", "isAdmin", "isBanned", "isVerified", "lastLoginAt", "level", "name", "passwordHash", "phone", "updatedAt", "vipLevel", "xp") SELECT "activeFrameId", "avatarFrameUrl", "avatarUrl", "banReason", "bannedAt", "bio", "coinsBalance", "country", "countryCode", "createdAt", "email", "gender", "googleId", "id", "isAdmin", "isBanned", "isVerified", "lastLoginAt", "level", "name", "passwordHash", "phone", "updatedAt", "vipLevel", "xp" FROM "users";
DROP TABLE "users";
ALTER TABLE "new_users" RENAME TO "users";
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");
CREATE UNIQUE INDEX "users_googleId_key" ON "users"("googleId");
CREATE UNIQUE INDEX "users_displayId_key" ON "users"("displayId");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- CreateIndex
CREATE UNIQUE INDEX "Follow_followerId_followingId_key" ON "Follow"("followerId", "followingId");

-- CreateIndex
CREATE UNIQUE INDEX "Relation_user1Id_user2Id_key" ON "Relation"("user1Id", "user2Id");

-- CreateIndex
CREATE UNIQUE INDEX "AgencyMember_agencyId_userId_key" ON "AgencyMember"("agencyId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "AgencyInvite_agencyId_inviteeId_key" ON "AgencyInvite"("agencyId", "inviteeId");
