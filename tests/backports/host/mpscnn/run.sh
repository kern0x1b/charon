#!/bin/sh
# run.sh — is this port's convolutional MPS the same arithmetic as the system's own?
#
# cnn-cases.m is compiled twice and run twice: once against the system's MPS, once against this port's
# classes with the MPS names mapped to Charon names and their selectors prefixed, so the port's
# implementations are reached under names of their own and cannot replace the system's. Every case
# prints the result the kernel wrote, as text, and the two runs are compared against a written-down
# float tolerance rather than bit for bit, because a convolution accumulates in a different order on a
# GPU than on a CPU. See TOLERANCE below.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mps=${MPS:-$here/../../../../packages/a/apple-backports/MetalPerformanceShaders}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-macos13.0 -isysroot $sdk"
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unguarded-availability -Wno-incomplete-implementation -Wno-nullability-completeness -Wno-objc-protocol-method-implementation"
mkdir -p "$build"

xcrun clang -fobjc-arc $target $quiet "$here/cnn-cases.m" \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/system"
"$build/system" > "$build/system.txt" 2> "$build/system.err" || true
echo "system: $(wc -l < "$build/system.txt") lines"

# The names this library carries, each under a name of its own: every class its sources implement that
# this file's cases reach.
python3 - "$mps" "$build/rename.h" <<'PY'
import os, re, sys
names = set()
for entry in sorted(os.listdir(sys.argv[1])):
    if not entry.endswith('.m'):
        continue
    for line in open(os.path.join(sys.argv[1], entry), errors='ignore'):
        m = re.match(r'@implementation\s+(MPSCNN\w+)', line)
        if m:
            names.add(m.group(1))
with open(sys.argv[2], 'w') as out:
    for name in sorted(names):
        out.write("#define %s Charon%s\n" % (name, name))
PY
echo "renamed: $(grep -c define "$build/rename.h") classes"

printf '#import <MetalPerformanceShaders/MetalPerformanceShaders.h>\n#import "CharonMPSCnn.h"\n' > "$build/declarations.h"
objects=""
for source in "$mps"/MPSCNN*.m; do
    name=$(basename "$source" .m)
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -c "$source" -o "$build/$name.plain.o"
    python3 "$here/../prefix_selectors.py" "$source" "$build/$name.m" ccharonHost_ \
        --declarations="$build/declarations.h" -fobjc-arc $target $quiet -I"$mps" -include "$build/rename.h" -- "$build/$name.plain.o"
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -I"$mps" -include "$build/rename.h" \
        -include "$build/declarations.h" -c "$build/$name.m" -o "$build/$name.o"
    objects="$objects $build/$name.o"
done
echo "compiled: $(echo "$objects" | wc -w) objects"

xcrun clang -fobjc-arc $target $quiet -include "$build/rename.h" "$here/cnn-cases.m" $objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/port"
"$build/port" > "$build/port.txt" 2> "$build/port.err" || true

# TOLERANCE, written down before the numbers were compared: a convolution and a normalisation
# accumulate in a different order on the GPU than on the CPU, so the two are not expected to agree to
# the bit. A case passes when every element differs by no more than TOLERANCE, absolute or relative,
# whichever is larger, with TOLERANCE = 1e-4 for a single precision result. Pooling, which sums at
# most nine values with no division of magnitudes, is compared exactly: its cases are named
# "exact" below and must agree bit for bit.
TOLERANCE=1e-4
python3 - "$build/system.txt" "$build/port.txt" "$TOLERANCE" <<'PY'
import sys
system_path, port_path, tolerance = sys.argv[1], sys.argv[2], float(sys.argv[3])
def read(path):
    cases, name, values = {}, None, []
    for line in open(path):
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            if name: cases[name] = values
            name, values = parts[0], []
        elif parts:
            values.extend(float(v) for v in parts)
    if name: cases[name] = values
    return cases
a, b = read(system_path), read(port_path)
if not a:
    print("the system answered no case at all:", open(system_path).read()[:200], open(system_path + ".err").read()[:200] if __import__('os').path.exists(system_path + ".err") else "")
    raise SystemExit(1)
if sorted(a) != sorted(b):
    print("the two runs reached different cases: system %s, port %s" % (sorted(a), sorted(b)))
    raise SystemExit(1)
print("cases: %d, tolerance %g absolute or relative" % (len(a), tolerance))
bad = 0
for name in sorted(a):
    exact = name.startswith("pooling-")
    limit = 0.0 if exact else tolerance
    for index, (x, y) in enumerate(zip(a[name], b[name])):
        if limit == 0.0:
            close = x == y
        else:
            close = abs(x - y) <= limit * max(1.0, abs(x), abs(y))
        if not close:
            print("  DIFFERS %-28s [%d] system %.9g port %.9g" % (name, index, x, y))
            bad += 1
            break
print("differing cases: %d" % bad)
raise SystemExit(1 if bad else 0)
PY
echo "port: within the tolerance, case for case"
