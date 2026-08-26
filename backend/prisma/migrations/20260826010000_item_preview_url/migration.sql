-- A25/B5 — still poster for a video product.
--
-- The store grid no longer builds a VideoPlayerController per tile (that is what
-- made opening المتجر crawl), and falls back to `preview_url`, which the API had
-- always filled with the clip itself — so every مركبة showed a blank grey
-- placeholder. Posters are extracted with ffmpeg at upload time and stored here.
-- Existing clips stay null until `npm run backfill:posters` is run.
ALTER TABLE "items" ADD COLUMN IF NOT EXISTS "previewUrl" TEXT;
