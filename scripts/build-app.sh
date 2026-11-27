#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product CodexQuota
APP="build/CodexQuota.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CodexQuota "$APP/Contents/MacOS/CodexQuota"
cp Support/Info.plist "$APP/Contents/Info.plist"
ICON_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_DIR"' EXIT
swift -framework AppKit scripts/render-icon.swift "$ICON_DIR/icon.png"
ICONSET="$ICON_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "build/CodexQuota.zip"
echo "$PWD/$APP"
echo "$PWD/build/CodexQuota.zip"
