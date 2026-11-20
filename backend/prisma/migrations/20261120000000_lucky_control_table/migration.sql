BEGIN;
CREATE TABLE IF NOT EXISTS "lucky_control_rows" (
  "giftValue" INTEGER PRIMARY KEY CHECK ("giftValue" > 0),
  "thresholds" INTEGER[] NOT NULL CHECK (array_length("thresholds", 1) = 14 AND 0 < ALL("thresholds")),
  "tier" INTEGER NOT NULL DEFAULT 0 CHECK ("tier" BETWEEN 0 AND 13),
  "counter" INTEGER NOT NULL DEFAULT 0 CHECK ("counter" >= 0),
  "testTier" INTEGER NOT NULL DEFAULT 0 CHECK ("testTier" BETWEEN 0 AND 13),
  "testCounter" INTEGER NOT NULL DEFAULT 0 CHECK ("testCounter" >= 0)
);
-- Table ships empty: the old probability draw stays active until the admin saves rows.
COMMIT;
