-- الألعاب الحلال: stake/prize ledger. Additive only.
CREATE TABLE "game_ledger" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "game" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "amount" INTEGER NOT NULL,
    "xp" INTEGER NOT NULL DEFAULT 0,
    "ref" TEXT,
    "day" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "game_ledger_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "game_ledger_day_kind_idx" ON "game_ledger"("day", "kind");
CREATE INDEX "game_ledger_userId_day_idx" ON "game_ledger"("userId", "day");
