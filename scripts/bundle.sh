#!/usr/bin/env bash
# Assembles build/Meetie.app from the SwiftPM release binary + assets/ (see ASSETS.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"   # CONFIG=debug bundles the debug binary (Test Dog enabled)
BIN="$ROOT/.build/$CONFIG/Meetie"
APP="$ROOT/build/Meetie.app"
RES="$APP/Contents/Resources"

[ -x "$BIN" ] || { echo "error: $BIN not found — run 'swift build -c $CONFIG' first" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$RES/dog-sprite/shiba" "$RES/dog-sprite/corgi" \
         "$RES/menubar" "$RES/bark" "$RES/banner"

cp "$BIN" "$APP/Contents/MacOS/Meetie"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App + menu bar icons (R20, ASSETS.md)
cp "$ROOT/assets/icons/app/Meetie-clock.icns" "$RES/AppIcon.icns"
cp "$ROOT/assets/icons/menubar/created/clock@1x.png" "$RES/menubar/"
cp "$ROOT/assets/icons/menubar/created/clock@2x.png" "$RES/menubar/"

# Dog sprites (R14a)
for v in shiba corgi; do
  for i in 1 2 3 4 5 6 7 8; do
    cp "$ROOT/assets/dog-sprite/created/$v/frame$i.png" "$RES/dog-sprite/$v/"
  done
done

# Banner sign + Join button, 9-slice (R14)
cp "$ROOT/assets/banner/created/sign@3x.png" "$RES/banner/"
cp "$ROOT/assets/banner/created/join@3x.png" "$RES/banner/"

# Bark pool (R16a)
cp "$ROOT/assets/bark/found/rubberduck-cartoon-barks/bark-01.wav" "$RES/bark/"
cp "$ROOT/assets/bark/found/rubberduck-cartoon-barks/bark-02.wav" "$RES/bark/"
cp "$ROOT/assets/bark/found/brandon-morris-real-bark/bark-single.wav" "$RES/bark/"
cp "$ROOT/assets/bark/found/brandon-morris-real-bark/dog_barking_mono_full.wav" "$RES/bark/"

# Ad-hoc signature — local personal build, not notarized (R28)
codesign --force --sign - "$APP"

echo "Built $APP"
