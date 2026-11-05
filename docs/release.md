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
