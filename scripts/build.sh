#!/usr/bin/env bash
# Builds "build/Glyph Native.app" (the Mac side of the launcher: see and install every Glyph Native app) from this folder (SwiftPM, no Xcode needed). Signs with the Apple
# Development identity when there is one, else ad hoc; SIGN_IDENTITY=<identity> signs with that
# instead. --install copies it to /Applications.
set -euo pipefail

# Fru, 2026-10-31, stated three times and absolute: nothing executes on the Mac he works on.
# Builds, tests, simulators, screenshots and microphone checks go to the unattended desktop or to
# a laptop deliberately marked as a test host. The desktop has no battery and needs no flag.
# Detecting a battery rather than matching a computer name, because a name match wrongly refuses
# on a dedicated test laptop whose name happens to match the pattern.
if pmset -g batt 2>/dev/null | grep -q InternalBattery && [[ -z ${GLYPH_UI_HOST:-} ]]; then
  echo >&2 "Nothing executes on the Mac being worked on. Run this on the unattended desktop,"
  echo >&2 "or on a test laptop with GLYPH_UI_HOST=1 set."
  exit 2
fi
cd "$(dirname "$0")/.."

VERSION=0.6.3
BUILD=14

[[ -d /Applications/Xcode.app ]] && export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} # the on-device model's macros
swift build -c release --product GlyphNative

APP="build/Glyph Native.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GlyphNative "$APP/Contents/MacOS/GlyphNative"
# Debug info and symbols carry the absolute path of every source file and checkout. A public
# build must not ship them (and SwiftPM also bakes in a dependency's resource-bundle build path).
strip -S -x "$APP/Contents/MacOS/GlyphNative" 2>/dev/null
  python3 - "$APP/Contents/MacOS/GlyphNative" <<'PY'
import re, sys
p = sys.argv[1]; b = open(p, "rb").read()
b = re.sub(rb"/Users/[ -~]*?\.bundle", lambda m: (b"/nonexistent" + b"/" * len(m.group(0)))[:len(m.group(0))], b)
open(p, "wb").write(b)
PY
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/icons/icon-*.png assets/icons/mark-*.png "$APP/Contents/Resources/"
cp scripts/install-release.sh "$APP/Contents/Resources/"
# One build: Glyph Native, which downloads each app's signed release. The source build that built the
# apps itself (Glyph Labs, Install All) was retired 2026-11-13. GLYPH_NATIVE_RELEASE is no longer read.
NAME="Glyph Native"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>dev.fru.glyph.native.mac</string>
  <key>CFBundleExecutable</key><string>GlyphNative</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- The vault computer is the person's own machine on their own network or tailnet, reached over plain http. -->
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>NSBonjourServices</key><array><string>_glyph-vault._tcp</string></array>
  <key>NSLocalNetworkUsageDescription</key><string>Glyph Native looks for your vault computer on this network.</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 fru.dev</string>
</dict>
</plist>
PLIST

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -v REVOKED | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)}
if [[ $IDENTITY == "Developer ID Application"* ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null
else
  codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
fi
echo "Built $APP $VERSION (signed: ${IDENTITY:-ad-hoc})"

for arg in "$@"; do
  case "$arg" in
    --install)
      pkill -x GlyphNative 2>/dev/null || true
      rm -rf "/Applications/Glyph Native.app"
      cp -R "$APP" /Applications/
      echo "Installed /Applications/Glyph Native.app"
      ;;
  esac
done
