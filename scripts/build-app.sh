#!/bin/bash
# Builds dist/Companion.app and dist/Companion-arm64.zip for release.
# Usage: scripts/build-app.sh [version]   (default: 0.1.0)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="dist/Companion.app"
ZIP="dist/Companion-arm64.zip"

# The interface is React, built by Vite and copied into the bundle. It has to
# exist before the app is assembled, or Companion launches to an empty panel.
if [ ! -d web/node_modules ]; then
  echo "==> Installing interface dependencies"
  npm --prefix web ci
fi

echo "==> Building the interface"
npm --prefix web run build

if [ ! -f packaging/AppIcon.icns ]; then
  echo "==> Generating app icon"
  swift scripts/make-icon.swift
fi

echo "==> Building release binary (arm64)"
swift build -c release --arch arm64

echo "==> Assembling ${APP} (v${VERSION})"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Companion "$APP/Contents/MacOS/Companion"
sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R web/dist "$APP/Contents/Resources/web"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Zipping"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done"
shasum -a 256 "$ZIP"
