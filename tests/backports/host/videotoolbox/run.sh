#!/bin/sh
# THIS SUITE COMPARES THE 135 STRING CONSTANTS. The sibling vtclass/run.sh compares the CLASSES - the class, its conformance, and where each accessor lives. Two suites, two questions, and both are needed: a constant is a value and a class is a shape.
# run.sh — a host differential for VideoToolbox's 135 string constants, one check per constant.
#
# The host's VideoToolbox exports all 135 and implements them, so its value is the value. The port's
# file is compiled into the same binary with its names renamed, and compare.py requires the two to agree
# character for character. This is the check the values were measured with and the check that would
# catch a value written from a rule.
#
# The release is not the oracle and cannot be: its 6.1.3 armv7 cache was copied from a running
# device and 3709 of its pages hold slid pointers, which is why tools/cfconst.py cannot read it, and
# the host's own cache is a 753KB stub. See facts/VideoToolbox/VideoToolbox.md.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
appledir=${APPLEDIR:-$here/../../../../packages/a/apple-backports}
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path --sdk macosx)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc -w"
libs="-framework Foundation -framework CoreMedia -framework VideoToolbox"

xcrun clang $common -I"$here" "$here/record.m" "$here/cases.m" $libs -o "$build/system"
VIDEOTOOLBOX_RECORDS="$build/system.json" "$build/system"
echo "the host answered: $(python3 -c "import json; print(len(json.load(open('$build/system.json'))))")"

python3 "$here/rename.py" "$build/rename.h" "$here/names.txt"
xcrun clang $common -DCHARON_VIDEOTOOLBOX_PORT=1 -include "$build/rename.h" -I"$here" -I"$appledir/VideoToolbox" \
    "$here/record.m" "$here/cases.m" "$appledir/VideoToolbox/VideoToolboxConstants26.m" $libs -o "$build/port"
VIDEOTOOLBOX_RECORDS="$build/port.json" "$build/port"
python3 "$here/compare.py" "$build/system.json" "$build/port.json"

# a mutation of the port's file must change a record: one value made into the constant's own name,
# which is the mistake this whole family is measured against
survived=0
mutant() {
    label=$1; from=$2; to=$3
    rm -rf "$build/mutant"; mkdir -p "$build/mutant"
    cp "$appledir/VideoToolbox/VideoToolboxConstants26.m" "$build/mutant/"
    if ! python3 "$here/mutate.py" "$build/mutant/VideoToolboxConstants26.m" "$from" "$to" >/dev/null; then
        echo "MUTATION DID NOT APPLY: $label"; survived=$((survived + 1)); return
    fi
    xcrun clang $common -DCHARON_VIDEOTOOLBOX_PORT=1 -include "$build/rename.h" -I"$here" -I"$build/mutant" \
        "$here/record.m" "$here/cases.m" "$build/mutant/VideoToolboxConstants26.m" $libs -o "$build/mutant/run"
    rm -f "$build/mutant.json"
    VIDEOTOOLBOX_RECORDS="$build/mutant.json" timeout 90 "$build/mutant/run" >/dev/null 2>&1 || true
    if cmp -s "$build/port.json" "$build/mutant.json"; then
        echo "MUTANT SURVIVED: $label"; survived=$((survived + 1))
    else
        python3 -c "
import json
a = json.load(open('$build/port.json')); b = json.load(open('$build/mutant.json'))
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k): print('  caught: %-58s [%s] -> [%s]' % (k, a.get(k), b.get(k)))"
    fi
}
mutant "one value becomes the constant's own name" \
    "CFSTR(\"PremultipliedAlpha\");" \
    "CFSTR(\"kVTAlphaChannelMode_PremultipliedAlpha\");"
if [ "$survived" -ne 0 ]; then echo "$survived mutations survived"; exit 1; fi
echo "mutations: all caught"
