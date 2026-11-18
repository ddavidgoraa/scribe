#!/usr/bin/env bash
# Regenerates the app icon set from scripts/icon/make-icon.swift (the icon's source).
set -euo pipefail
cd "$(dirname "$0")/../.."
SET=app/Scribe/Assets.xcassets/AppIcon.appiconset
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swift scripts/icon/make-icon.swift "$work/icon-1024.png" >/dev/null
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/icon-1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$work/icon-1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
echo "icon set written to $SET"
