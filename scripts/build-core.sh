#!/usr/bin/env bash
# Builds the Rust core as an XCFramework and generates Swift bindings
# into app/Packages/MdCore. Apple Silicon only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
PKG="$ROOT/app/Packages/MdCore"
TARGET="aarch64-apple-darwin"
PROFILE="${PROFILE:-release}"
GEN="$CORE/target/uniffi-gen"

# Xcode build phases run with a minimal PATH.
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0

cd "$CORE"
CARGO_FLAGS=(--target "$TARGET" -p mdcore-ffi --lib)
[[ "$PROFILE" == "release" ]] && CARGO_FLAGS+=(--release)
cargo build "${CARGO_FLAGS[@]}"
LIB="$CORE/target/$TARGET/$PROFILE/libmdcore_ffi.a"

rm -rf "$GEN" && mkdir -p "$GEN/headers"
cargo run -q -p mdcore-ffi --bin uniffi-bindgen -- \
  generate --library "$LIB" --language swift --out-dir "$GEN"

# XCFramework expects headers + module.modulemap in one directory.
mv "$GEN"/*.h "$GEN/headers/"
cat "$GEN"/*.modulemap > "$GEN/headers/module.modulemap"

rm -rf "$PKG/MdCoreFFI.xcframework"
xcodebuild -create-xcframework \
  -library "$LIB" -headers "$GEN/headers" \
  -output "$PKG/MdCoreFFI.xcframework" >/dev/null

mkdir -p "$PKG/Sources/MdCore"
cp "$GEN"/*.swift "$PKG/Sources/MdCore/"
echo "MdCore built ($PROFILE, $TARGET)"
