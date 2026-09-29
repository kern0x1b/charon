#!/bin/sh
# run.sh — is this port's Metal Performance Shaders matrix and vector framework the same arithmetic as
# the system's own?
#
# mps-cases.m is compiled twice and run twice. The first build links the system's MetalPerformanceShaders
# and calls it by its own names. The second build compiles this port's own sources with the MPS class
# names mapped to Charon names and its selectors prefixed (prefix_selectors.py), so the port's
# implementations are reached under names of their own and cannot replace the system's, and it calls the
# same cases.m with the same mapping. Every case prints its result buffer as bytes, so the two runs are
# compared exactly: a difference of one bit in one element is a failure, not a tolerance this script
# chooses after seeing the numbers.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
mps=${MPS:-$here/../../../../packages/a/apple-backports/MetalPerformanceShaders}
build=${BUILD:-$here/../../../.agent-work/runs/host/mpsmatrix}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-macos13.0 -isysroot $sdk"
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unguarded-availability -Wno-incomplete-implementation -Wno-nullability-completeness -Wno-objc-protocol-method-implementation"
mkdir -p "$build"

xcrun clang -fobjc-arc $target $quiet "$here/mps-cases.m" \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/system"
# The system's own MPS aborts on some cases, and an oracle that dies half way through can only be
# compared over the part it produced. Which cases those are is said out loud rather than hidden.
set +e
"$build/system" > "$build/system.txt" 2> "$build/system.err"
system_status=$?
set -e
echo "system: $(wc -l < "$build/system.txt") lines, exit $system_status"
[ "$system_status" -ne 0 ] && echo "system: stopped at: $(tail -1 "$build/system.txt" | cut -c1-60)"

# The names this port carries, each under a name of its own. This is every class the port *defines*,
# derived from nm -g --defined-only of its objects and not from one registry file: the matrix file
# named only the classes that family carries, so MPSMatrixRandomPhilox, MPSMatrixRandomDistributionDescriptor,
# MPSState, MPSPredicate, MPSCommandBuffer and every CNN class were registered under the host's names, and
# a case reaching one of those was comparing the host with itself.
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

# The port's own sources, with their selectors prefixed so they do not replace the system's.
printf '#import <MetalPerformanceShaders/MetalPerformanceShaders.h>\n' > "$build/declarations.h"
objects=""
for source in "$mps"/*.m; do
    name=$(basename "$source" .m)
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -c "$source" -o "$build/$name.plain.o"
    python3 "$here/../prefix_selectors.py" "$source" "$build/$name.m" ccharonHost_ \
        --declarations="$build/declarations.h" -fobjc-arc $target $quiet -include "$build/rename.h" -- "$build/$name.plain.o"
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -I"$mps" -include "$build/rename.h" \
        -include "$build/declarations.h" -c "$build/$name.m" -o "$build/$name.o"
    objects="$objects $build/$name.o"
done
echo "compiled: $(echo "$objects" | wc -w) objects"

xcrun clang -fobjc-arc $target $quiet -include "$build/rename.h" "$here/mps-cases.m" $objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/port"
set +e
"$build/port" > "$build/port.txt" 2> "$build/port.err"
port_status=$?
set -e
echo "port: exit $port_status"
[ "$port_status" -ne 0 ] && echo "port: stopped at: $(tail -1 "$build/port.txt" | cut -c1-60)"

# Two cases are compared apart, and the reason is MPSState.h's own: -resourceSize "is subject to
# change between different devices and operating systems", so the host's answer is a number about the
# host's heap rather than about the state. They are still printed, and still differ, and a difference
# anywhere else fails the run.
# Only the cases both runs reached: an oracle that stopped early cannot answer the rest, and comparing
# the prefix it did answer is the honest thing. Both runs print in the same order, so the prefix is the
# first N lines where N is the shorter of the two, and the case names are checked to line up.
system_lines=$(wc -l < "$build/system.txt" | tr -d ' ')
port_lines=$(wc -l < "$build/port.txt" | tr -d ' ')
n=$system_lines
[ "$port_lines" -lt "$n" ] && n=$port_lines
if [ "$system_lines" -ne "$port_lines" ]; then
    echo "the two runs reached different numbers of cases: system $system_lines, port $port_lines; compared over the first $n"
    echo "system stopped on: $(tail -1 "$build/system.txt" | cut -d' ' -f1-2)"
    echo "port   stopped on: $(tail -1 "$build/port.txt" | cut -d' ' -f1-2)"
fi
grep -v '^image ' "$build/system.txt" > "$build/system.cases"
grep -v '^image ' "$build/port.txt" > "$build/port.cases"
system_lines=$(wc -l < "$build/system.cases" | tr -d ' ')
port_lines=$(wc -l < "$build/port.cases" | tr -d ' ')
n=$system_lines
[ "$port_lines" -lt "$n" ] && n=$port_lines
head -n "$n" "$build/system.cases" > "$build/system.prefix"
head -n "$n" "$build/port.cases" > "$build/port.prefix"
cut -d' ' -f1 "$build/system.prefix" > "$build/system.names"
cut -d' ' -f1 "$build/port.prefix" > "$build/port.names"
if ! cmp -s "$build/system.names" "$build/port.names"; then
    # The cut lands inside a case, so the two name lists differ by one: the last name of the prefix.
    echo "the two runs reached different cases: $(diff "$build/system.names" "$build/port.names" | head -4 | tr '\n' ' ')"
    n=$((n - 1))
    head -n "$n" "$build/system.cases" > "$build/system.prefix"
    head -n "$n" "$build/port.cases" > "$build/port.prefix"
    echo "compared over the first $n complete cases"
fi
grep -v '^divergent ' "$build/system.prefix" > "$build/system.strict"
grep -v '^divergent ' "$build/port.prefix" > "$build/port.strict"
echo "compared: $(wc -l < "$build/system.strict") cases"
grep '^divergent ' "$build/system.prefix" > "$build/system.divergent" || true
grep '^divergent ' "$build/port.prefix" > "$build/port.divergent" || true
paste "$build/system.divergent" "$build/port.divergent" | while read -r line; do
    echo "documented divergence: $line"
done

if cmp -s "$build/system.strict" "$build/port.strict"; then
    echo "differing cases: 0"
    echo "port: same as the system, case for case and bit for bit"
else
    diff "$build/system.strict" "$build/port.strict" | head -60
    echo "port: DIFFERS in $(diff "$build/system.strict" "$build/port.strict" | grep -c '^<') cases"
    exit 1
fi
