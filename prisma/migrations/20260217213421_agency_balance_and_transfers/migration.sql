-- CreateTable
CREATE TABLE "charging_agencies" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "userId" INTEGER NOT NULL,
    "agencyName" TEXT NOT NULL,
    "phoneNumber" TEXT NOT NULL,
    "agencyImageUrl" TEXT NOT NULL,
    "idFrontUrl" TEXT NOT NULL,
    "idBackUrl" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "balanceCoins" INTEGER NOT NULL DEFAULT 0,
    "totalSentCoins" INTEGER NOT NULL DEFAULT 0,
    "totalTopupCoins" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "charging_agencies_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "agency_transfers" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "agencyId" INTEGER NOT NULL,
    "toUserId" INTEGER NOT NULL,
    "amount" INTEGER NOT NULL,
    "note" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "agency_transfers_agencyId_fkey" FOREIGN KEY ("agencyId") REFERENCES "charging_agencies" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "agency_transfers_toUserId_fkey" FOREIGN KEY ("toUserId") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateIndex
CREATE INDEX "charging_agencies_userId_idx" ON "charging_agencies"("userId");

-- CreateIndex
CREATE INDEX "charging_agencies_status_idx" ON "charging_agencies"("status");

-- CreateIndex
CREATE INDEX "agency_transfers_agencyId_idx" ON "agency_transfers"("agencyId");

-- CreateIndex
CREATE INDEX "agency_transfers_toUserId_idx" ON "agency_transfers"("toUserId");
