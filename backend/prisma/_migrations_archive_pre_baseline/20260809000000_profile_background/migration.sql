-- Profile-page background: a still image, an animated GIF or a video clip that
-- the user picks for his own page. `profile_bg_type` tells the client whether to
-- mount an Image or a video player; existing rows keep NULL and fall back to the
-- built-in gradient.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "profileBgUrl" TEXT;
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "profileBgType" TEXT DEFAULT 'image';
