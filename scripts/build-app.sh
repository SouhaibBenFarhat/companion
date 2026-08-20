#!/bin/bash
# Builds dist/Companion.app and dist/Companion-arm64.zip for release.
# Usage: scripts/build-app.sh [version]   (default: 0.1.0)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"

# A development build is a separate app to macOS: its own bundle identifier,
# its own name, its own permissions and its own storage. Without that split a
# build under test writes into the installed app's conversations, and each
# holds permissions the other cannot use.
#
#   scripts/build-app.sh              production
#   scripts/build-app.sh 0.1.0 dev    development
VARIANT="${2:-release}"

if [ "$VARIANT" = "dev" ]; then
  APP_NAME="Companion Dev"
  BUNDLE_ID="com.souhaibbenfarhat.companion.dev"
else
  APP_NAME="Companion"
  BUNDLE_ID="com.souhaibbenfarhat.companion"
fi

APP="dist/${APP_NAME}.app"
ZIP="dist/Companion-arm64.zip"

# The interface is React, built by Vite and copied into the bundle. It has to
# exist before the app is assembled, or Companion launches to an empty panel.
if [ ! -d web/node_modules ]; then
  echo "==> Installing interface dependencies"
  npm --prefix web ci
fi

# Kept in step with the template on every build.
scripts/make-dev-plist.sh > /dev/null

echo "==> Building the interface"
npm --prefix web run build

if [ ! -f packaging/AppIcon.icns ]; then
  echo "==> Generating app icon"
  swift scripts/make-icon.swift
fi

echo "==> Building release binary (arm64)"
swift build -c release --arch arm64

echo "==> Assembling ${APP} (v${VERSION}, ${BUNDLE_ID})"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Companion "$APP/Contents/MacOS/Companion"
sed -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__APP_NAME__/$APP_NAME/g" \
    packaging/Info.plist > "$APP/Contents/Info.plist"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R web/dist "$APP/Contents/Resources/web"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

# Only the production build is ever released, so only it is zipped.
if [ "$VARIANT" = "dev" ]; then
  echo "==> Done (development build, not zipped)"
  echo "    $APP"
  echo "    data: ~/Library/Application Support/${APP_NAME}"
  exit 0
fi

echo "==> Zipping"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done"
shasum -a 256 "$ZIP"
