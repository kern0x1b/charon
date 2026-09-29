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
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-macos13.0 -isysroot $sdk"
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unguarded-availability -Wno-incomplete-implementation -Wno-nullability-completeness -Wno-objc-protocol-method-implementation"
mkdir -p "$build"

xcrun clang -fobjc-arc $target $quiet "$here/mps-cases.m" \
    -framework Foundation -framework Metal -framework MetalPerformanceShaders -o "$build/system"
"$build/system" > "$build/system.txt"
echo "system: $(wc -l < "$build/system.txt") lines"

# The names this port carries, each under a name of its own. Every class the registry's matrix.json
# names as implemented is here, and nothing else: a class the port does not carry is left as the
# system's, which is what a case that reaches one is testing.
python3 - "$here/../../../../packages/a/apple-backports/registry/MetalPerformanceShaders/matrix.json" "$build/rename.h" <<'PY'
import json, sys
names = set()
for entry in json.load(open(sys.argv[1]))["entries"]:
    if entry["kind"] == "class":
        names.add(entry["api"])
with open(sys.argv[2], "w") as out:
    for name in sorted(names):
        out.write("#define %s Charon%s\n" % (name, name))
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
"$build/port" > "$build/port.txt"

# Two cases are compared apart, and the reason is MPSState.h's own: -resourceSize "is subject to
# change between different devices and operating systems", so the host's answer is a number about the
# host's heap rather than about the state. They are still printed, and still differ, and a difference
# anywhere else fails the run.
grep -v '^divergent ' "$build/system.txt" > "$build/system.strict"
grep -v '^divergent ' "$build/port.txt" > "$build/port.strict"
echo "compared: $(wc -l < "$build/system.strict") cases"
grep '^divergent ' "$build/system.txt" > "$build/system.divergent"
grep '^divergent ' "$build/port.txt" > "$build/port.divergent"
paste "$build/system.divergent" "$build/port.divergent" | while read -r line; do
    echo "documented divergence: $line"
done

if cmp -s "$build/system.strict" "$build/port.strict"; then
    echo "port: same as the system, case for case and bit for bit"
else
    diff "$build/system.strict" "$build/port.strict" | head -60
    echo "port: DIFFERS in $(diff "$build/system.strict" "$build/port.strict" | grep -c '^<') cases"
    exit 1
fi
