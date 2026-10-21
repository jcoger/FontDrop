#!/usr/bin/env bash
# One command: build the app. Regenerates the Rust bindings first if they are missing.
#   macos/build.sh            -> macos/build/FontDrop.app
#   macos/build.sh --run      -> build, then launch
#   macos/build.sh --rebuild-core   force core/build-swift.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

if [[ "${1:-}" == "--rebuild-core" || ! -d FontDropCore/FontDropCore.xcframework ]]; then
  "$HERE/../core/build-swift.sh"
fi

swift build -c release --product FontDrop

BIN="$(swift build -c release --show-bin-path)/FontDrop"
APP="$HERE/build/FontDrop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FontDrop"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FontDrop</string>
  <key>CFBundleIdentifier</key><string>co.dynolabs.fontdrop.spike</string>
  <key>CFBundleExecutable</key><string>FontDrop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
[[ "${1:-}" == "--run" ]] && open "$APP"
exit 0
