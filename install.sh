#!/usr/bin/env bash
#
# Builds Rayclone from source and installs it to ~/Applications.
#
# Usage:
#   ./install.sh            build, install, launch
#   ./install.sh --no-open  build and install only
#
# This script touches exactly two things: the checkout's dist/ folder (build
# output) and ~/Applications/Rayclone.app (the installed app). It never uses
# sudo and never changes Gatekeeper policy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="Rayclone"
EXECUTABLE="Rayclone"
BUILT_APP="$ROOT/dist/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
OPEN_AFTER=1

for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN_AFTER=0 ;;
    --help|-h)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument '$arg'" >&2
      exit 2
      ;;
  esac
done

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rayclone-install.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# --- 1. Requirements -------------------------------------------------------
if ! xcrun --find swift >/dev/null 2>&1 && ! command -v swift >/dev/null 2>&1; then
  echo "error: Swift is not installed." >&2
  echo "       Install the free Xcode Command Line Tools:" >&2
  echo "         xcode-select --install" >&2
  exit 1
fi

# --- 2. Build the app bundle ----------------------------------------------
"$ROOT/Scripts/build-app.sh"

if [[ ! -x "$BUILT_APP/Contents/MacOS/$EXECUTABLE" ]]; then
  echo "error: build did not produce $BUILT_APP/Contents/MacOS/$EXECUTABLE" >&2
  exit 1
fi

# --- 3. Replace any running copy ------------------------------------------
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
  echo "==> stopping the running copy"
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  for _ in {1..20}; do
    pgrep -x "$EXECUTABLE" >/dev/null 2>&1 || break
    sleep 0.1
  done
fi

# --- 4. Install ------------------------------------------------------------
echo "==> installing to $INSTALLED_APP"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"

# Scope quarantine removal to the app we just built locally.
xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true

# --- 5. Verify the installed copy -----------------------------------------
plutil -lint "$INSTALLED_APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

# --- 6. Launch -------------------------------------------------------------
if [[ "$OPEN_AFTER" == "1" ]]; then
  echo "==> launching"
  open "$INSTALLED_APP"
fi

echo
echo "Installed: $INSTALLED_APP"
echo "Press ⌥Space to open the launcher."
echo "Uninstall: pkill -x $EXECUTABLE 2>/dev/null || true; rm -rf \"$INSTALLED_APP\""
