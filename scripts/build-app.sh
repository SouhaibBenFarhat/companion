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

# Which identity signs the bundle.
#
# macOS does not remember an app by its name or its path. It remembers the
# fingerprint of its code, and every permission you grant is filed against that
# fingerprint. An ad-hoc signature has no stable identity, so changing one line
# and rebuilding produces what macOS considers a different app with the same
# name: the switches you turned on in System Settings stay in the list, still
# looking on, pointing at a build that no longer exists. Microphone, Screen
# Recording and Accessibility all have to be granted again, every time.
#
# A self-signed certificate fixes that. It is free, it is made locally in
# Keychain Access, and it proves nothing to anybody else — which is fine,
# because the only thing being asked of it is to stay the same tomorrow.
#
#   Keychain Access -> Certificate Assistant -> Create a Certificate...
#   Name: Companion Dev Signing   Identity Type: Self Signed Root
#   Certificate Type: Code Signing
#
# Release builds stay ad-hoc: a certificate only this Mac has means nothing on
# anybody else's.
SIGNING_IDENTITY="${COMPANION_SIGNING_IDENTITY:-Companion Dev Signing}"

if [ "$VARIANT" = "dev" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
  echo "==> Signing as ${SIGNING_IDENTITY}"
  codesign --force --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "==> Signing (ad-hoc)"
  codesign --force --sign - "$APP"
  if [ "$VARIANT" = "dev" ]; then
    echo "    No '${SIGNING_IDENTITY}' certificate found, so this build has no"
    echo "    stable identity: macOS will drop its permissions on the next"
    echo "    rebuild. See the comment above this line in scripts/build-app.sh."
  fi
fi

# What macOS actually matches a permission against, printed so a lost grant can
# be checked rather than guessed at.
#
# For a signed build this is the designated requirement, and it must be
# identical from one build to the next — the code hash changes every time and
# does not matter. For an ad-hoc build there is no certificate to name, the
# requirement falls back to the code hash, and every rebuild is a new app.
codesign -d -r- "$APP" 2>&1 | grep 'designated' | sed 's/^/    /'

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
