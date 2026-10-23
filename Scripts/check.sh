#!/usr/bin/env bash
#
# Local gate: build with zero warnings, run the unit tests, confirm the
# generated dataset matches its generator.
#
# Usage: Scripts/check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> swift build (warnings fail the gate)"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT
swift build 2>&1 | tee "$BUILD_LOG" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|warning:" || true
if grep -qE "error:|warning:" "$BUILD_LOG"; then
  echo "FAIL: build produced errors or warnings" >&2
  exit 1
fi

echo "==> swift test"
swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Executed [0-9]+ tests, with" | tail -1

echo "==> emoji dataset is reproducible"
BEFORE="$(shasum -a 256 Sources/Rayclone/Resources/emoji.json | cut -d' ' -f1)"
python3 Scripts/generate_emoji.py >/dev/null
AFTER="$(shasum -a 256 Sources/Rayclone/Resources/emoji.json | cut -d' ' -f1)"
if [[ "$BEFORE" != "$AFTER" ]]; then
  echo "FAIL: emoji.json is stale; run Scripts/generate_emoji.py" >&2
  exit 1
fi

echo "OK"
