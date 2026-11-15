#!/usr/bin/env bash
# Installs a pinned XcodeGen release after verifying its checksum (used by CI).
set -euo pipefail

VERSION="2.46.0"
SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
DEST="${1:-$HOME/.local/xcodegen}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
echo "$SHA256  $work/xcodegen.zip" | shasum -a 256 --check --quiet
rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$work/xcodegen.zip" -d "$work"
cp -R "$work/xcodegen/." "$DEST/"
echo "$DEST/bin"
