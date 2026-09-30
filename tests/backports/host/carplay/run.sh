#!/bin/sh
# What Apple's own CarPlay answers with NO head unit attached -- the differential for the seven
# classes `registry/CarPlay/ios12.json` carries as `absent`.
#
# Why a Mac Catalyst binary: it is the only place on this machine where Apple's CarPlay loads. The
# fleet devices run 6.1.3, which has no CarPlay class of any name (apple.objc.inventory over the
# armv7 cache), and `/System/Library/Frameworks` has no CarPlay outside the SDK, so a host probe
# against the system frameworks cannot ask the question at all.
#
# What it is for: the seven classes split into two worlds and only a measurement tells them apart. A
# row whose API Apple carries is a measurement -- what the SDK answers with no head unit -- and this
# prints it. A row that IS the framework's own gate (a scene, a session configuration the connected
# system fills in) is a hardware absence, and this measures the hardware side of that: the class is
# there, and what answers is nothing.
#
# The run FAILS if a check does not hold, and FAILS if the mutant does not differ, because a green
# mutant is a comparison that decides nothing. Run output lands under this repository's own
# .agent-work, never the system temp: the transcript is the evidence the registry's `source` names.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=${CARPLAY_BUILD:-$PWD/.agent-work/runs/carplay-host}
mkdir -p "$build"
rm -f "$build"/cc.log "$build"/probe "$build"/probe.log "$build"/mutant "$build"/mutant.log \
      "$build"/mutated.m

MACOSX_SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="-target arm64-apple-ios17.0-macabi -isysroot $MACOSX_SDK"
FRAMEWORKS="-F $MACOSX_SDK/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit -framework CarPlay"

build_probe() {
    out=$1
    source=$2
    xcrun clang -fobjc-arc -Wall $TARGET $FRAMEWORKS "$source" -o "$out" 2> "$build/cc.log" || {
        grep -m5 ': error:' "$build/cc.log" || true
        exit 1
    }
}

# The real run.
build_probe "$build/probe" "$here/headunit-probe.m"
"$build/probe" > "$build/probe.log" 2>&1 && real_status=0 || real_status=$?
cat "$build/probe.log"

# The mutant: the SAME source with one expectation inverted -- the voice control template's five
# state limit read as six. A header that stopped limiting would answer six, and this is the check
# that would notice, so the plant has to make the run red. mutate.py is not used here because the
# probe is one file: the substitution is asserted below before the build, so a renamed line fails
# the run instead of producing a mutant that is quietly identical to the real run.
sed 's/\[voice.voiceControlStates count\] == 5/[voice.voiceControlStates count] == 6/' \
    "$here/headunit-probe.m" > "$build/mutated.m"
if cmp -s "$build/mutated.m" "$here/headunit-probe.m"; then
    echo "MUTANT: the line the plant changes is not in the probe, so the mutant is identical" >&2
    exit 1
fi
build_probe "$build/mutant" "$build/mutated.m"
"$build/mutant" > "$build/mutant.log" 2>&1 && mutant_status=0 || mutant_status=$?

echo
echo "real exit=$real_status mutant exit=$mutant_status"
if [ "$real_status" -ne 0 ]; then
    echo "FAIL: the real run did not pass every check" >&2
    exit 1
fi
if [ "$mutant_status" -eq 0 ]; then
    echo "FAIL: the mutant passed, so this probe cannot fail and proves nothing" >&2
    exit 1
fi
echo "ok: the probe fails on a broken expectation and passes on the real one"
