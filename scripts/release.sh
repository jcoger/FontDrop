#!/usr/bin/env bash
# Builds a release DMG of FontDrop.
#
#   scripts/release.sh            sign with Developer ID, notarize, staple, build a DMG (public release)
#   scripts/release.sh --adhoc    ad-hoc signed DMG for local testing only (Gatekeeper will warn on other Macs)
#
# Variables:
#   NOTARY_PROFILE   the keychain profile name you gave `xcrun notarytool store-credentials` (default: fontdrop-notary)
#   DEVELOPER_ID     the exact signing identity, if you have more than one Developer ID Application certificate
#
# One-time setup is in docs/release.md. Output: dist/FontDrop-<version>.dmg
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MAC="$ROOT/macos"
DIST="$ROOT/dist"
DERIVED="$MAC/build/DerivedData-release"
NOTARY_PROFILE="${NOTARY_PROFILE:-fontdrop-notary}"
ADHOC=0

for arg in "$@"; do
  case "$arg" in
    --adhoc) ADHOC=1 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown option: $arg. Use --adhoc or no option." >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }

# 1. Pick the signing identity before any slow work.
if [[ $ADHOC == 1 ]]; then
  IDENTITY="-"
  say "Ad-hoc build. This DMG is for testing on this Mac. Other Macs will show a Gatekeeper warning."
else
  IDENTITY="${DEVELOPER_ID:-}"
  if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
  fi
  if [[ -z "$IDENTITY" ]]; then
    cat >&2 <<'MSG'

There is no "Developer ID Application" certificate in your keychain, so FontDrop cannot be signed for release.

Create one once:
  1. Open Xcode > Settings > Accounts, pick your Apple Developer team, click Manage Certificates.
  2. Click the + button and choose "Developer ID Application".
  3. Run `security find-identity -v -p codesigning` and check that it is listed.

Then store notarization credentials once (see docs/release.md):
  xcrun notarytool store-credentials "fontdrop-notary" --apple-id <you@example.com> --team-id <TEAMID>

To make a DMG for testing on this Mac in the meantime, run:  scripts/release.sh --adhoc
MSG
    exit 1
  fi
  say "Signing as: $IDENTITY"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MSG

The notarization profile "$NOTARY_PROFILE" is not in your keychain (or Apple rejected it).
Create it once:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id <you@example.com> --team-id <TEAMID>
It asks for an app-specific password from appleid.apple.com. Or pass another name: NOTARY_PROFILE=<name> $0
MSG
    exit 1
  fi
fi

# 2. The Rust core, then the app (Release, signing off: we sign by hand below).
if [[ ! -d "$MAC/FontDropCore/FontDropCore.xcframework" ]]; then
  say "Building the Rust core (about 3 minutes the first time)"
  "$ROOT/core/build-swift.sh"
fi
if command -v xcodegen >/dev/null 2>&1; then
  (cd "$MAC" && xcodegen generate --quiet)
fi
say "Building FontDrop (Release)"
xcodebuild build -project "$MAC/FontDrop.xcodeproj" -scheme FontDrop -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" -quiet

BUILT="$DERIVED/Build/Products/Release/FontDrop.app"
[[ -d "$BUILT" ]] || { echo "The build did not produce FontDrop.app." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT/Contents/Info.plist")"
say "FontDrop $VERSION ($BUILD)"

rm -rf "$DIST"; mkdir -p "$DIST"
APP="$DIST/FontDrop.app"
cp -R "$BUILT" "$APP"

# 3. Sign with the hardened runtime. Nested code first, then the app.
SIGN_FLAGS=(--force --options runtime --sign "$IDENTITY")
[[ $ADHOC == 0 ]] && SIGN_FLAGS+=(--timestamp)
say "Signing"
while IFS= read -r nested; do
  codesign "${SIGN_FLAGS[@]}" "$nested"
done < <(find "$APP/Contents" \( -name '*.dylib' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' \) -print 2>/dev/null)
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "flags|Signature|Identifier" || true

# 4. Notarize and staple the app (Developer ID only).
if [[ $ADHOC == 0 ]]; then
  say "Notarizing the app (a few minutes)"
  ditto -c -k --keepParent "$APP" "$DIST/FontDrop-app.zip"
  xcrun notarytool submit "$DIST/FontDrop-app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$DIST/FontDrop-app.zip"
fi

# 5. The DMG: the app next to an Applications shortcut.
say "Building the DMG"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/FontDrop.app"
ln -s /Applications "$STAGE/Applications"
if [[ $ADHOC == 1 ]]; then DMG="$DIST/FontDrop-$VERSION-adhoc.dmg"; else DMG="$DIST/FontDrop-$VERSION.dmg"; fi
hdiutil create -volname "FontDrop" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ $ADHOC == 0 ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  say "Notarizing the DMG (a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG" || true
fi

hdiutil verify "$DMG" >/dev/null
say "Done: $DMG"
shasum -a 256 "$DMG"
