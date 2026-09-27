#!/bin/sh
# The port's SparseBLAS9.m held against the host's own Accelerate, case by case: the same inputs through
# each, comparing a status, a count and every element.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ACCELERATE=${ACCELERATE:-$here/../../../../packages/a/apple-backports/Accelerate}
build=${SPARSEBLAS_BUILD:-${TMPDIR:-/tmp}/charon-sparseblas-host}
rm -rf "$build"
mkdir -p "$build"

# Every API name the port's source defines is renamed in the port's own translation unit, so this one
# can hold the port's objects and the host's side by side. The names come from the port's registry and
# not from a list kept here, so a name added to the library is renamed too.
renames=""
for name in $(python3 - "$here" <<'PY'
import json, os, sys
here = sys.argv[1]
registry = os.path.join(here, "..", "..", "..", "..", "packages", "a", "apple-backports", "registry", "Accelerate")
for part in sorted(os.listdir(registry)):
    for entry in json.load(open(os.path.join(registry, part)))["entries"]:
        name = entry["api"].rstrip("()")
        if entry["kind"] == "function" and name.startswith("sparse_"):
            print(name)
PY
); do
    renames="$renames -D$name=charon_host_$name"
done

xcrun clang -fobjc-arc -w $renames -I"$ACCELERATE" -c "$ACCELERATE/SparseBLAS9.m" -o "$build/SparseBLAS9.o"
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unused-function \
    "$here/differential.m" "$build/SparseBLAS9.o" \
    -framework Foundation -framework Accelerate -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
