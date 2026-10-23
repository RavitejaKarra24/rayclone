#!/usr/bin/env bash
#
# Builds the release binary and assembles a valid, ad-hoc signed
# Rayclone.app into dist/.
#
# Usage: Scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Rayclone"
BUNDLE_ID="com.rayclone.macos"
EXECUTABLE="Rayclone"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/$APP_NAME.app"
HOST_ARCH="$(uname -m)"

# A full Xcode toolchain is needed for the SwiftUI macro plugin; fall back to it
# automatically when it is installed.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# --- 0. Versions -----------------------------------------------------------
MARKETING_VERSION="1.0.0"
BUILD_NUMBER="1"
if [[ -f "$ROOT/version.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/version.env"
fi

# --- 1. Toolchain checks ---------------------------------------------------
if ! xcrun --find swift >/dev/null 2>&1 && ! command -v swift >/dev/null 2>&1; then
  echo "error: no Swift compiler found. Install the Xcode Command Line Tools:" >&2
  echo "       xcode-select --install" >&2
  exit 1
fi

# Different toolchains ship different SwiftPM build engines. Prefer the newer
# `swiftbuild` engine when the toolchain supports it, but never require it.
BUILD_ARGS=(-c release)
if swift build --help 2>/dev/null | grep -q -- "--build-system"; then
  if swift build --help 2>/dev/null | grep -q "swiftbuild"; then
    BUILD_ARGS=(--build-system swiftbuild "${BUILD_ARGS[@]}")
  fi
fi

# --- 2. Build --------------------------------------------------------------
echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}" --arch "$HOST_ARCH"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --arch "$HOST_ARCH" --show-bin-path)"
BIN="$BIN_DIR/$EXECUTABLE"
if [[ ! -x "$BIN" ]]; then
  echo "error: expected executable at $BIN" >&2
  exit 1
fi

# --- 3. Assemble the bundle ------------------------------------------------
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"

if [[ ! -f "$ROOT/Icon.icns" ]]; then
  echo "==> Icon.icns missing, rendering it"
  if command -v iconutil >/dev/null 2>&1; then
    swift "$ROOT/Scripts/make-icon.swift"
  else
    echo "    warn: iconutil unavailable, the app will use the generic icon" >&2
  fi
fi
if [[ -f "$ROOT/Icon.icns" ]]; then
  cp "$ROOT/Icon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundled data files (emoji dataset, etc.) also live next to the executable's
# resources so a missing SwiftPM bundle is not fatal.
if [[ -d "$ROOT/Sources/$APP_NAME/Resources" ]]; then
  cp -R "$ROOT/Sources/$APP_NAME/Resources/." "$APP/Contents/Resources/"
fi

# Copy SwiftPM resource bundles and normalise their layout. SwiftPM can emit a
# flat bundle; code signing rejects that with "unsealed contents present in the
# bundle root", so a flat bundle is converted to the standard structure.
shopt -s nullglob
BUNDLES=("$BIN_DIR"/*.bundle)
shopt -u nullglob
for bundle in "${BUNDLES[@]}"; do
  target="$APP/Contents/Resources/$(basename "$bundle")"
  cp -R "$bundle" "$target"
  if [[ ! -d "$target/Contents/Resources" ]]; then
    echo "    normalising flat bundle $(basename "$bundle")"
    tmp="$target.flat"
    mv "$target" "$tmp"
    mkdir -p "$target/Contents/Resources"
    shopt -s dotglob nullglob
    for entry in "$tmp"/*; do
      mv "$entry" "$target/Contents/Resources/"
    done
    shopt -u dotglob
    rm -rf "$tmp"
    cat > "$target/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID.resources</string>
    <key>CFBundleName</key><string>$(basename "$bundle" .bundle)</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
</dict>
</plist>
PLIST
  fi
done

# --- 4. Info.plist ---------------------------------------------------------
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Local build. Not affiliated with Raycast.</string>
    <key>NSAppleEventsUsageDescription</key><string>Rayclone sends Apple Events to Finder and System Events to run system actions such as emptying the Trash, toggling system appearance, and locking the screen.</string>
    <key>NSDesktopFolderUsageDescription</key><string>Rayclone reads filenames in your Desktop folder so you can find and open files from the launcher.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Rayclone reads filenames in your Documents folder so you can find and open files from the launcher.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Rayclone reads filenames in your Downloads folder so you can find and open files from the launcher.</string>
    <key>NSRemovableVolumesUsageDescription</key><string>Rayclone reads filenames on removable volumes so you can find and open files from the launcher.</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# --- 5. Sign ---------------------------------------------------------------
echo "==> signing (ad-hoc)"
# Strip extended attributes first: AppleDouble files break the seal.
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# Nested code first, then the outer bundle last.
while IFS= read -r -d '' nested; do
  codesign --force --sign - --timestamp=none "$nested" >/dev/null 2>&1 || true
done < <(find "$APP/Contents/Resources" -name '*.bundle' -print0)

codesign --force --sign - --timestamp=none "$APP"

# --- 6. Verify -------------------------------------------------------------
codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> built $APP"
