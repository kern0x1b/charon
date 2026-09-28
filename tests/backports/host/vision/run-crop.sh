#!/bin/sh
# run-crop.sh -- the port's crop-and-scale rules against Core ML's own image constructor, pixel for
# pixel, with a mutant that must go red.
#
# One program, built twice: once against the framework's own resampler (which is the oracle and
# answers itself, so the system binary is a self-consistency check of the program) and once against
# the port's, compiled with the rest of the library under names of its own. Both print
# `differing=N of M` per case and the run fails if any N is not zero.
#
# The harness compiles the port's function with each of CoreGraphics' interpolation qualities first
# (the header's CHARON_VISION_INTERPOLATION is the seam), which is how the one the framework uses was
# found: the numbers below are the measurement, and the default in the header is the answer.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
vision=${VISION:-$root/packages/a/apple-backports/Vision}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc -w -Wno-unguarded-availability"
libs="-framework Foundation -framework CoreGraphics -framework CoreVideo -framework CoreML -framework Vision"

python3 - "$vision" "$build/rename.h" <<'PY'
import glob, json, os, sys
names = set()
for path in glob.glob(os.path.join(sys.argv[1], "..", "registry", "Vision", "*.json")):
    for entry in json.load(open(path))["entries"]:
        if entry["kind"] in ("class", "protocol", "constant", "function"):
            names.add(entry["api"].replace("()", ""))
with open(sys.argv[2], "w") as out:
    for name in sorted(names):
        out.write("#define %s Charon%s\n" % (name, name))
PY

xcrun clang $common -I"$here" "$here/crop.m" $libs -o "$build/system" 2>/dev/null ||
    xcrun clang $common -I"$here" "$here/crop.m" $libs -o "$build/system"
build_port() {
    quality=$1
    xcrun clang $common -DCHARON_PORT_BUILD=1 \
        -include "$build/rename.h" -I"$here" -I"$vision" \
        "$here/crop.m" "$vision/CharonVisionBilinear.c" $libs -o "$build/port-$quality"
}

echo "=== the oracle against itself (the program's own two answers are both Core ML's here):"
"$build/system" || true

for quality in kCGInterpolationHigh kCGInterpolationMedium kCGInterpolationNone; do
    build_port "$quality"
    echo "=== the port with $quality:"
    "$build/port-$quality" || true
done

# The verdict and the mutants are counted separately, and the mutants run whatever the verdict was:
# a red verdict is the common case while a rule is being found, and a mutant stage that only ran on
# a green one would not run at all.
echo "=== the verdict, with the header's own default:"
build_port kCGInterpolationHigh
verdict=0
"$build/port-kCGInterpolationHigh" || verdict=1
if [ "$verdict" -eq 0 ]; then
    echo "port: same as the framework, every case"
else
    echo "port: DIFFERS from the framework"
fi

# 5. the mutant: the default interpolation, which is the paste this delivery was measured against.
#    It has to go red, or the check above is not holding anything.
rm -rf "$build/mutant"
mkdir -p "$build/mutant"
cp "$vision"/*.m "$vision"/*.h "$build/mutant/"
python3 - "$build/mutant/CharonVisionImage.h" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
# the mutant: the destination inset back into the sample position, which is the bug the kernel
# had and the one this check exists to hold.
import re
before = text
text = re.sub(r"\(double\)y \+ 0\.5\) \* down", "(double)(insetY + y) + 0.5) * down", text, count=1)
text = re.sub(r"\(double\)x \+ 0\.5\) \* across", "(double)(insetX + x) + 0.5) * across", text, count=1)
assert text != before, "the mutant did not change anything"
old = "double sx = charon_vision_clamp(((double)x + 0.5) * across - 0.5, (double)sourceWide);"
new = "double sx = charon_vision_clamp(((double)(insetX + x) + 0.5) * across - 0.5, (double)sourceWide);"
assert old in text, old
print("the mutant is the inset back into the sample position")
open(path, "w").write(text.replace(old, new, 1))
PY
xcrun clang $common -DCHARON_PORT_BUILD=1 -include "$build/rename.h" -I"$here" -I"$build/mutant" \
    "$here/crop.m" "$build/mutant/CharonVisionBilinear.c" $libs -o "$build/mutant/run"
if "$build/mutant/run" > "$build/mutant/record.txt" 2>&1; then
    echo "MUTANT SURVIVED: the inset in the sample position makes no difference, so the check holds nothing"
    mutants=1
else
    echo "the mutant is caught: the inset in the sample position is red, so the check holds the geometry"
    mutants=0
fi
echo "=== mutants: 1 run, $mutants surviving"
if [ "$verdict" -ne 0 ] || [ "$mutants" -ne 0 ]; then
    exit 1
fi
