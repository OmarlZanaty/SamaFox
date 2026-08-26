-- Per-product layout guides (content insets + 9-slice centre) so the dashboard
-- can tell the app where a decorated product's EMPTY inner box is.
-- Drives chat bubbles (A3), the entry banner (A5) and mic frames (A19).
ALTER TABLE "items" ADD COLUMN "meta" JSONB;
