-- SPEC52 #41 (2026-10-20): store lists, products, orders, display-id history. New tables only.
-- CreateTable
CREATE TABLE IF NOT EXISTS "store_categories" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "imageUrl" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "store_categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "store_products" (
    "id" SERIAL NOT NULL,
    "categoryId" INTEGER NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'special_id',
    "name" TEXT NOT NULL,
    "imageUrl" TEXT,
    "priceCoins" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'coins',
    "durationDays" INTEGER,
    "stock" INTEGER,
    "isAvailable" BOOLEAN NOT NULL DEFAULT true,
    "specialDisplayId" INTEGER,
    "itemId" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "store_products_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "store_orders" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "productId" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "priceCoins" INTEGER NOT NULL,
    "oldDisplayId" INTEGER,
    "newDisplayId" INTEGER,
    "idempotencyKey" TEXT NOT NULL,
    "failureReason" TEXT,
    "transactionId" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "store_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "display_id_history" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "oldId" INTEGER,
    "newId" INTEGER NOT NULL,
    "orderId" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "display_id_history_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "store_products_specialDisplayId_key" ON "store_products"("specialDisplayId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "store_products_categoryId_isAvailable_idx" ON "store_products"("categoryId", "isAvailable");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "store_orders_idempotencyKey_key" ON "store_orders"("idempotencyKey");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "store_orders_userId_createdAt_idx" ON "store_orders"("userId", "createdAt");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "display_id_history_userId_createdAt_idx" ON "display_id_history"("userId", "createdAt");

-- AddForeignKey
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'store_products_categoryId_fkey') THEN ALTER TABLE "store_products" ADD CONSTRAINT "store_products_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "store_categories"("id") ON DELETE RESTRICT ON UPDATE CASCADE; END IF; END $$;
