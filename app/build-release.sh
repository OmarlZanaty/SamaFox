#!/usr/bin/env bash
#
# A2 / G1 / G6 — the release build.
#
# This script exists because the single most damaging bug in the app was not in
# any source file: `AppConfig.turnUrls` defaults to an empty string, and NOTHING
# in the repository ever passed --dart-define=TURN_URLS. Every release ever
# built therefore shipped STUN-only WebRTC. Two users on mobile data sit behind
# carrier-grade NAT with no direct path between them, so the voice link simply
# never comes up — which is the "الصوت راح خالص / بيقطع" the owner reported
# twelve times.
#
# A build command that has to be typed correctly from memory will eventually be
# typed wrong. So it lives here, in the repo, and refuses to produce a release
# that would repeat the bug.
#
# Usage:
#   cp turn.env.example turn.env      # fill in your coturn details
#   ./build-release.sh                # app bundle for Play (default)
#   ./build-release.sh apk            # a direct-download APK (G2)
#
set -euo pipefail

cd "$(dirname "$0")"

TARGET="${1:-appbundle}"
ENV_FILE="${TURN_ENV_FILE:-turn.env}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

: "${TURN_URLS:=}"
: "${TURN_USERNAME:=}"
: "${TURN_CREDENTIAL:=}"
: "${API_BASE_URL:=}"
: "${SOCKET_URL:=}"

if [[ -z "$TURN_URLS" ]]; then
  cat >&2 <<'WARN'
────────────────────────────────────────────────────────────────────────
  TURN_URLS is empty.

  Building now produces a STUN-only app: two users on mobile data will
  not hear each other at all. This is the exact defect this script was
  written to prevent, so it stops here.

  Fix: copy turn.env.example to turn.env and fill in your coturn server,
  or export TURN_URLS / TURN_USERNAME / TURN_CREDENTIAL yourself.

  To build anyway (local testing on one wifi network only):
      ALLOW_NO_TURN=1 ./build-release.sh
────────────────────────────────────────────────────────────────────────
WARN
  if [[ "${ALLOW_NO_TURN:-0}" != "1" ]]; then
    exit 1
  fi
  echo "ALLOW_NO_TURN=1 — continuing without TURN. Do not ship this build." >&2
fi

DEFINES=()
[[ -n "$TURN_URLS" ]]       && DEFINES+=("--dart-define=TURN_URLS=$TURN_URLS")
[[ -n "$TURN_USERNAME" ]]   && DEFINES+=("--dart-define=TURN_USERNAME=$TURN_USERNAME")
[[ -n "$TURN_CREDENTIAL" ]] && DEFINES+=("--dart-define=TURN_CREDENTIAL=$TURN_CREDENTIAL")
[[ -n "$API_BASE_URL" ]]    && DEFINES+=("--dart-define=API_BASE_URL=$API_BASE_URL")
[[ -n "$SOCKET_URL" ]]      && DEFINES+=("--dart-define=SOCKET_URL=$SOCKET_URL")

# G1 — the direct-download APK was ONE universal binary carrying arm64, armv7
# and x86 native code, so every user downloaded three architectures to run one.
# `--split-per-abi` emits one APK per architecture; arm64 is what to publish for
# any phone made in the last decade. Play is unaffected — the bundle handles
# this itself, and passing the flag to an appbundle build is an error.
SPLIT=()
if [[ "$TARGET" == "apk" && "${NO_ABI_SPLIT:-0}" != "1" ]]; then
  SPLIT+=(--split-per-abi)
fi

# A marker older than anything this run produces, so the check below never
# grades an artifact left over from an earlier build (a universal APK from a
# NO_ABI_SPLIT run sits beside the split ones and is not rebuilt with them).
BUILD_MARK="$(mktemp)"

echo "▶ flutter build $TARGET  (${#DEFINES[@]} dart-defines)"
flutter build "$TARGET" --release "${DEFINES[@]}" "${SPLIT[@]}"

# ── Verify the OUTPUT, not just the input ────────────────────────────────────
#
# The guard above only checks that TURN_URLS was set when this script ran. It
# cannot help when the script is not run at all: version 1.0.20 (build 2027)
# went to Play from a plain `flutter build appbundle --release`, and its Dart
# snapshot contained the five Google STUN servers and not one TURN entry. Two
# users on mobile data could not hear each other, and nothing said why.
#
# So the binary itself is inspected. The dart-define values are embedded as
# plain strings in libapp.so; if `turn:` is not in there, this build must not
# leave this machine.
verify_turn_in() {
  local artifact="$1"
  local so
  so="$(unzip -Z1 "$artifact" 2>/dev/null | grep -m1 'lib/arm64-v8a/libapp.so')" || true
  if [[ -z "$so" ]]; then
    echo "   (no arm64 libapp.so in $artifact — skipping TURN check)" >&2
    return 0
  fi
  local hits
  hits="$(unzip -p "$artifact" "$so" | grep -ac 'turn:' || true)"
  if [[ "${hits:-0}" -gt 0 ]]; then
    echo "✅ TURN present in $(basename "$artifact") ($hits match)"
    return 0
  fi
  echo "❌ $(basename "$artifact") contains NO TURN configuration." >&2
  echo "   This is the STUN-only build that ships silent voice. Refusing." >&2
  return 1
}

if [[ -n "$TURN_URLS" ]]; then
  case "$TARGET" in
    appbundle) verify_turn_in build/app/outputs/bundle/release/app-release.aab ;;
    apk)
      for f in build/app/outputs/flutter-apk/app-*release.apk; do
        [[ -f "$f" ]] || continue
        if [[ "$f" -ot "$BUILD_MARK" ]]; then
          echo "   (skipping $(basename "$f") — left over from an earlier build, not produced now)"
          continue
        fi
        verify_turn_in "$f"
      done
      ;;
  esac
fi
rm -f "$BUILD_MARK"

case "$TARGET" in
  appbundle)
    echo "✅ build/app/outputs/bundle/release/app-release.aab"
    echo "   Upload this to Play — it serves each device only its own ABI."
    ;;
  apk)
    echo "✅ build/app/outputs/flutter-apk/"
    if [[ "${NO_ABI_SPLIT:-0}" == "1" ]]; then
      echo "   app-release.apk — universal (NO_ABI_SPLIT=1). Every user"
      echo "   downloads three architectures to run one; only do this when you"
      echo "   genuinely cannot tell devices apart."
    else
      echo "   app-arm64-v8a-release.apk   ← publish this one (G2)"
      echo "   app-armeabi-v7a-release.apk ← only for phones older than ~2015"
      echo "   app-x86_64-release.apk      ← emulators"
      echo "   Each carries one architecture instead of all three."
    fi
    echo
    echo "   Note: the remaining size is ASSETS (~61 MB of game artwork), which"
    echo "   no build flag can shrink. Cutting it means re-encoding the art —"
    echo "   the client's call, not a build setting."
    ;;
esac
