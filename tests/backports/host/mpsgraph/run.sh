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
"$build/system" > "$build/system.txt" 2> "$build/system.err"
status=$?
set -e
echo "system: $(wc -l < "$build/system.txt") lines, exit $status"
[ "$status" -ne 0 ] && echo "system: stopped at: $(tail -1 "$build/system.txt" | cut -c1-70)"

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
"$build/port" > "$build/port.txt" 2> "$build/port.err"
port_status=$?
set -e
echo "port: exit $port_status"
[ "$port_status" -ne 0 ] && echo "port: stopped at: $(tail -1 "$build/port.txt" | cut -c1-70)"

# The red control: the same sources with every stored element off by one. It exists because a comparison
# that cannot see a wrong kernel is not a comparison, and this file's own history is the reason - the
# verdict line it printed for a year could not be told apart from a test nobody ran.
plant_objects=$(build_objects 1)
xcrun clang -fobjc-arc $target $quiet -include "$build/rename.h" "$here/graph-cases.m" $plant_objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework MetalPerformanceShadersGraph -o "$build/port-plant1"
set +e
"$build/port-plant1" > "$build/port-plant1.txt" 2> "$build/port-plant1.err"
plant_status=$?
set -e
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
    echo "  system: $(tail -1 "$build/system.txt" | cut -d' ' -f1-3)"
    echo "  port:   $(tail -1 "$build/port.txt" | cut -d' ' -f1-3)"
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
# The verdict, in the words the host sweep reads. It counted this directory as DEAD whatever the
# comparison said, because nothing here began a line the sweep recognises: this run ended
# "port: DIFFERS in 1 cases" and a sweep cannot tell that from a test nobody ran. The two counts are
# the comparison's own - the cases both sides answered, and how many of them differ - so the line
# says what happened rather than what someone hoped would.
if cmp -s "$build/system.prefix" "$build/port.prefix"; then
    echo "port: same as the system, case for case and bit for bit"
    echo "checks=$n failures=0"
else
    diff "$build/system.prefix" "$build/port.prefix" | head -40
    differs=$(diff "$build/system.prefix" "$build/port.prefix" | grep -c '^<')
    echo "port: DIFFERS in $differs cases"
    echo "checks=$n failures=$differs"
    exit 1
fi
