#!/bin/zsh
# Build Glyph Native, sign it with Developer ID (hardened runtime), notarize and staple the disk
# image, check a quarantined copy passes Gatekeeper, and publish a GitHub release on
# fru-dev3/glyph-native: Glyph-Native-<version>.dmg plus Glyph-Native.dmg (the stable
# releases/latest/download link). Run it in the public clone.
# Needs a "Developer ID Application" certificate in the keychain, an App Store Connect API key
# for notarization (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH in the environment), and gh signed in.
set -euo pipefail
cd "${0:A:h}/.."
: ${ASC_KEY_ID:?set ASC_KEY_ID} ${ASC_ISSUER_ID:?set ASC_ISSUER_ID} ${ASC_KEY_PATH:?set ASC_KEY_PATH}
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
[[ -n $identity ]] || { echo "no Developer ID Application certificate in the keychain"; exit 1; }
version=$(awk -F= '/^VERSION=/{print $2; exit}' scripts/build.sh)
repo=fru-dev3/glyph-native
# The shared personal-data scan: scripts/public-scan.sh in a mirror, the repo's own beside this folder.
scan=./scripts/public-scan.sh
[[ -x $scan ]] || { echo "no public-scan.sh"; exit 1; }

echo "building Glyph Native $version"
SIGN_IDENTITY="$identity" ./scripts/build.sh
app="build/Glyph Native.app"
codesign --verify --strict --deep "$app"
sig=$(codesign -dvv "$app" 2>&1)
[[ $sig == *"(runtime)"* ]] || { echo "not signed with the hardened runtime"; exit 1; }
"$scan" "$app" || { echo "personal detail in the app: nothing was uploaded"; exit 1; }

echo "making the disk image"
rm -rf dist && mkdir -p dist/stage
cp -R "$app" dist/stage/ && ln -s /Applications dist/stage/Applications
dmg=dist/Glyph-Native-$version.dmg
hdiutil create -volname "Glyph Native $version" -srcfolder dist/stage -fs HFS+ -format UDZO -ov "$dmg" -quiet
codesign --sign "$identity" --timestamp "$dmg"

echo "notarizing (a few minutes)"
result=$(xcrun notarytool submit "$dmg" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --timeout 20m)
echo "$result"
if ! grep -q "status: Accepted" <<<"$result"; then
  id=$(awk '/^ *id:/{print $2; exit}' <<<"$result")
  xcrun notarytool log "$id" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
  echo "notarization was not accepted (log above)"; exit 1
fi
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

echo "checking a downloaded copy passes Gatekeeper"
cp "$dmg" dist/check.dmg
xattr -w com.apple.quarantine "0081;00000000;Safari;" dist/check.dmg
spctl --assess --type open --context context:primary-signature -v dist/check.dmg
rm dist/check.dmg
cp "$dmg" dist/Glyph-Native.dmg
"$scan" dist/Glyph-Native.dmg || { echo "personal detail in the final disk image: nothing was uploaded"; exit 1; }

notes="Glyph Native $version: one install for every Glyph app. Signed and notarized; needs macOS 26 on Apple silicon."
if gh release view "v$version" --repo $repo >/dev/null 2>&1; then
  gh release upload "v$version" "$dmg" dist/Glyph-Native.dmg --repo $repo --clobber
else
  gh release create "v$version" "$dmg" dist/Glyph-Native.dmg --repo $repo --title "Glyph Native $version" --notes "${notes:-Glyph Native $version}"
fi
echo "released: https://github.com/$repo/releases/tag/v$version"
