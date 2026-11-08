#!/usr/bin/env bash
# Builds Scribe.app (Release, Apple Silicon) and packages it as dist/Scribe-<version>-arm64.dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' app/project.yml)}"
BUILD="$ROOT/app/build"
DIST="$ROOT/dist"
STAGE="$DIST/dmg"

./scripts/build-core.sh
(cd app && xcodegen generate --quiet)
xcodebuild -project app/Scribe.xcodeproj -scheme Scribe -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD" \
  MARKETING_VERSION="$VERSION" build | tail -1

rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$BUILD/Build/Products/Release/Scribe.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Scribe-$VERSION-arm64.dmg"
rm -f "$DMG"
hdiutil create -volname "Scribe $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
