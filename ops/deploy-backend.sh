#!/usr/bin/env bash
#
# Deploys built backend files to production (Hetzner, dist only).
#
#   ops/deploy-backend.sh dist/index.js dist/routes/auth.routes.js public/client-health.html
#   ops/deploy-backend.sh --now dist/index.js      # outside the night window
#   ops/deploy-backend.sh --no-reload dist/tools/x.js   # files the server does not load
#
# Paths are relative to backend/. The script:
#   1. refuses to run between 10:00 and 03:00 Cairo time without --now: a
#      restart drops every socket, and on 8 Oct four daytime restarts threw
#      everyone off the mic and out of the app;
#   2. builds (npx tsc) unless --no-build;
#   3. backs up the files it replaces to /srv/backups/deploy-<stamp>/;
#   4. uploads with CRLF stripped, syntax-checks every .js on the server;
#   5. reloads pm2 when anything under dist/ changed, then polls /health;
#   6. on a failed check or health, puts the old files back and reloads.
#
set -euo pipefail

HOST="${SAMAFOX_HOST:-root@46.224.129.250}"
KEY="${SAMAFOX_KEY:-$HOME/.ssh/hetzner-main}"
REMOTE=/srv/samafox/backend
NOW=0
BUILD=1
NO_RELOAD=0
FILES=()
for arg in "$@"; do
  case "$arg" in
    --now) NOW=1 ;;
    --no-build) BUILD=0 ;;
    --no-reload) NO_RELOAD=1 ;;
    -*) echo "unknown option $arg" >&2; exit 2 ;;
    *) FILES+=("$arg") ;;
  esac
done
[[ ${#FILES[@]} -gt 0 ]] || { echo "usage: $0 [--now] [--no-build] <path under backend/>..." >&2; exit 2; }

# Git Bash on Windows has no zoneinfo (TZ=Africa/Cairo silently gives UTC);
# Node's Intl does, DST included.
if [[ $NO_RELOAD -eq 1 ]]; then NOW=1; fi  # nothing restarts, nobody is dropped
hour=$(node -e "process.stdout.write(new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Cairo',hour:'2-digit',hourCycle:'h23'}).format(new Date()))")
if [[ $NOW -eq 0 ]] && (( 10#$hour >= 10 || 10#$hour < 3 )); then
  echo "It is ${hour}:00 in Cairo. A restart drops every user's connection;" >&2
  echo "deploy between 03:00 and 10:00, or pass --now if it cannot wait." >&2
  exit 1
fi

cd "$(dirname "$0")/../backend"
if [[ $BUILD -eq 1 ]]; then
  echo "▶ npx tsc"
  npx tsc
fi
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done

ssh_() { ssh -i "$KEY" -o ConnectTimeout=15 "$HOST" "$@"; }
stamp=$(date +%Y%m%d-%H%M%S)
backup="/srv/backups/deploy-$stamp"
echo "▶ backup → $backup"
ssh_ "mkdir -p '$backup' && cd '$REMOTE' && : > '$backup/.new-files' && for f in ${FILES[*]}; do
  if [ -f \"\$f\" ]; then cp --parents -p \"\$f\" '$backup/'; else echo \"\$f\" >> '$backup/.new-files'; fi
done"

reload=0
for f in "${FILES[@]}"; do
  [[ "$f" == dist/* && $NO_RELOAD -eq 0 ]] && reload=1
  echo "▶ upload $f"
  tr -d '\r' < "$f" | ssh_ "mkdir -p '$REMOTE/$(dirname "$f")' && cat > '$REMOTE/$f.deploying' && chown samafox:samafox '$REMOTE/$f.deploying' && mv '$REMOTE/$f.deploying' '$REMOTE/$f'"
done

rollback() {
  echo "✖ $1 — restoring the previous files" >&2
  ssh_ "cd '$backup' && find . -type f ! -name .new-files -exec cp -p --parents {} '$REMOTE/' \; ;
        while read -r f; do [ -n \"\$f\" ] && rm -f '$REMOTE/'\"\$f\"; done < .new-files;
        sudo -u samafox pm2 reload samafox-api --update-env >/dev/null" || true
  exit 1
}

js=()
for f in "${FILES[@]}"; do [[ "$f" == *.js ]] && js+=("$f"); done
if [[ ${#js[@]} -gt 0 ]]; then
  echo "▶ node --check"
  ssh_ "cd '$REMOTE' && for f in ${js[*]}; do node --check \"\$f\" || exit 1; done" || rollback "syntax check failed"
fi

if [[ $reload -eq 1 ]]; then
  echo "▶ pm2 reload"
  ssh_ "sudo -u samafox pm2 reload samafox-api --update-env >/dev/null"
  echo "▶ health"
  ok=0
  for _ in $(seq 1 30); do
    if ssh_ "curl -fsS -m 3 http://127.0.0.1:3000/health >/dev/null 2>&1"; then ok=1; break; fi
    sleep 1
  done
  [[ $ok -eq 1 ]] || rollback "/health did not answer within 30 s"
fi
echo "✔ deployed ${#FILES[@]} file(s); backup in $backup"
