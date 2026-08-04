-- Personal music library: songs a user uploaded from their phone to play in
-- rooms. Rows are never auto-pruned — only the owner deletes them.
CREATE TABLE IF NOT EXISTS "music_tracks" (
    "id" SERIAL NOT NULL,
    "userId" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "filename" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "music_tracks_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "music_tracks_userId_idx" ON "music_tracks"("userId");

DO $$
BEGIN
    ALTER TABLE "music_tracks"
        ADD CONSTRAINT "music_tracks_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "users"("id")
        ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
