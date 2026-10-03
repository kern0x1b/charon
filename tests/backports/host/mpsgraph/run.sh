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
objects=""
for source in "$graph"/*.m; do
    name=$(basename "$source" .m)
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -c "$source" -o "$build/$name.plain.o"
    python3 "$here/../prefix_selectors.py" "$source" "$build/$name.m" ccharonHost_ \
        --declarations="$build/declarations.h" -fobjc-arc $target $quiet -I"$graph" -include "$build/rename.h" -- "$build/$name.plain.o"
    xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -I"$graph" -include "$build/rename.h" \
        -include "$build/declarations.h" -c "$build/$name.m" -o "$build/$name.o"
    objects="$objects $build/$name.o"
done
echo "compiled: $(echo "$objects" | wc -w) objects"

xcrun clang -fobjc-arc $target $quiet -include "$build/rename.h" "$here/graph-cases.m" $objects \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework MetalPerformanceShadersGraph -o "$build/port"
set +e
"$build/port" > "$build/port.txt" 2> "$build/port.err"
port_status=$?
set -e
echo "port: exit $port_status"
[ "$port_status" -ne 0 ] && echo "port: stopped at: $(tail -1 "$build/port.txt" | cut -c1-70)"

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
echo "compared: $n cases"
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
