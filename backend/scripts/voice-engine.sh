#!/usr/bin/env bash
#
# Which voice engine rooms use, live, without an app update.
#
#   ./scripts/voice-engine.sh                      # show the current setting
#   ./scripts/voice-engine.sh rooms 12,33          # THESE rooms on LiveKit, the rest on the mesh
#   ./scripts/voice-engine.sh rooms ""             # no room on LiveKit
#   ./scripts/voice-engine.sh livekit              # default for every room: SFU
#   ./scripts/voice-engine.sh mesh-rooms 5         # …except these, back on the mesh
#   ./scripts/voice-engine.sh mesh                 # default for every room: the mesh
#
# Read this before flipping: the two engines cannot hear EACH OTHER. A phone on
# `mesh` sends audio to other phones; a phone on `livekit` sends it to the SFU.
# So a room moves as a WHOLE. The rollout that works:
#
#   1. the build that reads these per-room lists (2034+) is on (nearly) every
#      phone — set min_supported_build so the old ones are forced to update;
#   2. `rooms <id>` one room at a time, with the people in it warned that the
#      room is restarting its audio (everyone re-enters);
#   3. once every busy room has moved, `livekit` flips the default, and
#      `mesh-rooms` holds any exception;
#   4. anything wrong — the same command the other way, same instant.
#
# Clients read the lists at launch, on resume and right before entering a room,
# so a change reaches the next person to enter; people already inside keep the
# engine they entered with until they leave.
set -euo pipefail
cd "$(dirname "$0")/.."

CMD="${1:-}"
ARG="${2-}"
case "$CMD" in
  ""|livekit|mesh) ;;
  rooms|mesh-rooms)
    if [[ $# -lt 2 ]]; then echo "usage: $0 $CMD <id,id,...|\"\">" >&2; exit 1; fi ;;
  *) echo "usage: $0 [livekit|mesh|rooms <ids>|mesh-rooms <ids>]" >&2; exit 1 ;;
esac

set -a; . ./.env; set +a
CMD="$CMD" ARG="$ARG" node -e '
const { PrismaClient } = require("@prisma/client");
(async () => {
  const p = new PrismaClient();
  const cmd = process.env.CMD;
  const arg = process.env.ARG ?? "";
  const set = async (key, value) => p.appSetting.upsert({
    where: { key }, update: { value }, create: { key, value },
  });
  const ids = (s) => s.split(/[,\s]+/).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (cmd === "livekit" || cmd === "mesh") await set("voice_engine", cmd);
  if (cmd === "rooms") await set("livekit_rooms", ids(arg).join(","));
  if (cmd === "mesh-rooms") await set("mesh_rooms", ids(arg).join(","));

  const rows = await p.appSetting.findMany({
    where: { key: { in: ["voice_engine", "livekit_url", "livekit_rooms", "mesh_rooms", "min_supported_build"] } },
  });
  const m = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  console.log(`voice_engine        = ${m.voice_engine ?? "mesh (default)"}`);
  console.log(`livekit_url         = ${m.livekit_url ?? "(unset — engine stays mesh)"}`);
  console.log(`livekit_rooms       = ${m.livekit_rooms || "(none)"}`);
  console.log(`mesh_rooms          = ${m.mesh_rooms || "(none)"}`);
  console.log(`min_supported_build = ${m.min_supported_build ?? "0 (gate off)"}`);
  if (cmd) console.log(`\n✔ updated. Apps pick it up on their next launch / room entry.`);
  await p.$disconnect();
})().catch((e) => { console.error(e.message); process.exit(1); });
'
