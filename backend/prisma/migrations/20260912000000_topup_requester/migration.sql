-- B5: a فرع may request a top-up for himself. The approval credits the
-- requester's own wallet, not the agency owner's, so the row has to remember
-- who asked. NULL on every existing row, which is an owner request by
-- construction (only owners could reach the endpoint before this).
ALTER TABLE "AgencyTopupRequest" ADD COLUMN "requesterId" INTEGER;

CREATE INDEX "AgencyTopupRequest_requesterId_idx" ON "AgencyTopupRequest"("requesterId");

ALTER TABLE "AgencyTopupRequest"
  ADD CONSTRAINT "AgencyTopupRequest_requesterId_fkey"
  FOREIGN KEY ("requesterId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
