-- Super-admin role (#23). Additive & safe: new boolean, default false.
ALTER TABLE "users" ADD COLUMN "isSuperAdmin" BOOLEAN NOT NULL DEFAULT false;
