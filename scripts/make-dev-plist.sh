#!/bin/bash
# Regenerates packaging/Info.dev.plist from packaging/Info.plist.
#
# The file is committed even though it is generated. `swift build` links it
# into the development binary, so a checkout without it cannot compile — and
# generating it as a build step would mean every clone needs a bootstrap
# command before the package works at all.
#
# CI checks the committed copy still matches this output, so it cannot drift.
set -euo pipefail
cd "$(dirname "$0")/.."

sed -e "s/__VERSION__/0.0.0-dev/g" \
    -e "s/__BUNDLE_ID__/com.souhaibbenfarhat.companion.dev/g" \
    -e "s/__APP_NAME__/Companion Dev/g" \
    packaging/Info.plist > packaging/Info.dev.plist

echo "wrote packaging/Info.dev.plist"
