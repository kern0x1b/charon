#!/bin/sh
# run.sh — is this port's MPSGraph the same arithmetic as the system's own?
#
# graph-cases.m is compiled twice and run twice: once against the system's MPSGraph, once against this
# port's classes with the MPSGraph names mapped to Charon names and their selectors prefixed, so the
# port's implementations are reached under names of their own and cannot replace the system's. Every
# case prints the bytes of a buffer the case owns, so the two runs are compared exactly.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
graph=${GRAPH:-$here/../../../../packages/a/apple-backports/MetalPerformanceShadersGraph}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-macos13.0 -isysroot $sdk"
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unguarded-availability -Wno-incomplete-implementation -Wno-nullability-completeness -Wno-objc-protocol-method-implementation"
mkdir -p "$build"

xcrun clang -fobjc-arc $target $quiet "$here/graph-cases.m" \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework MetalPerformanceShadersGraph -o "$build/system"
set +e
"$build/system" > "$build/system.raw" 2> "$build/system.err"
status=$?
set -e
# Only the lines the case file marks are cases; the framework's own diagnostics share the stream.
grep -a '^#case ' "$build/system.raw" > "$build/system.txt" || true
echo "system: $(wc -l < "$build/system.txt") lines, exit $status"
[ "$status" -ne 0 ] && echo "system: stopped at: $(tail -1 "$build/system.txt" | cut -c2-71)"

# The names this library carries, each under a name of its own.
python3 - "$graph" "$build/rename.h" <<'PY'
import os, re, sys
names = set()
for entry in sorted(os.listdir(sys.argv[1])):
    if not entry.endswith('.m'):
        continue
    for line in open(os.path.join(sys.argv[1], entry), errors='ignore'):
        m = re.match(r'@implementation\s+(\w+)', line)
        if m and m.group(1).startswith('MPSGraph'):
            names.add(m.group(1))
with open(sys.argv[2], 'w') as out:
    for name in sorted(names):
        out.write("#define %s Charon%s\n" % (name, name))
PY
echo "renamed: $(grep -c define "$build/rename.h") classes"

printf '#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>\n#import "CharonMPSGraph.h"\n' > "$build/declarations.h"
# The plant has to reach the objects, not only the case file. CharonMPSStore in ../MetalPerformanceShaders/
# CharonMPS.h is where CHARON_PLANT is compiled in, and it is on the way out of every element the graph's
# interpreter writes, so a planted build has to be compiled with the flag like any other source: passed on
# the case file's line alone it would arm nothing and both builds would print the same correct bytes.
# Each build gets its own object directory, so a planted object cannot be handed back to the plain run.
build_objects() {
    _plant=$1
    _objdir="$build/obj-p$_plant"
    rm -rf "$_objdir"
    mkdir -p "$_objdir"
    _objects=""
    for source in "$graph"/*.m; do
        _s=$(basename "$source" .m)
        xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -DCHARON_PLANT=$_plant \
            -c "$source" -o "$_objdir/$_s.plain.o"
        python3 "$here/../prefix_selectors.py" "$source" "$_objdir/$_s.m" ccharonHost_ \
            --declarations="$build/declarations.h" -fobjc-arc $target $quiet -DCHARON_PLANT=$_plant \
            -I"$graph" -include "$build/rename.h" -- "$_objdir/$_s.plain.o"
        xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -DCHARON_PLANT=$_plant \
            -I"$graph" -include "$build/rename.h" \
            -include "$build/declarations.h" -c "$_objdir/$_s.m" -o "$_objdir/$_s.o"
        _objects="$_objects $_objdir/$_s.o"
    done
    echo "$_objects"
}
objects=$(build_objects 0)
echo "compiled: $(echo "$objects" | wc -w) objects"

xcrun clang -fobjc-arc $target $quiet -include "$build/rename.h" "$here/graph-cases.m" $objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework MetalPerformanceShadersGraph -o "$build/port"
set +e
"$build/port" > "$build/port.raw" 2> "$build/port.err"
port_status=$?
set -e
grep -a '^#case ' "$build/port.raw" > "$build/port.txt" || true
echo "port: exit $port_status"
[ "$port_status" -ne 0 ] && echo "port: stopped at: $(tail -1 "$build/port.txt" | cut -c2-71)"

# The red control: the same sources with every stored element off by one. It exists because a comparison
# that cannot see a wrong kernel is not a comparison, and this file's own history is the reason - the
# verdict line it printed for a year could not be told apart from a test nobody ran.
plant_objects=$(build_objects 1)
xcrun clang -fobjc-arc $target $quiet -include "$build/rename.h" "$here/graph-cases.m" $plant_objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework MetalPerformanceShadersGraph -o "$build/port-plant1"
set +e
"$build/port-plant1" > "$build/port-plant1.raw" 2> "$build/port-plant1.err"
plant_status=$?
set -e
grep -a '^#case ' "$build/port-plant1.raw" > "$build/port-plant1.txt" || true
echo "port-plant1: exit $plant_status"

n=$(wc -l < "$build/system.txt" | tr -d ' ')
m=$(wc -l < "$build/port.txt" | tr -d ' ')
# One case is known to abort the host of this machine and is asked for last, so the two runs are
# expected to differ by exactly that one. Anything else - the host dying earlier, the port dying, a case
# appearing or vanishing - is a failure, and it names the case either side last reached. The port's extra
# lines must be the case the host cannot answer, and nothing else.
HOST_CANNOT_ANSWER=1
if [ "$m" -ne "$((n + HOST_CANNOT_ANSWER))" ]; then
    echo "the two runs produced different numbers of lines: system $n, port $m, and only $HOST_CANNOT_ANSWER is expected to be extra"
    echo "the last case either side reached:"
    echo "  system: $(tail -1 "$build/system.txt" | cut -d' ' -f2-4)"
    echo "  port:   $(tail -1 "$build/port.txt" | cut -d' ' -f2-4)"
    exit 1
fi
if [ "$n" -eq 0 ]; then
    echo "the host answered no case at all"
    exit 1
fi
head -n "$n" "$build/system.txt" > "$build/system.prefix"
head -n "$n" "$build/port.txt" > "$build/port.prefix"
head -n "$n" "$build/port-plant1.txt" > "$build/port-plant1.prefix"
echo "compared: $n cases"
# The red control, judged against the same oracle rather than trusted: a plant the comparison cannot see
# is a comparison that would pass a wrong port, and this file's verdict line was unreadable to the sweep
# for a year for a reason of the same family.
if cmp -s "$build/port.prefix" "$build/port-plant1.prefix"; then
    echo "the red control did not fire: the planted build printed exactly what the plain build printed"
    exit 1
fi
plant_wrong=$(diff "$build/system.prefix" "$build/port-plant1.prefix" | grep '^<' | wc -l | tr -d ' ')
echo "red control: the planted build differs from the release in $plant_wrong of $n cases"
# The verdict, cell by cell. Every cell of every case is compared, and a difference is a failure unless
# the cell is in recorded-cells.txt WITH the two sets of bytes the release and the port answer there, or
# the two answers of that cell are within the figure tolerances.txt gives for that operation in that data
# type.
#
# Neither file is an allowance. recorded-cells.txt names no data type, no operation and no element count,
# and a cell on it whose bytes are not the two written there fails as surely as one that is not on it at
# all. tolerances.txt names an operation and a data type and a number of units in the last place, and a
# cell outside that number fails; a case not on it is compared byte for byte, which is every case that is
# not one of the transcendentals, so a predicate, a logical, a remainder or a rounding has no tolerance
# at all. What each recorded group is, and the rule attempted and rejected for it, and where each
# tolerance is written down, is in facts/MetalPerformanceShadersGraph/Core.md.
python3 - "$build/system.prefix" "$build/port.prefix" "$here/recorded-cells.txt" "$here/tolerances.txt" <<'PY'
import sys
recorded = {}
for number, line in enumerate(open(sys.argv[3]), 1):
    if line.startswith("#") or not line.strip():
        continue
    fields = line.split()
    if len(fields) != 5:
        print("recorded-cells.txt line %d is not five fields:" % number, line.strip())
        raise SystemExit(1)
    recorded[(fields[0], fields[1], int(fields[2]))] = (fields[3], fields[4])
# How many units in the last place two answers of one data type may differ and still be the same answer,
# per case. Zero everywhere but the transcendental family, and there it is Metal's own documented figure
# for that function, which is the whole of what "the same arithmetic" can mean for a kernel that is not
# the C library's: tolerances.txt carries the number and where it is written down.
tolerances = {}
for number, line in enumerate(open(sys.argv[4]), 1):
    if line.startswith("#") or not line.strip():
        continue
    fields = line.split()
    if len(fields) != 3:
        print("tolerances.txt line %d is not three fields:" % number, line.strip())
        raise SystemExit(1)
    tolerances[(fields[0], fields[1])] = int(fields[2])

# The distance between two answers of a floating point type, in units in the last place: the bit patterns
# read as signed integers of the same sign-magnitude order, so the distance is how many representable
# values lie between them. A zero of either sign is the same value and the distance is zero; two NaNs are
# the same answer whatever their payloads; a NaN against a number is no distance at all and fails.
def value_of(pattern):
    # The bytes are written in the order the buffer holds them and an x86 buffer is little-endian, so the
    # number is those bytes the other way round.
    return int(bytes.fromhex(pattern)[::-1].hex(), 16)

def monotone(pattern):
    # How many representable values lie between two answers: the bit patterns read as signed integers in
    # sign-magnitude order, so +0 is 0, every positive value is its own pattern and every negative one is
    # the negation of its magnitude, and the distance is the difference of those.
    value = value_of(pattern)
    sign, magnitude = value >> (len(pattern) * 4 - 1), value & ((1 << (len(pattern) * 4 - 1)) - 1)
    return -magnitude if sign else magnitude

def is_nan(pattern):
    # The exponent all ones and the mantissa not zero, read off the number and not off the printed bytes.
    value = value_of(pattern)
    if len(pattern) == 4:
        return value & 0x7C00 == 0x7C00 and value & 0x03FF != 0
    return value & 0x7F800000 == 0x7F800000 and value & 0x007FFFFF != 0

def is_zero(pattern):
    return value_of(pattern) & ((1 << (len(pattern) * 4 - 1)) - 1) == 0

def distance(one, other, width):
    if is_nan(one) and is_nan(other):
        return 0
    if is_nan(one) or is_nan(other):
        return None
    # A zero of either sign is the same value, as IEEE has it: a kernel that answers +0 where the port
    # answers -0 is not off by an ulp and not off by half of one.
    if is_zero(one) and is_zero(other):
        return 0
    return abs(monotone(one) - monotone(other))

hard, seen, differing, checked, cells = [], set(), set(), 0, 0
for one, other in zip(open(sys.argv[1]), open(sys.argv[2])):
    a, b = one.split(), other.split()
    # Five fields is a case with a result buffer in it: the marker, the operation, the data type, the
    # length and the bytes. Anything shorter is a line of its own - the graph device type, a shaped type
    # data type - and it is compared as the whole line it is.
    if len(a) < 5 or len(b) < 5 or a[1] != b[1]:
        if one != other:
            hard.append(" ".join(a))
        continue
    checked += 1
    # How many hex characters one element of this data type is: two per byte, and the bytes of the
    # types this file asks for. A predicate's result is a boolean - MPSSizeofMPSDataType(MPSDataTypeBool)
    # is 1, measured - and the case names carry that as "bool-from-<the operand's type>", so a boolean
    # cell is one byte and is compared like any other.
    # The width is in hex characters, because the bytes are written in the order the buffer holds them and
    # that is the order this reads. A float32 is 8 of them, a float16 four, an int32 eight, a boolean two.
    width = {"float32": 8, "float16": 4, "int32": 8}.get(a[2], 2 if a[2].startswith("bool") else 8)
    count = int(a[3]) * 2 // width
    cells += count
    allowed = tolerances.get((a[1], a[2]), 0)
    for i in range(count):
        key = (a[1], a[2], i)
        release = a[4][i * width:(i + 1) * width]
        mine = b[4][i * width:(i + 1) * width]
        want = (release, mine)
        listed = recorded.get(key)
        if want[0] == want[1]:
            if listed is not None:
                hard.append("%s %s element %d is on recorded-cells.txt and the two now agree" % key)
            continue
        # A boolean or an integer answer has no tolerance: it is one bit of truth or a whole number, and
        # "within N units in the last place" is not a thing for either. So the tolerance is read only for
        # the two floating point types, and a case of another type that differs is a failure.
        if allowed and a[2] in ("float32", "float16"):
            how_far = distance(release, mine, width)
            if how_far is not None and how_far <= allowed:
                continue
        differing.add(key)
        if listed is None:
            hard.append("%s %s element %d: release %s, port %s, and it is neither within %d ulp nor recorded"
                        % (key[0], key[1], key[2], want[0], want[1], allowed))
        elif listed != want:
            hard.append("%s %s element %d is recorded as release %s and port %s and answered %s and %s"
                        % (key[0], key[1], key[2], listed[0], listed[1], want[0], want[1]))
        else:
            seen.add(key)
for key, value in sorted(recorded.items()):
    if key not in differing:
        hard.append("%s %s element %d is recorded as release %s and port %s and the two now agree"
                    % (key[0], key[1], key[2], value[0], value[1]))
print("port: same as the system on %d of the %d cells with a result buffer; %d within the release's own "
      "precision, %d recorded" % (cells - len(seen), cells, cells - len(seen) - len(differing), len(seen)))
for name in hard:
    print("  DIFFERS:", name)
print("checks=%d failures=%d recorded=%d" % (checked, len(hard), len(seen)))
raise SystemExit(1 if hard else 0)
PY
verdict=$?
if [ "$verdict" -ne 0 ]; then
    exit 1
fi
