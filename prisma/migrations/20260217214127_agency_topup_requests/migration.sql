-- CreateTable
CREATE TABLE "agency_topup_requests" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "agencyId" INTEGER NOT NULL,
    "amount" INTEGER NOT NULL,
    "receiptUrl" TEXT NOT NULL,
    "note" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "reviewedBy" INTEGER,
    "reviewedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "agency_topup_requests_agencyId_fkey" FOREIGN KEY ("agencyId") REFERENCES "charging_agencies" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "agency_topup_requests_reviewedBy_fkey" FOREIGN KEY ("reviewedBy") REFERENCES "users" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateIndex
CREATE INDEX "agency_topup_requests_agencyId_idx" ON "agency_topup_requests"("agencyId");

-- CreateIndex
CREATE INDEX "agency_topup_requests_status_idx" ON "agency_topup_requests"("status");
