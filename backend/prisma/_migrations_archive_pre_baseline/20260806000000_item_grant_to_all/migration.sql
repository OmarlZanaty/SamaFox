-- منح المنتج لجميع المستخدمين: الراية تبقى على المنتج حتى يستلمه كل من يسجّل
-- لاحقاً تلقائياً. durationDays مضاف هنا أيضاً بأمان لأن قواعد قديمة قد لا تحتويه.
ALTER TABLE "items" ADD COLUMN IF NOT EXISTS "durationDays" INTEGER;
ALTER TABLE "items" ADD COLUMN IF NOT EXISTS "grantToAll" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "user_items" ADD COLUMN IF NOT EXISTS "expiresAt" TIMESTAMP(3);
