#!/usr/bin/env bash
# One command: build the app from the terminal.
#   macos/build.sh                  -> macos/build/FontDrop.app
#   macos/build.sh --run            -> build, then launch
#   macos/build.sh --test           -> build and run the unit tests
#   macos/build.sh --rebuild-core   -> regenerate the Rust lib + Swift bindings first (core/build-swift.sh)
# Needs Xcode. XcodeGen (brew install xcodegen) is only needed when project.yml changes.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

RUN=0; TEST=0; REBUILD=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --test) TEST=1 ;;
    --rebuild-core) REBUILD=1 ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done

# The Rust core becomes an XCFramework + generated Swift. Both are git-ignored.
if [[ $REBUILD == 1 || ! -d FontDropCore/FontDropCore.xcframework ]]; then
  "$HERE/../core/build-swift.sh"
fi

# Regenerate the Xcode project when the spec is newer than the project (or the project is missing).
if command -v xcodegen >/dev/null 2>&1; then
  if [[ ! -d FontDrop.xcodeproj || project.yml -nt FontDrop.xcodeproj/project.pbxproj ]]; then
    xcodegen generate --quiet
  fi
fi

DERIVED="$HERE/build/DerivedData"
if [[ $TEST == 1 ]]; then
  xcodebuild test -project FontDrop.xcodeproj -scheme FontDrop -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" -quiet
  exit 0
fi

xcodebuild build -project FontDrop.xcodeproj -scheme FontDrop -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" -quiet

APP="$HERE/build/FontDrop.app"
rm -rf "$APP"
cp -R "$DERIVED/Build/Products/Release/FontDrop.app" "$APP"
echo "built $APP"
[[ $RUN == 1 ]] && open "$APP"
exit 0
