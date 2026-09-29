#!/bin/sh
# run.sh — a host differential for SensorKit's four time functions.
#
# The host has a real SensorKit and the four functions work there; the port's are over the two clocks
# this release has. Their NUMBERS cannot be compared - the two anchors are different by construction -
# so what is compared is the three relations the header states: the round trip is exact, the pair names
# the same instant as CFAbsoluteTimeGetCurrent, and two readings increase. The port's half is the port's
# own file with its four functions renamed, so one binary carries both.
#
# There is no differential for SRSensorReader and this file is the reason: under Mac Catalyst the class
# is declared and implements nothing - respondsToSelector: is 0 for +authorizationStatus and +sharedReader
# and sending either raises - so the reader's answers stand on the header alone (facts/SensorKit).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
appledir=${APPLEDIR:-$here/../../../../packages/a/apple-backports}
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path --sdk macosx)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc -w"
libs="-framework Foundation -framework CoreFoundation -framework SensorKit"

xcrun clang $common -I"$here" "$here/record.m" "$here/cases.m" $libs -o "$build/system"
SENSORKIT_RECORDS="$build/system.json" "$build/system"
echo "records: $(python3 -c "import json; print(len(json.load(open('$build/system.json'))))")"

python3 "$here/rename.py" "$appledir/registry/SensorKit/ios14.json" "$build/rename.h"
port() {
    dir=$1
    xcrun clang $common -DCHARON_SENSORKIT_PORT=1 -include "$build/rename.h" -I"$here" -I"$appledir/SensorKit" \
        "$here/record.m" "$here/cases.m" "$dir/SRAbsoluteTime.m" "$dir/NSDate+SensorKit14.m" $libs -o "$dir/run"
}
rm -rf "$build/port"; mkdir -p "$build/port"
cp "$appledir/SensorKit/SRAbsoluteTime.m" "$build/port/"
cp "$appledir/SensorKit/NSDate+SensorKit14.m" "$build/port/"
port "$build/port"
SENSORKIT_RECORDS="$build/port.json" "$build/port/run"
python3 "$here/compare.py" "$build/system.json" "$build/port.json"

survived=0
mutant() {
    # the file to mutate is the fourth argument and defaults to the time functions, because a plant that
    # points at the category's own file and is applied to the time functions is not a mutation at all -
    # which is what the first version of the category's plant did, and mutate.py said so by refusing.
    label=$1; from=$2; to=$3; which=${4:-SRAbsoluteTime.m}
    rm -rf "$build/mutant"; mkdir -p "$build/mutant"
    cp "$appledir/SensorKit/SRAbsoluteTime.m" "$build/mutant/"
    cp "$appledir/SensorKit/NSDate+SensorKit14.m" "$build/mutant/"
    if ! python3 "$here/mutate.py" "$build/mutant/$which" "$from" "$to" >/dev/null; then
        echo "MUTATION DID NOT APPLY: $label"; survived=$((survived + 1)); return
    fi
    port "$build/mutant"
    rm -f "$build/mutant.json"
    SENSORKIT_RECORDS="$build/mutant.json" timeout 90 "$build/mutant/run" >/dev/null 2>&1 || true
    if cmp -s "$build/port.json" "$build/mutant.json"; then echo "MUTANT SURVIVED: $label"; survived=$((survived + 1)); else
        for key in $(python3 -c "
import json
a = json.load(open('$build/port.json')); b = json.load(open('$build/mutant.json'))
print(' '.join(k for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)))"); do
            echo "  caught by $key: $(python3 -c "import json;print(json.load(open('$build/port.json')).get('$key'))") -> $(python3 -c "import json;print(json.load(open('$build/mutant.json')).get('$key'))")"
        done
    fi
}
mutant "the round trip loses a second" "    return (SRAbsoluteTime)(anchor->absolute + (cf - anchor->absolute));" "    return (SRAbsoluteTime)(anchor->absolute + (cf - anchor->absolute) + 1.0);"
mutant "the category's round trip gains a millisecond" \
    "    return SRAbsoluteTimeFromCFAbsoluteTime((CFAbsoluteTime)self.timeIntervalSinceReferenceDate);" \
    "    return SRAbsoluteTimeFromCFAbsoluteTime((CFAbsoluteTime)self.timeIntervalSinceReferenceDate) + 0.001;" \
    "NSDate+SensorKit14.m"
mutant "the reading does not advance" "    NSTimeInterval elapsed = CharonSensorKitSecondsFromTicks(mach_absolute_time() - anchor->continuous);" "    NSTimeInterval elapsed = 0.0;"
if [ "$survived" -ne 0 ]; then echo "$survived mutations survived; the differential is not holding"; exit 1; fi
echo "mutations: all caught"
