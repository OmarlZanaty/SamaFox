-- PK levels, each opened by the battle total with its own prizes (client 10/11 19:48).
ALTER TABLE "pk_configs" ADD COLUMN IF NOT EXISTS "levels" JSONB NOT NULL DEFAULT '[]';
