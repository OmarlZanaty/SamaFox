#!/usr/bin/env bash
#
# One-off deploy of the 14/10 client notes (commits 87dc4a6, 7a363d5):
# 30% program / no win caps, Greedy Cat limit per item, Fruit Wheel v2.
#
#   ops/deploy-2026-10-14.sh          # 03:00–10:00 Cairo only
#   ops/deploy-2026-10-14.sh --now    # any time (drops every socket once)
#
# Order matters: the new engine needs its tables and the regenerated Prisma
# client BEFORE the reload that starts it.
#   1. database dump
#   2. migration 20261014000000_fruit_wheel_shared (by hand, skipped if applied)
#   3. prisma/schema.prisma + prisma generate
#   4. ops/deploy-backend.sh (backup, upload, node --check, reload, /health, rollback)
#   5. Greedy Cat: clear its stored max-win caps (client: «من غير أكبر مكسب»)
#   6. check the engine started
set -euo pipefail

HOST="${SAMAFOX_HOST:-root@46.224.129.250}"
KEY="${SAMAFOX_KEY:-$HOME/.ssh/hetzner-main}"
REMOTE=/srv/samafox/backend
NOW=()
[[ "${1:-}" == "--now" ]] && NOW=(--now)

hour=$(node -e "process.stdout.write(new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Cairo',hour:'2-digit',hourCycle:'h23'}).format(new Date()))")
if [[ ${#NOW[@]} -eq 0 ]] && (( 10#$hour >= 10 || 10#$hour < 3 )); then
  echo "It is ${hour}:00 in Cairo — deploy between 03:00 and 10:00, or pass --now." >&2
  exit 1
fi

cd "$(dirname "$0")/.."
ssh_() { ssh -i "$KEY" -o ConnectTimeout=15 "$HOST" "$@"; }
psql_() { ssh_ "cd /srv/samafox/stack && set -a && . ./.env && set +a && docker exec -i samafox-db psql -v ON_ERROR_STOP=1 -U \$SF_DB_USER -d \$SF_DB_NAME $*"; }
stamp=$(date +%Y%m%d-%H%M%S)

echo "▶ 1. database dump"
ssh_ "cd /srv/samafox/stack && set -a && . ./.env && set +a && docker exec samafox-db pg_dump -U \$SF_DB_USER -Fc \$SF_DB_NAME > /srv/backups/samafox-db-pre-fruitwheel2-$stamp.dump && ls -lh /srv/backups/samafox-db-pre-fruitwheel2-$stamp.dump"

echo "▶ 2. migration"
if [[ "$(psql_ -tAc "\"select to_regclass('public.fruit_wheel_stakes') is not null\"")" == "t" ]]; then
  echo "  already applied"
else
  tr -d '\r' < backend/prisma/migrations/20261014000000_fruit_wheel_shared/migration.sql | psql_ -1
fi

echo "▶ 3. schema + prisma generate"
ssh_ "cp -p $REMOTE/prisma/schema.prisma /srv/backups/schema.prisma.pre-fruitwheel2-$stamp"
tr -d '\r' < backend/prisma/schema.prisma | ssh_ "cat > $REMOTE/prisma/schema.prisma && chown samafox:samafox $REMOTE/prisma/schema.prisma"
ssh_ "cd $REMOTE && sudo -u samafox npx prisma generate >/dev/null && echo '  client generated'"

echo "▶ 4. files"
ops/deploy-backend.sh "${NOW[@]}" \
  dist/index.js \
  dist/routes/game.routes.js \
  dist/controllers/fruitWheelRound.controller.js \
  dist/services/fruitWheelRound.math.js \
  dist/services/fruitWheelRound.service.js \
  dist/services/economyAccounts.service.js \
  dist/services/gameConfig.service.js \
  dist/services/greedyCat.service.js \
  dist/services/halalGames.service.js \
  dist/services/roulette.math.js \
  public/admin-dashboard.html \
  public/economy-admin.js

echo "▶ 5. Greedy Cat caps → none (the pool is the limit)"
psql_ -tAc "\"update app_settings set value = jsonb_set(jsonb_set(value::jsonb, '{greedy-cat,maxWinPerRound}', 'null'), '{greedy-cat,dailyMaxWinPerUser}', 'null')::text where key = 'game_config' and value::jsonb ? 'greedy-cat' returning value::jsonb -> 'greedy-cat'\""

echo "▶ 6. engine"
sleep 5
ssh_ "sudo -u samafox pm2 logs samafox-api --lines 200 --nostream 2>&1 | grep -iE 'fruitwheel|error' | tail -5"
echo "✔ done — rollback files: /srv/backups/deploy-*, DB: /srv/backups/samafox-db-pre-fruitwheel2-$stamp.dump"
