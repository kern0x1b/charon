#!/bin/sh
# run.sh - VideoToolbox's pixel rotation, held to what this Mac's own VTPixelRotationSession does AND to an
# expectation computed from the source pattern alone.
#
#   1. probe.m asks the host for all sixteen cells - four rotations x the two flips, alone and together -
#      and compares each against pixels derived from the source alone. It prints the status
#      VTSessionSetProperty returns and READS THE VALUE BACK, because the property is a CFStringRef
#      (kVTRotation_CW90 / _180 / _CCW90) and an NSNumber is rejected silently.
#   2. probe.m checks its own expectation against a HAND-WRITTEN 180 before Apple is asked, so a wrong
#      expectation cannot hide behind a matching host. The 180 of a 2x4 image whose B channels are
#      1 11 / 21 31 / 41 51 / 61 71 must read it upside down: 71 61 / 51 41 / 31 21 / 11 1.
#   3. two plants must each turn it red: swapping the CW90 and CCW90 mappings, and rejecting the rotation
#      property by setting an NSNumber as the first version of this probe did.
#
# WHAT IT DELIBERATELY DOES NOT CLAIM: anything about odd widths, padded bytesPerRow or a second pixel
# format. This is a 2x4 32BGRA probe with the stride CoreVideo chose (64), and the port's implementation
# will carry the full set or answer kVTParameterErr for what it cannot. Cells for the rest belong here
# before the port claims them.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"

xcrun clang -fobjc-arc -w "$here/probe.m" -framework VideoToolbox -framework CoreVideo \
    -framework CoreMedia -framework Foundation -o "$build/probe" > "$build/cc.log" 2>&1 || {
        echo "COMPILE FAILED:"; cat "$build/cc.log"; exit 1; }

echo "--- the host, against an expectation computed from the source alone"
"$build/probe"
status=$?
echo "probe exit: $status"

survived=0
plant() {
    label=$1; from=$2; to=$3
    if ! python3 - "$here/probe.m" "$build/mutant.m" "$from" "$to" <<'PY'
import sys
source, target, needle, replacement = sys.argv[1:5]
text = open(source, encoding="utf-8").read()
if needle not in text:
    sys.exit(1)
open(target, "w", encoding="utf-8").write(text.replace(needle, replacement, 1))
PY
    then
        echo "MUTATION DID NOT APPLY: $label"
        survived=$((survived + 1))
        return
    fi
    if xcrun clang -fobjc-arc -w "$build/mutant.m" -framework VideoToolbox -framework CoreVideo \
        -framework CoreMedia -framework Foundation -o "$build/mutant-bin" > "$build/mutant-cc.log" 2>&1; then
        if "$build/mutant-bin" > "$build/mutant.out" 2>&1; then
            echo "MUTANT SURVIVED: $label"
            survived=$((survived + 1))
        else
            echo "  caught: $(grep -m1 "^CELLS" "$build/mutant.out")$(grep -m1 "^DIFF" "$build/mutant.out" | cut -c1-72)"
        fi
    else
        echo "MUTANT DID NOT BUILD, which is not the same as being noticed: $label"
        survived=$((survived + 1))
    fi
}

echo "--- the plants"
plant "the CW90 and CCW90 mappings swapped" \
    'if (CFEqual(rotation, kVTRotation_CW90))       { sx = py;                sy = SRC_HEIGHT - 1 - px; }' \
    'if (CFEqual(rotation, kVTRotation_CW90))       { sx = SRC_WIDTH - 1 - py; sy = px; }'
plant "the rotation property set with an NSNumber, as the first probe did" \
    'VTSessionSetProperty(session, kVTPixelRotationPropertyKey_Rotation,
                                                     cells[index].rotation)' \
    'VTSessionSetProperty(session, kVTPixelRotationPropertyKey_Rotation,
                                                     (__bridge CFNumberRef)@(0))'

if [ "$survived" -ne 0 ]; then echo "$survived plants survived; this check proves nothing"; exit 1; fi
echo "videotoolbox-pixelrotation: OK - 16 cells agree with the host and with the hand-written 180;"
echo "  the rotation property is a CFStringRef and is read back; 2 plants caught"
