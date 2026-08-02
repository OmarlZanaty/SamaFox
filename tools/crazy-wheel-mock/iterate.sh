#!/usr/bin/env bash
# Rebuild the preview bundle and re-shoot every scene.
#   bash tools/crazy-wheel-mock/iterate.sh <round-label> [scene ...]
set -e
cd "$(dirname "$0")/../.."
LABEL="${1:-r0}"; shift || true
SCENES=("$@")
[ ${#SCENES[@]} -eq 0 ] && SCENES=(betting spinning result coinflip cashhunt pachinko crazytime)

( cd app && flutter build web --release -t lib/dev/crazy_wheel_preview.dart \
    --dart-define=API_BASE_URL=http://localhost:3100/api/v1/ \
    --dart-define=SOCKET_URL=http://localhost:3100 >/dev/null 2>&1 )

mkdir -p tools/crazy-wheel-mock/shots
for scene in "${SCENES[@]}"; do
  node tools/crazy-wheel-mock/shoot.js "$scene" "tools/crazy-wheel-mock/shots/${LABEL}-${scene}.png"
done
