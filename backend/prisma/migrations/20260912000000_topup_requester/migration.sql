-- B5: a فرع may request a top-up for himself. The approval credits the
-- requester's own wallet, not the agency owner's, so the row has to remember
-- who asked. NULL on every existing row, which is an owner request by
-- construction (only owners could reach the endpoint before this).
--
-- Table is `agency_topup_requests`, not the Prisma model name: the model
-- carries an @@map, and so do the index/constraint names Prisma generates.
ALTER TABLE "agency_topup_requests" ADD COLUMN "requesterId" INTEGER;

CREATE INDEX "agency_topup_requests_requesterId_idx"
  ON "agency_topup_requests"("requesterId");

ALTER TABLE "agency_topup_requests"
  ADD CONSTRAINT "agency_topup_requests_requesterId_fkey"
  FOREIGN KEY ("requesterId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
