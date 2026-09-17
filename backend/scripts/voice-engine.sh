#!/usr/bin/env bash
#
# Switch every room's voice engine, live, without an app update.
#
#   ./scripts/voice-engine.sh            # show the current setting
#   ./scripts/voice-engine.sh livekit    # SFU: one connection per phone
#   ./scripts/voice-engine.sh mesh       # the original peer-to-peer mesh
#
# Read this before flipping: the two engines cannot hear EACH OTHER. A phone on
# `mesh` sends audio to other phones; a phone on `livekit` sends it to the SFU.
# Users in the same room on different engines hear only their own kind. So the
# switch is a room-wide moment, not a preference:
#
#   1. the build that contains the LiveKit client must be on (nearly) every
#      phone — set min_supported_build so the old ones are forced to update;
#   2. then flip to livekit;
#   3. if anything is wrong, flip back to mesh — same command, same instant.
#
# Clients read the setting at launch and keep the engine for the life of the
# process, so a running app moves on its next start, not mid-room.
set -euo pipefail
cd "$(dirname "$0")/.."

ENGINE="${1:-}"
if [[ -n "$ENGINE" && "$ENGINE" != "livekit" && "$ENGINE" != "mesh" ]]; then
  echo "usage: $0 [livekit|mesh]" >&2
  exit 1
fi

set -a; . ./.env; set +a
ENGINE="$ENGINE" node -e '
const { PrismaClient } = require("@prisma/client");
(async () => {
  const p = new PrismaClient();
  const want = process.env.ENGINE;
  if (want) {
    await p.appSetting.upsert({
      where: { key: "voice_engine" },
      update: { value: want },
      create: { key: "voice_engine", value: want },
    });
  }
  const rows = await p.appSetting.findMany({
    where: { key: { in: ["voice_engine", "livekit_url", "min_supported_build"] } },
  });
  const m = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  console.log(`voice_engine        = ${m.voice_engine ?? "mesh (default)"}`);
  console.log(`livekit_url         = ${m.livekit_url ?? "(unset — engine stays mesh)"}`);
  console.log(`min_supported_build = ${m.min_supported_build ?? "0 (gate off)"}`);
  if (want) console.log(`\n✔ set voice_engine=${want}. Apps pick it up on their next launch.`);
  await p.$disconnect();
})().catch((e) => { console.error(e.message); process.exit(1); });
'
