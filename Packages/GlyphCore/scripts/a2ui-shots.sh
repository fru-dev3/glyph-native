#!/bin/zsh
# a2ui-shots.sh <out dir> [simulator name]: pictures of the A2UI renderer's five fixtures, dark, on an iPhone
# simulator (inside the family chat) and on the Mac (the surface alone). Builds Harness/A2UIDemo under the build
# lock, then pictures under the screen lock: one lock at a time, never one while waiting for the other, and only
# its own removed. The build output goes in <out dir>/dd and is deleted at the end.
set -uo pipefail
out=${1:?out dir}; simname=${2:-Glyph Review}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
here=${0:A:h}/../Harness/A2UIDemo
B=/tmp/glyph-build.lock.d U=/tmp/glyph-mac-ui.lock.d mine=
take() { for _ in $(seq 1440); do mkdir $1 2>/dev/null && { echo "a2ui $$" > $1/holder; mine=$1; return 0; }; sleep 5; done; echo "no lock $1"; exit 75; }
give() { [[ -n $mine ]] && rm -rf $mine; mine=; }
trap 'give' EXIT; trap 'exit 143' TERM; trap 'exit 130' INT
mkdir -p $out; dd=$out/dd
names=(time-picker place renewals spending todos)

take $B
(cd $here && xcodegen generate --quiet)
for t in A2UIDemoPhone A2UIDemoMac; do
  dest=$([[ $t == *Phone ]] && echo "generic/platform=iOS Simulator" || echo "platform=macOS")
  xcodebuild -project $here/A2UIDemo.xcodeproj -scheme $t -destination "$dest" -derivedDataPath $dd build > $out/build-$t.log 2>&1 \
    || { echo "build failed: $t (see $out/build-$t.log)"; grep -E "error:" $out/build-$t.log | head; exit 1; }
done
give

take $U
sim=$(xcrun simctl list devices available | grep "$simname (" | head -1 | grep -oE '[0-9A-F-]{36}')
[[ -n $sim ]] || { echo "no simulator named $simname"; exit 1; }
was=$(xcrun simctl list devices | grep $sim | grep -c Booted)
xcrun simctl boot $sim 2>/dev/null; xcrun simctl bootstatus $sim > /dev/null
xcrun simctl ui $sim appearance dark
app=$(ls -d $dd/Build/Products/Debug-iphonesimulator/A2UIDemoPhone.app)
xcrun simctl install $sim $app
xcrun simctl status_bar $sim override --time 9:41 --batteryState charged --batteryLevel 100 2>/dev/null
for n in $names; do
  SIMCTL_CHILD_A2UI_FIXTURE=$n xcrun simctl launch --terminate-running-process $sim dev.fru.a2ui-demo > /dev/null
  sleep 7
  xcrun simctl io $sim screenshot $out/iphone-$n.png > /dev/null 2>&1
done
# The Place card's button in its sent states (A2UI_SENT): spinning, answered, and a failed send.
for how in sending answered failed; do
  SIMCTL_CHILD_A2UI_FIXTURE=place SIMCTL_CHILD_A2UI_SENT=$how xcrun simctl launch --terminate-running-process $sim dev.fru.a2ui-demo > /dev/null
  sleep 7
  xcrun simctl io $sim screenshot $out/iphone-place-$how.png > /dev/null 2>&1
done
xcrun simctl terminate $sim dev.fru.a2ui-demo 2>/dev/null
xcrun simctl uninstall $sim dev.fru.a2ui-demo
xcrun simctl status_bar $sim clear 2>/dev/null
[[ $was == 0 ]] && xcrun simctl shutdown $sim
A2UI_SHOTS=$out $dd/Build/Products/Debug/A2UIDemoMac.app/Contents/MacOS/A2UIDemoMac > $out/mac.log 2>&1
give
rm -rf $dd $here/A2UIDemo.xcodeproj
ls $out/*.png
