#!/usr/bin/env bash
# Deploys the 6/11 client batch: 3 additive migrations, schema + prisma generate, changed dist + dashboard files.
set -euo pipefail
HOST="${SAMAFOX_HOST:-root@46.224.129.250}"
KEY="${SAMAFOX_KEY:-$HOME/.ssh/hetzner-main}"
REMOTE=/srv/samafox/backend
NOW=(); [[ "${1:-}" == "--now" ]] && NOW=(--now)
cd "$(dirname "$0")/.."
ssh_() { ssh -i "$KEY" -o ConnectTimeout=15 "$HOST" "$@"; }
psql_() { ssh_ "cd /srv/samafox/stack && set -a && . ./.env && set +a && docker exec -i samafox-db psql -v ON_ERROR_STOP=1 -U \$SF_DB_USER -d \$SF_DB_NAME $*"; }
stamp=$(date +%Y%m%d-%H%M%S)
echo "▶ 1. dump"
ssh_ "cd /srv/samafox/stack && set -a && . ./.env && set +a && docker exec samafox-db pg_dump -U \$SF_DB_USER -Fc \$SF_DB_NAME > /srv/backups/samafox-db-pre-nov06-$stamp.dump && ls -lh /srv/backups/samafox-db-pre-nov06-$stamp.dump"
echo "▶ 2. migrations"
chk() { [[ "$(psql_ -tAc "\"$1\"")" == "t" ]]; }
if chk "select to_regclass('public.pk_prize_boxes') is not null"; then echo " pk applied"; else tr -d '\r' < backend/prisma/migrations/20261106000101_pk_prize_boxes/migration.sql | psql_ -1; fi
if chk "select to_regclass('public.user_special_ids') is not null"; then echo " special ids applied"; else tr -d '\r' < backend/prisma/migrations/20261106000200_special_ids/migration.sql | psql_ -1; fi
if chk "select exists(select 1 from information_schema.columns where table_name='users' and column_name='receivedXp')"; then echo " economy applied"; else tr -d '\r' < backend/prisma/migrations/20261106000300_economy_supported_level/migration.sql | psql_ -1; fi
echo "▶ 3. schema + generate"
ssh_ "cp -p $REMOTE/prisma/schema.prisma /srv/backups/schema.prisma.pre-nov06-$stamp"
tr -d '\r' < backend/prisma/schema.prisma | ssh_ "cat > $REMOTE/prisma/schema.prisma && chown samafox:samafox $REMOTE/prisma/schema.prisma"
ssh_ "cd $REMOTE && sudo -u samafox npx prisma generate >/dev/null && echo ' client generated'"
echo "▶ 4. files"
ops/deploy-backend.sh "${NOW[@]}" \
  dist/index.js dist/agencies/agency.controller.js dist/controllers/adminDashboard.controller.js \
  dist/controllers/messages.controller.js dist/follow/follow.controller.js dist/gifts/giftService.js \
  dist/routes/adminDashboard.routes.js dist/routes/adminEconomy.routes.js dist/routes/messages.routes.js \
  dist/routes/roomEvents.routes.js dist/routes/store.routes.js dist/services/economyAdmin.service.js \
  dist/services/roomEvents.service.js dist/services/storeLists.service.js \
  public/admin-dashboard.html public/app.js public/economy-admin.js public/spec52-admin.js
