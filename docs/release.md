# Releasing FontDrop

One command builds, signs, notarizes, staples and packs the app:

```bash
make release                        # Developer ID build for the public
make release NOTARY_PROFILE=name    # use another notarytool profile name
make release-adhoc                  # ad-hoc build for testing on this Mac (same as scripts/release.sh --adhoc)
```

The DMG lands in `dist/` (git-ignored): `FontDrop-<version>.dmg`, or `FontDrop-<version>-adhoc.dmg` for the ad-hoc build. The version comes from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `macos/project.yml`. Raise them before you release.

## One-time setup

You need a paid Apple Developer account.

1. **The certificate.** Xcode > Settings > Accounts > pick your team > Manage Certificates > `+` > **Developer ID Application**. Check it with `security find-identity -v -p codesigning`. A line that says `Developer ID Application: <Name> (<TEAMID>)` means you are ready. If you have more than one, pick one with `DEVELOPER_ID="Developer ID Application: ..." make release`.
2. **The notarization login.** Make an app-specific password at appleid.apple.com (Sign-In and Security > App-Specific Passwords). Then store it once in your keychain:

   ```bash
   xcrun notarytool store-credentials "fontdrop-notary" \
     --apple-id <you@example.com> --team-id <TEAMID>
   ```

   It asks for the app-specific password and keeps it in the keychain under the name you gave. The script never sees the password, only the profile name (`NOTARY_PROFILE`, default `fontdrop-notary`).

If the certificate is missing the script stops at once and says what to create. It never builds half a release.

## What the script does

1. Picks the signing identity and checks the notary profile (before any slow work).
2. Builds the Rust core if needed (`core/build-swift.sh`, about 3 minutes the first time), then the app in Release.
3. Signs the app with the hardened runtime and a secure timestamp.
4. Submits it to Apple with `xcrun notarytool submit --wait`, then staples the ticket to the app.
5. Packs the app and an Applications shortcut into a DMG, signs the DMG, notarizes it and staples it.

The ad-hoc path skips steps 4 and notarization of the DMG. Its DMG opens on this Mac. On another Mac, Gatekeeper warns: right-click the app and choose Open.

FontDrop is not sandboxed (it reads `~/Library/Fonts` and the shared library), so there is no entitlements file. If a future change needs one (for example to load a plug-in), add it to `scripts/release.sh` as `--entitlements`.

## After the build

- Open the DMG on a second Mac (or a fresh macOS user account) and check that Gatekeeper does not warn: `spctl --assess --type execute -vv /Applications/FontDrop.app` should say `accepted, source=Notarized Developer ID`.
- Tag the commit (`git tag v0.2.0`), then on GitHub create a Release from the tag and attach the DMG. Paste the SHA-256 the script printed into the notes.

## The app icon

One asset: `macos/Sources/FontDrop/Resources/Assets.xcassets/AppIcon.appiconset`. The 1024 px source is `macos/Resources/AppIcon-source.png`. To change the icon, replace the source and run `macos/scripts/make-app-icon.sh`, which rewrites every size with `sips`.

## Keyboard check before a release

`macos/Tests/FontDropUITests/KeyboardUITests.swift` presses real keys and scrolls on a temp library with one brand and two fonts. Run it with `xcodebuild test -project macos/FontDrop.xcodeproj -scheme FontDropUI -destination 'platform=macOS'`. The test runner needs Automation permission (macOS asks once, in a dialog). Where that dialog cannot be answered, the run stops with "Timed out while enabling automation mode". Then do this by hand, on a library copy, without clicking anything first:

1. Open FontDrop. Press Down, then Return. The sidebar's Display row now names a face.
2. Press Command-2. Press Down, then Return. The Text row names a face.
3. Press Command-3. Hover the dial and scroll down until it reads 1.2. Scroll up once: 1.25. Scroll up again: 1.333. Each scroll is one stop.
4. Type a search that hides the selected face, press Return and Space. Nothing is chosen, no preview opens.
5. Drag the dial, the Body slider and the colour area. The window does not move. Drag the empty strip at the top of the sidebar: it does.
6. Open the New brand sheet and press Command-Z. The library's picks do not change.
7. Hide the sidebar (Control-Command-S). The search row and the Text list head clear the traffic lights. Quit and reopen: it stays hidden.
8. On Text, Command-= zooms in the stage, and so does Command-+.
