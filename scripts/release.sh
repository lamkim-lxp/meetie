#!/usr/bin/env bash
# Builds, signs, notarizes, and validates a public Meetie DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT/Support/Info.plist"
APP="$ROOT/build/Meetie.app"
ALLOW_DIRTY=false
SKIP_TESTS=false
STAGING=""

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [options]

Build, sign, notarize, staple, and validate a public Meetie DMG.
The version and build number are read from Support/Info.plist.

Required environment:
  SIGNING_IDENTITY  Exact Developer ID Application identity from Keychain

Optional environment:
  NOTARY_PROFILE    notarytool Keychain profile (default: meetie-notary)

Options:
  --allow-dirty     Allow release creation from a dirty Git working tree
  --skip-tests      Skip the Swift test suite
  -h, --help        Show this help

Example:
  SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
    scripts/release.sh
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty)
      ALLOW_DIRTY=true
      ;;
    --skip-tests)
      SKIP_TESTS=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-meetie-notary}"

[[ -n "$SIGNING_IDENTITY" ]] ||
  die "SIGNING_IDENTITY is required; run 'security find-identity -v -p codesigning'"

for command in codesign git hdiutil lipo make security shasum spctl swift xcrun; do
  command -v "$command" >/dev/null 2>&1 ||
    die "required command not found: $command"
done

[[ -f "$INFO_PLIST" ]] || die "Info.plist not found: $INFO_PLIST"

cd "$ROOT"

if [[ "$ALLOW_DIRTY" == false ]]; then
  [[ -z "$(git status --porcelain)" ]] ||
    die "Git working tree is not clean; commit the release changes or use --allow-dirty"
fi

IDENTITIES="$(security find-identity -v -p codesigning)"
[[ "$IDENTITIES" == *"\"$SIGNING_IDENTITY\""* ]] ||
  die "SIGNING_IDENTITY does not match an available code-signing identity"

VERSION="$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "$INFO_PLIST"
)"
BUILD_NUMBER="$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleVersion" \
    "$INFO_PLIST"
)"

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
  die "CFBundleShortVersionString must contain two or three numeric components"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] ||
  die "CFBundleVersion must be a positive integer"

DMG="$ROOT/build/Meetie-${VERSION}.dmg"
CHECKSUM="$DMG.sha256"
NOTARY_RESULT="$ROOT/build/notary-result.json"

printf 'Release version: %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'Signing identity: %s\n' "$SIGNING_IDENTITY"
printf 'Notary profile: %s\n' "$NOTARY_PROFILE"

if [[ "$SKIP_TESTS" == false ]]; then
  log "Running tests"
  swift test
else
  log "Skipping tests by request"
fi

log "Building release app"
make clean
make app

[[ -d "$APP" ]] || die "release app was not created: $APP"
[[ -x "$APP/Contents/MacOS/Meetie" ]] ||
  die "release executable is missing"

APP_VERSION="$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist"
)"
APP_BUILD_NUMBER="$(
  /usr/libexec/PlistBuddy \
    -c "Print :CFBundleVersion" \
    "$APP/Contents/Info.plist"
)"
[[ "$APP_VERSION" == "$VERSION" && "$APP_BUILD_NUMBER" == "$BUILD_NUMBER" ]] ||
  die "built app version does not match Support/Info.plist"

ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/Meetie")"
printf 'Executable architectures: %s\n' "$ARCHITECTURES"

log "Signing app with Developer ID"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP"

codesign --verify --strict --verbose=2 "$APP"

log "Creating DMG"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/meetie-release.XXXXXX")"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG" "$CHECKSUM" "$NOTARY_RESULT"

hdiutil create \
  -volname "Meetie" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$DMG"

log "Signing DMG"
codesign \
  --force \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$DMG"

codesign --verify --verbose=2 "$DMG"

log "Submitting DMG for notarization"
if ! xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json | tee "$NOTARY_RESULT"; then
  die "notarization command failed; inspect $NOTARY_RESULT"
fi

NOTARY_STATUS="$(
  /usr/bin/plutil -extract status raw "$NOTARY_RESULT" 2>/dev/null || true
)"
SUBMISSION_ID="$(
  /usr/bin/plutil -extract id raw "$NOTARY_RESULT" 2>/dev/null || true
)"

if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  if [[ -n "$SUBMISSION_ID" ]]; then
    printf '\nNotarization log for %s:\n' "$SUBMISSION_ID" >&2
    xcrun notarytool log "$SUBMISSION_ID" \
      --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fi
  die "notarization was not accepted; status: ${NOTARY_STATUS:-unknown}"
fi

log "Stapling notarization ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

log "Running Gatekeeper assessment"
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$DMG"

log "Creating SHA-256 checksum"
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" >"$(basename "$CHECKSUM")"
)

printf '\nRelease ready:\n'
printf '  %s\n' "$DMG"
printf '  %s\n' "$CHECKSUM"
printf '\nTest the downloaded DMG on a clean macOS account before publishing.\n'
