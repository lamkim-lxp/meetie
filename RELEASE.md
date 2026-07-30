# Public release guide

This guide creates a signed, notarized DMG for direct distribution outside the
Mac App Store. The resulting app should open normally under Gatekeeper on
macOS 14 or later.

The current `make app` command creates a release bundle with an ad-hoc
signature. The steps below replace that signature with a Developer ID
signature before packaging and notarization.

## Requirements

- A paid [Apple Developer Program](https://developer.apple.com/programs/)
  membership
- Xcode and its command line tools
- A `Developer ID Application` certificate installed in the login keychain
- An Apple ID app-specific password for notarization
- A clean checkout of the release commit

Create the certificate in Xcode under **Settings > Accounts > Manage
Certificates**, then confirm that it is available:

```sh
security find-identity -v -p codesigning
```

The identity should look like:

```text
Developer ID Application: Your Name (TEAMID)
```

## 1. Choose release values

Run all commands from the repository root. Replace the signing identity with
the exact value reported by `security find-identity`.

```sh
export VERSION="1.0.0"
export BUILD_NUMBER="1"
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="meetie-notary"
export APP="build/Meetie.app"
export DMG="build/Meetie-${VERSION}.dmg"
```

`VERSION` is the user-facing version. `BUILD_NUMBER` must be an integer that
increases with every distributed build, including rebuilds of the same
version.

## 2. Set the bundle version

Update the source `Info.plist` before building:

```sh
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString ${VERSION}" \
  Support/Info.plist

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
  Support/Info.plist
```

Review and commit the version change as part of the release commit.

## Automated release

After completing the certificate, version, and notarization credential setup,
run the release script from a clean working tree:

```sh
export NOTARY_PROFILE="meetie-notary"
scripts/release.sh
```

The script reads the version from `Support/Info.plist`, runs the tests, builds
the release app, signs the app and DMG, submits it for notarization, staples
the ticket, runs Gatekeeper validation, and creates a SHA-256 checksum. It
automatically selects the installed `Developer ID Application` identity when
exactly one is available. It rejects `Apple Development` identities because
they cannot sign a public release.

If multiple Developer ID identities are installed, select one explicitly
using the SHA-1 hash printed by the script:

```sh
scripts/release.sh --signing-identity "CERTIFICATE_SHA1"
```

Successful output is written to:

```text
build/Meetie-VERSION.dmg
build/Meetie-VERSION.dmg.sha256
```

Use `scripts/release.sh --help` to see its options. `--allow-dirty` and
`--skip-tests` are intended only for troubleshooting and must not be used for
a public release.

The remaining sections document the individual steps performed by the script
and can be used for troubleshooting.

## 3. Test and build

Start from a clean working tree and run the complete test suite:

```sh
git status --short
swift test
make clean
make app
```

Confirm the generated executable's architecture:

```sh
file "${APP}/Contents/MacOS/Meetie"
```

The current SwiftPM build produces a binary for the build Mac's native
architecture. A build made on Apple Silicon therefore supports Apple Silicon
Macs, but not Intel Macs. Do not advertise Intel support unless the release
pipeline is changed to produce and test a universal `arm64` and `x86_64`
binary.

## 4. Apply the Developer ID signature

The bundle script applies an ad-hoc signature. Replace it with the release
signature and enable the hardened runtime required by notarization:

```sh
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "${SIGNING_IDENTITY}" \
  "${APP}"
```

Verify the signature:

```sh
codesign --verify --strict --verbose=2 "${APP}"
codesign --display --verbose=4 "${APP}"
```

Check that the displayed authority is the expected Developer ID identity and
that a secure timestamp is present.

Do not modify the app after signing it. Any change to its executable,
resources, or `Info.plist` invalidates the signature.

## 5. Create and sign the DMG

Create a temporary DMG folder containing Meetie and an Applications shortcut:

```sh
rm -rf build/dmg-root
mkdir -p build/dmg-root
cp -R "${APP}" build/dmg-root/
ln -s /Applications build/dmg-root/Applications
rm -f "${DMG}"

hdiutil create \
  -volname "Meetie" \
  -srcfolder build/dmg-root \
  -format UDZO \
  -ov \
  "${DMG}"

codesign \
  --force \
  --timestamp \
  --sign "${SIGNING_IDENTITY}" \
  "${DMG}"
```

Verify the DMG signature:

```sh
codesign --verify --verbose=2 "${DMG}"
```

## 6. Configure notarization credentials

Create an app-specific password at
[account.apple.com](https://account.apple.com/). Store it in the macOS
Keychain once, rather than putting it in a script or shell history:

```sh
xcrun notarytool store-credentials "${NOTARY_PROFILE}" \
  --apple-id "you@example.com" \
  --team-id "TEAMID"
```

The command securely prompts for the app-specific password. The profile can be
reused for future releases.

For CI, prefer an App Store Connect API key stored in the CI provider's secret
manager.

## 7. Submit for notarization

Upload the DMG and wait for Apple's result:

```sh
xcrun notarytool submit "${DMG}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
```

Continue only if the final status is `Accepted`. If Apple rejects the
submission, copy the submission ID from the output and inspect its log:

```sh
xcrun notarytool log "SUBMISSION_ID" \
  --keychain-profile "${NOTARY_PROFILE}"
```

Fix the reported problem, then rebuild, sign, package, and submit again. Do not
reuse a DMG that was modified after signing.

## 8. Staple and validate

Attach the notarization ticket so Gatekeeper can verify the DMG without a
network connection:

```sh
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "${DMG}"
```

The assessment should report `accepted`.

## 9. Test the distributed artifact

Test the exact DMG that will be uploaded, ideally on a different Mac or a clean
macOS user account:

1. Download the DMG through the same browser and hosting service users will
   use. This ensures the file receives the normal quarantine attribute.
2. Open the DMG and drag Meetie to Applications.
3. Launch Meetie normally, without right-clicking or bypassing Gatekeeper.
4. Confirm onboarding appears and Calendar permission can be granted.
5. Confirm the menu bar item, meeting lookup, Test Dog replacement behavior,
   sound, Join action, and Launch at Login.
6. Restart the Mac and verify Launch at Login if it was enabled.

Public builds must not expose the debug-only Test Dog menu item or accept the
debug command-line flags.

## 10. Publish

Create a checksum for the final artifact:

```sh
shasum -a 256 "${DMG}" > "${DMG}.sha256"
```

Upload both files over HTTPS and publish:

- Version and build number
- Minimum supported version: macOS 14
- Supported CPU architecture
- SHA-256 checksum
- Release notes
- Installation instructions
- Calendar access and privacy explanation

Keep the notarized DMG unchanged after validation. Repackaging or modifying it
requires signing and notarization again.

## Release checklist

- [ ] Release commit is selected and the working tree is clean
- [ ] `CFBundleShortVersionString` and `CFBundleVersion` are updated
- [ ] `swift test` passes
- [ ] Release build contains no debug-only features
- [ ] Executable architecture matches the advertised support
- [ ] App is signed with Developer ID and hardened runtime
- [ ] DMG is signed
- [ ] Notarization status is `Accepted`
- [ ] Notarization ticket is stapled and validated
- [ ] Gatekeeper assessment reports `accepted`
- [ ] Downloaded DMG passes a clean installation test
- [ ] SHA-256 checksum and release notes are published

## Project documentation follow-up

Before the first public release, update the project documentation that still
describes Meetie as a personal, ad-hoc-signed build:

- `README.md`, under **Build & run**
- `docs/SPEC.md`, requirement R28

The bundled sounds are documented as CC0, and the sprites and icons as
original works, in `assets/ASSETS.md`. Reconfirm that manifest before each
public release.
