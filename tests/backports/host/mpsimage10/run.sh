#!/bin/sh
# run.sh - is this port's image-side MPS the same arithmetic as the system's own?
#
# cases.m is compiled twice and run twice: once against the system's MPS, once against this port's
# classes with the MPS names mapped to Charon names and their selectors prefixed, so the port's
# implementations are reached under names of their own and cannot replace the system's. Every case
# prints the result the kernel wrote, as text, and the two runs are compared against a written-down
# float tolerance rather than bit for bit, because a normalisation accumulates in a different order on
# a GPU than on a CPU. See TOLERANCE below.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mps=${MPS:-$here/../../../../packages/a/apple-backports/MetalPerformanceShaders}
build=${BUILD:-$here/../../../../.agent-work/runs/host/mpsimage10}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-macos13.0 -isysroot $sdk"
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unguarded-availability -Wno-incomplete-implementation -Wno-nullability-completeness -Wno-objc-protocol-method-implementation"
xcrun clang -fobjc-arc $target $quiet "$here/cases.m" \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/system"
"$build/system" > "$build/system.txt" 2> "$build/system.err" || true
echo "system: $(wc -l < "$build/system.txt") lines"

# The names this library carries, each under a name of its own. The list is every class the port
# *defines*, read out of its compiled objects and not the subset a case happens to reach: the host's
# MPS framework defines nearly all of them, so a class left unrenamed is two classes of one name in
# the port's process, and which one a superclass pointer or a message reaches is then decided by load
# order rather than by anything here. The same shape of defect ba5df243 found in NetworkExtension.
rm -rf "$build/plain"
mkdir -p "$build/plain"
for source in "$mps"/*.m; do
    xcrun clang -fobjc-arc -w $target -c "$source" -o "$build/plain/$(basename "$source" .m).o" 2>/dev/null
done
for object in "$build/plain"/*.o; do xcrun nm -g --defined-only "$object"; done \
    | grep -oE '_OBJC_CLASS_\$_[A-Za-z0-9_]+' | sed 's/_OBJC_CLASS_\$_//' | sort -u > "$build/port-defines.txt"
python3 - "$build/port-defines.txt" "$build/rename.h" <<'PY'
import sys
names = [line.strip() for line in open(sys.argv[1]) if line.strip()]
with open(sys.argv[2], 'w') as out:
    for name in names:
        out.write("#define %s Charon%s\n" % (name, name))
print("classes the port defines: %d" % len(names))
PY
echo "renamed: $(grep -c define "$build/rename.h") classes"

# The eleven classes this band carries, named here so the run FAILS if one is missing from the
# objects. Without this the harness would compile, run and compare, and the comparison would be of
# two transcripts in which every case said NOT COMPARED - which the reader below treats as red, but
# which a reader who only looked at the case count would read as a pass.
python3 - "$build/port-defines.txt" <<'PY'
import sys
defined = {line.strip() for line in open(sys.argv[1]) if line.strip()}
wanted = ["MPSImageLaplacian", "MPSTemporaryImage"]
missing = [name for name in wanted if name not in defined]
if missing:
    print("the port's objects do not define: %s" % ", ".join(missing))
    raise SystemExit(1)
print("the port's objects define all %d classes this harness compares" % len(wanted))
PY

printf '#import <MetalPerformanceShaders/MetalPerformanceShaders.h>\n#import "CharonMPSImage.h"\n#import <objc/runtime.h>\n#include <stdio.h>\n' > "$build/declarations.h"
objects=""
for source in "$mps"/*.m; do
    name=$(basename "$source" .m)
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -c "$source" -o "$build/$name.plain.o"
    python3 "$here/../prefix_selectors.py" "$source" "$build/$name.m" ccharonHost_ \
        --declarations="$build/declarations.h" -fobjc-arc $target $quiet -I"$mps" -include "$build/rename.h" -- "$build/$name.plain.o"
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -I"$mps" -include "$build/rename.h" \
        -include "$build/declarations.h" -c "$build/$name.m" -o "$build/$name.o"
    objects="$objects $build/$name.o"
done
echo "compiled: $(echo "$objects" | wc -w) objects"

# -DCHARON_PORT_BUILD: this is the port's own build, and the guard below is a statement about it. The
# system build has no rename header and no port classes, and there is nothing for the guard to ask of
# it.
xcrun clang -fobjc-arc $target $quiet -DCHARON_PORT_BUILD=1 -include "$build/rename.h" "$here/cases.m" $objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/port"
"$build/port" > "$build/port.txt" 2> "$build/port.err" || true

# TOLERANCE, written down before the numbers were compared: a normalisation and an exponential
# accumulate in a different order on the GPU than on the CPU, so the two are not expected to agree to
# the bit. A case passes when every element differs by no more than TOLERANCE, absolute or relative,
# whichever is larger, with TOLERANCE = 1e-4 for a single precision result.
TOLERANCE=1e-4
python3 - "$build/system.txt" "$build/port.txt" "$TOLERANCE" <<'PY'
import sys
system_path, port_path, tolerance = sys.argv[1], sys.argv[2], float(sys.argv[3])
def read(path):
    """The transcript's cases, and the cases that were not compared.

    A line that names a class the port does not have is a case the harness refused to compare, and it
    is a result: the run said so instead of printing an answer. It is collected here and fails the
    comparison below, because a case that did not run is not a case that passed.
    """
    cases, name, values = {}, None, []
    skipped, defaults = [], []
    for line in open(path):
        if line.startswith("image "):
            continue
        # A "*-defaults alpha=..." line prints the property values a fresh kernel carries. That is a
        # measurement and it IS compared - the reader below collects these lines separately - but it
        # carries no count and no values, so it must not be read as a case body. It ended the case
        # being read and then aborted the parse on "could not convert string to float", which is a
        # harness defect and not a result.
        if "NOT COMPARED" in line:
            if name: cases[name] = values
            name, values = None, []
            skipped.append((line.split()[1] if len(line.split()) > 1 else "?", line.strip()))
            continue
        parts0 = line.split()
        if len(parts0) >= 2 and not parts0[1].isdigit() and not line.startswith(" ") \
                and not line.startswith("compared: ") and not line.startswith("device "):
            if name: cases[name] = values
            name, values = None, []
            defaults.append(line.strip())
            continue
        if "defaults" in line or line.startswith("relu-defaults"):
            if name: cases[name] = values
            name, values = None, []
            defaults.append(line.strip())
            continue
        if " NOT COMPARED:" in line:
            if name: cases[name] = values
            name, values = None, []
            parts = line.split()
            skipped.append((parts[1] if len(parts) > 1 else "?", line.strip().split("NOT COMPARED:", 1)[1].strip()))
            continue
        if line.startswith("compared: "):
            if name: cases[name] = values
            name, values = None, []
            continue
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            if name: cases[name] = values
            name, values = parts[0], []
        elif parts and name is not None:
            # A value line is "  ch<k> row<k> v v v": the two labels say which channel and row the
            # values are, and both sides print them, so they are dropped rather than compared - the
            # order they are printed in IS the order the transcript is read in, and the reader below
            # compares element by element in that order.
            tail = parts
            if tail[0].startswith("ch"):
                tail = tail[1:]
            if tail and tail[0].startswith("row"):
                tail = tail[1:]
            values.extend(float(v) for v in tail)
    if name: cases[name] = values
    return cases, skipped, defaults
a, a_skipped, a_defaults = read(system_path)
b, b_skipped, b_defaults = read(port_path)
# A case the PORT refused is expected here and is reported, not failed: MPSImageConversion is not
# carried, which is exactly what its row says, and the case's purpose is to print the SYSTEM's no-op as
# the measurement the row rests on. A case the SYSTEM refused would be a defect in the harness, so that
# is still red.
if a_skipped:
    print("the SYSTEM side refused a case, which is a harness defect:")
    for name, why in a_skipped:
        print("  system: %s: %s" % (name, why))
    raise SystemExit(1)
if b_skipped:
    print("the port refused %d case(s), which its rows say it does not carry:" % len({n for n, _ in b_skipped}))
    for name, why in b_skipped:
        print("  port: %s: %s" % (name, why))
if not a:
    print("the system answered no case at all:", open(system_path).read()[:200])
    raise SystemExit(1)
# The two sides need not reach the same cases, and the difference is EXPECTED only where the port has
# said it does not carry the class. So the difference is checked against that list rather than demanded
# to be empty: any case the system ran and the port did not, which is NOT in the list, is a defect.
NOT_CARRIED = {"conversion-null-info"}
missing = sorted(set(a) - set(b))
extra = sorted(set(b) - set(a))
if extra:
    print("the port reached cases the system did not, which cannot be right: %s" % extra)
    raise SystemExit(1)
if missing != sorted(NOT_CARRIED):
    print("the port did not reach %s, which is not a class its rows say it does not carry" % missing)
    raise SystemExit(1)
print("the port did not reach %s, which is what its rows say it does not carry" % ", ".join(missing))
for name, why in b_skipped:
    print("  port: %s: %s" % (name, why[:90]))
# The fresh-kernel property values are compared as TEXT, which is stricter than a tolerance: the
# release and this port must agree on alpha, beta, delta, p0, pm, ps and the kernel size to the digit,
# because they are the same declaration and a difference would be a different default, not a rounding.
a_named = {line.split()[0]: line for line in a_defaults}
b_named = {line.split()[0]: line for line in b_defaults}
bad = [name for name in a_named if name in b_named and a_named[name] != b_named[name]]
if bad:
    print("the two runs disagree on a fresh kernel's defaults:")
    for name in sorted(bad):
        print("  system: %s" % a_named[name])
        print("  port:   %s" % b_named[name])
    raise SystemExit(1)
shared = sorted(set(a_named) & set(b_named))
only_system = sorted(set(a_named) - set(b_named))
if only_system:
    print("the system measured a kernel the port did not build, which is its row's absence: %s"
          % ", ".join(only_system))
print("defaults: %d line(s) compared, agree exactly as text" % len(shared))
for name in shared:
    print("  %s" % a_named[name])
print("cases: %d compared, %d expected absent, tolerance %g absolute or relative"
      % (len(b), len(missing), tolerance))
bad = 0
# The largest distance each case came to, as a fraction of the tolerance it was allowed, so the
# number the tolerance is compared against is printed rather than implied.
worst = []
for name in sorted(b):
    if len(a[name]) != len(b[name]):
        print("  DIFFERS %-28s element count %d vs %d" % (name, len(a[name]), len(b[name])))
        bad += 1
        continue
    limit = tolerance
    used = 0.0
    for index, (x, y) in enumerate(zip(a[name], b[name])):
        close = abs(x - y) <= limit * max(1.0, abs(x), abs(y))
        used = max(used, abs(x - y) / (limit * max(1.0, abs(x), abs(y))))
        if not close:
            print("  DIFFERS %-28s [%d] system %.9g port %.9g" % (name, index, x, y))
            bad += 1
            break
    worst.append((used, name))
worst.sort(reverse=True)
print("closest to the tolerance, as a fraction of it:")
for used, name in worst[:5]:
    print("  %-28s %.3g" % (name, used))
print("differing cases: %d" % bad)
raise SystemExit(1 if bad else 0)
PY
status=$?
if [ "$status" -ne 0 ]; then
    echo "the port's convolutional MPS differs from the system's own"
    exit 1
fi
echo "port: within the tolerance, case for case"
