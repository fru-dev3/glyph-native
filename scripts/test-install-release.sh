#!/bin/zsh
# Tests install-release.sh with no network: a made-up app packed in a disk image, laid out the way a
# GitHub release is, installed with --base file://. Nothing touches /Applications.
set -u
here=${0:A:h}
t=$(mktemp -d "${TMPDIR:-/tmp}/glyph-release-test.XXXXXX")
trap 'rm -rf "$t"' EXIT
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi }

# makedmg <version> <out dmg>: Foo.app (id dev.example.foo), ad hoc signed.
makedmg() {
  local v=$1 out=$2 s=$t/src-$1
  rm -rf "$s"; mkdir -p "$s/Foo.app/Contents/MacOS"
  printf '#!/bin/sh\nexit 0\n' > "$s/Foo.app/Contents/MacOS/foo"; chmod +x "$s/Foo.app/Contents/MacOS/foo"
  cat > "$s/Foo.app/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.example.foo</string>
<key>CFBundleExecutable</key><string>foo</string>
<key>CFBundleShortVersionString</key><string>$v</string>
</dict></plist>
PL
  codesign --force --sign - "$s/Foo.app" >/dev/null 2>&1
  hdiutil create -quiet -volname Foo -srcfolder "$s" -format UDZO -ov "$out" >/dev/null
}
rel=$t/base/example/foo/releases/latest/download
mkdir -p $rel $t/apps
inst() { "$here/install-release.sh" --repo example/foo --asset Foo.dmg --bundle "${1:-dev.example.foo}" --apps $t/apps --base file://$t/base "${@:2}"; }
ver() { /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $t/apps/Foo.app/Contents/Info.plist 2>/dev/null; }

makedmg 1.0.0 $rel/Foo.dmg
out=$(inst 2>&1); check "installs and prints the version line" '[[ $out == *"installed Foo 1.0.0" && $(ver) == 1.0.0 ]]'
check "leaves no .new or temp folder behind" '[[ ! -e $t/apps/Foo.app.new && $(ls $t/apps) == Foo.app ]]'

makedmg 2.0.0 $rel/Foo.dmg
out=$(inst 2>&1); check "a second run replaces it cleanly" '[[ $out == *"installed Foo 2.0.0" && $(ver) == 2.0.0 && ! -e $t/apps/Foo.app.new ]]'

rm -rf $t/apps/Foo.app; mkdir -p $t/apps2
out=$(inst dev.example.wrong --apps $t/apps2 2>&1); rc=$?
check "wrong --bundle fails and installs nothing" '(( rc != 0 )) && [[ -z $(ls $t/apps2) && ! -e $t/apps/Foo.app ]]'

out=$(inst dev.example.foo --team FOO123 2>&1); rc=$?
check "--team fails for an app with no team and installs nothing" '(( rc != 0 )) && [[ ! -e $t/apps/Foo.app ]]'

# an install under another name is replaced in place, not duplicated
mkdir -p $t/apps3; cp -R $t/src-2.0.0/Foo.app "$t/apps3/Old Foo.app"
out=$(inst dev.example.foo --apps $t/apps3 2>&1); check "an existing copy under another name is replaced, not duplicated" '[[ $out == *"installed Foo 2.0.0" && $(ls $t/apps3) == "Old Foo.app" ]]'

makedmg 1.0.0 $rel/Foo.dmg; inst >/dev/null 2>&1
echo "not a disk image" > $rel/Foo.dmg
out=$(inst 2>&1); rc=$?
check "a corrupted disk image fails and leaves the previous app intact" '(( rc != 0 )) && [[ $(ver) == 1.0.0 && $(ls $t/apps) == Foo.app ]]'

(( fails == 0 )) && echo "all passed" || { echo "$fails failed"; exit 1; }
