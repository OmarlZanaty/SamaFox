-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_gifts" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "name" TEXT NOT NULL DEFAULT '',
    "nameAr" TEXT NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "animationUrl" TEXT,
    "coinsValue" INTEGER NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "priceCoins" INTEGER NOT NULL DEFAULT 0,
    "category" TEXT NOT NULL DEFAULT 'GENERAL',
    "xp" INTEGER NOT NULL DEFAULT 0,
    "level" INTEGER NOT NULL DEFAULT 1,
    "isComboFriendly" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "new_gifts" ("animationUrl", "category", "coinsValue", "createdAt", "id", "imageUrl", "isActive", "isComboFriendly", "level", "name", "nameAr", "priceCoins", "sortOrder", "xp") SELECT "animationUrl", "category", "coinsValue", "createdAt", "id", "imageUrl", "isActive", "isComboFriendly", "level", "name", "nameAr", "priceCoins", "sortOrder", "xp" FROM "gifts";
DROP TABLE "gifts";
ALTER TABLE "new_gifts" RENAME TO "gifts";
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
