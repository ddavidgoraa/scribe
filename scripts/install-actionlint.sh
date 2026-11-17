#!/usr/bin/env bash
# Installs a pinned actionlint release after verifying its checksum (used by CI).
set -euo pipefail

VERSION="1.7.12"
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  PLATFORM="linux_amd64";  SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8" ;;
    Darwin-arm64)  PLATFORM="darwin_arm64"; SHA256="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f" ;;
    *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
DEST="${1:-$HOME/.local/actionlint}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="actionlint_${VERSION}_${PLATFORM}.tar.gz"
curl -fsSL -o "$work/$archive" "https://github.com/rhysd/actionlint/releases/download/v$VERSION/$archive"
echo "$SHA256  $work/$archive" | shasum -a 256 --check --quiet
mkdir -p "$DEST"
tar -xzf "$work/$archive" -C "$DEST" actionlint
echo "$DEST"
