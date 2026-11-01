#!/usr/bin/env bash
# Release AAB via build-release.sh, logged to build-<version>.log.
cd "$(dirname "$0")"
v="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
bash build-release.sh appbundle 2>&1 | tee "build-$v.log"
echo "BUILD EXIT=${PIPESTATUS[0]}" | tee -a "build-$v.log"
