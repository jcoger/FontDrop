#!/usr/bin/env bash
# Regenerates everything Swift needs from the Rust core, from scratch:
#   1. builds libfontdrop_core.a (release, aarch64-apple-darwin, --features uniffi)
#   2. generates the Swift bindings with UniFFI (library mode, no .udl file)
#   3. packages the static lib + C header + modulemap as an XCFramework
#   4. writes the local Swift package macos/FontDropCore (Package.swift,
#      XCFramework, generated Swift)
# Generated files are git-ignored. Run from anywhere.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$CORE")"
CARGO="${CARGO:-$HOME/.cargo/bin/cargo}"
TARGET="aarch64-apple-darwin"
# Keep the static lib (bundled SQLite C code) on the app's deployment target, not the SDK default.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
PKG="$ROOT/macos/FontDropCore"
BUILD="$CORE/build"
LIB="$CORE/target/$TARGET/release/libfontdrop_core.a"

echo "==> clean"
rm -rf "$BUILD" "$PKG/FontDropCore.xcframework" "$PKG/Sources/FontDropCore/fontdrop_core.swift"
mkdir -p "$BUILD/headers" "$BUILD/swift" "$PKG/Sources/FontDropCore"

echo "==> cargo build (release, $TARGET)"
(cd "$CORE" && "$CARGO" build --release --features uniffi --target "$TARGET")

echo "==> generate Swift bindings"
(cd "$CORE" && "$CARGO" run --release --features bindgen --bin uniffi-bindgen -- \
  generate --library "$LIB" --language swift --out-dir "$BUILD/swift")

# UniFFI writes <crate>.swift, <crate>FFI.h and <crate>FFI.modulemap.
cp "$BUILD/swift/fontdrop_core.swift" "$PKG/Sources/FontDropCore/fontdrop_core.swift"
cp "$BUILD/swift/fontdrop_coreFFI.h" "$BUILD/headers/"
cp "$BUILD/swift/fontdrop_coreFFI.modulemap" "$BUILD/headers/module.modulemap"

echo "==> XCFramework"
xcodebuild -create-xcframework \
  -library "$LIB" -headers "$BUILD/headers" \
  -output "$PKG/FontDropCore.xcframework"

echo "==> done: $PKG"
