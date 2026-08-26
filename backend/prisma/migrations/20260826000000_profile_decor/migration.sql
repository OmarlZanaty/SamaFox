-- B3 / A9 — إطار تزيين الصفحة الشخصية.
--
-- The dashboard could already create a PROFILE_DECOR product, but the app had
-- nowhere to read an equipped one from, so the whole category was invisible.
-- These columns mirror the existing profileBg pair and are written by the store
-- when the item is equipped/unequipped.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "profileDecorUrl" TEXT;
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "profileDecorType" TEXT DEFAULT 'image';
