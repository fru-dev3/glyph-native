#!/bin/zsh
# Installs one app from its signed disk image on a public GitHub release (the public Glyph Native's
# way: nothing is built, a stranger has no source checkout). Every step is a plain line the launcher
# streams into its log. Never kills a running app, and never leaves a half-copied one in place.
#   install-release.sh --repo owner/name --asset File.dmg --bundle <bundle id> [--apps <dir>]
#                      [--team <TeamID>] [--base <url prefix>] [--tag <release>]
# --tag: the image is on that named release, not the repo's newest (the apps Glyph Native's repo hosts).
# --team: only an app signed by that developer is accepted, and Gatekeeper must accept it too. There is
# deliberately no way to skip those checks once it is given. --base is for tests (a file:// folder).
set -u
apps=/Applications base=https://github.com repo= asset= bundle= team= tag=
while (( $# )); do
  case $1 in
    --repo) repo=$2; shift 2 ;; --asset) asset=$2; shift 2 ;; --bundle) bundle=$2; shift 2 ;;
    --apps) apps=$2; shift 2 ;; --tag) tag=$2; shift 2 ;; --team) team=$2; shift 2 ;; --base) base=$2; shift 2 ;;
    *) echo "Unknown option $1." >&2; exit 2 ;;
  esac
done
[[ -n $repo && -n $asset && -n $bundle ]] || { echo "Missing --repo, --asset or --bundle." >&2; exit 2; }

fail() { echo "$1" >&2; exit 1; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/glyph-release.XXXXXX") || fail "Couldn't make a temporary folder."
mnt=$tmp/mnt
cleanup() { hdiutil detach -quiet -force "$mnt" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

rel=latest/download; [[ -n $tag ]] && rel=download/$tag
url=$base/$repo/releases/$rel/$asset
echo "Downloading $url"
curl -fsSL -o "$tmp/$asset" "$url" || fail "Couldn't download $asset from $repo."

echo "Opening the disk image"
mkdir "$mnt"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$tmp/$asset" </dev/null >/dev/null 2>&1 \
  || fail "$asset isn't a valid disk image."

src=
for a in "$mnt"/*.app(N); do
  [[ $(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$a/Contents/Info.plist" 2>/dev/null) == $bundle ]] && { src=$a; break; }
done
[[ -n $src ]] || fail "$asset has no app with the id $bundle."
name=${src:t:r}
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$src/Contents/Info.plist" 2>/dev/null || echo "?")
exe=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$src/Contents/Info.plist" 2>/dev/null)

echo "Checking the signature"
codesign --verify --deep --strict "$src" 2>/dev/null || fail "$name's signature is not valid."
if [[ -n $team ]]; then
  spctl --assess --type execute "$src" 2>/dev/null || fail "macOS does not accept $name."
  got=$(codesign -dv "$src" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [[ $got == $team ]] || fail "$name is not signed by the same developer as Glyph Native."
fi

# Never touch an app that is open: the user may be mid-dictation or mid-recording in it.
if [[ -n $(lsappinfo find "bundleid=$bundle" 2>/dev/null) ]] || { [[ -n $exe ]] && pgrep -f "/$name.app/Contents/MacOS/$exe" >/dev/null 2>&1; }; then
  fail "Quit $name first, then try again."
fi

# Replace the copy that is already there under any name (the Jot disk image's app is Jot.app, a
# Mac with it installed as Glyph Jot.app must not end up with two), else use the disk image's name.
dest=$apps/$name.app
for a in "$apps"/*.app(N); do
  [[ $(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$a/Contents/Info.plist" 2>/dev/null) == $bundle ]] && { dest=$a; break; }
done
echo "Copying $name to $apps"
rm -rf "$dest.new"
ditto "$src" "$dest.new" || { rm -rf "$dest.new"; fail "Couldn't copy $name to $apps."; }
if [[ -e $dest ]]; then
  mv "$dest" "$tmp/old.app" || { rm -rf "$dest.new"; fail "Couldn't replace the old $name."; }
fi
if ! mv "$dest.new" "$dest"; then
  [[ -e $tmp/old.app ]] && mv "$tmp/old.app" "$dest"
  rm -rf "$dest.new"
  fail "Couldn't put $name in place; the old one was kept."
fi
echo "installed $name $version"
