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

VERSION=0.5.0
BUILD=10

swift build -c release --product GlyphNative

APP="build/Glyph Native.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GlyphNative "$APP/Contents/MacOS/GlyphNative"
# Debug info and symbols carry the absolute path of every source file and checkout. A public
# build must not ship them (and SwiftPM also bakes in a dependency's resource-bundle build path).
if [[ -n ${GLYPH_NATIVE_RELEASE:-} || ! -f scripts/install-all.sh ]]; then strip -S -x "$APP/Contents/MacOS/GlyphNative" 2>/dev/null
  python3 - "$APP/Contents/MacOS/GlyphNative" <<'PY'
import re, sys
p = sys.argv[1]; b = open(p, "rb").read()
b = re.sub(rb"/Users/[ -~]*?\.bundle", lambda m: (b"/nonexistent" + b"/" * len(m.group(0)))[:len(m.group(0))], b)
open(p, "wb").write(b)
PY
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/icons/icon-*.png assets/icons/mark-*.png "$APP/Contents/Resources/"
cp scripts/install-release.sh "$APP/Contents/Resources/"
# The repo's main checkout (the first worktree), never a short-lived one: Install All fetches it and
# builds from a fresh worktree of origin/main that it removes after.
REPO=$(git -C .. worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p') || true   # not inside a git repo at all: the public copy
[[ -n $REPO ]] || REPO=$(cd .. && pwd)

# GLYPH_NATIVE_RELEASE=1: the public build. No source checkout is baked in, which is what puts the app
# in release mode (it lists five apps and downloads their signed releases), and it is named for the public.
# A copy of this folder outside the family's repo (no install-all.sh to build from) is always that build.
[[ -f scripts/install-all.sh ]] || GLYPH_NATIVE_RELEASE=1
NAME="Glyph Labs"; REPO_KEY="  <key>GlyphNativeRepo</key><string>$REPO</string>"
if [[ -n ${GLYPH_NATIVE_RELEASE:-} ]]; then NAME="Glyph Native"; REPO_KEY=""; fi

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
$REPO_KEY
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
