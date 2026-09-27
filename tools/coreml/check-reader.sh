#!/bin/sh
# The CoreML reader, measured against coremltools: every container is read and the tree printed
# is compared with the one protobuf's own reflection prints from the same file, and a set of
# malformed containers is checked to be refused.
#
# What it proves and what it does not: that the reader reads every field of every container
# under test exactly as the specification's own parser reads it. It does not prove the reader
# reads a field of a container that is not under test -- a weight matrix of a few thousand
# elements, a oneof case this set never exercises, a message the schema table holds but no
# container here reaches. The interpreter is measured separately, against predictions.
#
# Usage: sh tools/coreml/check-reader.sh <directory for the run output>
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORE=$ROOT/packages/a/apple-backports/CoreML
OUT=${1:-$ROOT/.agent-work/runs/coreml-reader}
CC=${CC:-clang}
CFLAGS="-std=c99 -Wall -Wextra -Wno-unused-parameter -O1 -fsanitize=address"

mkdir -p "$OUT"
echo "reader check -> $OUT"

# The containers and the reference dumps are written by coremltools, which is the authority
# here: a model this port reads has to be one a converter really emits.
if [ ! -f "$OUT/models/manifest.json" ]; then
    echo "writing the containers with coremltools..."
    python3 "$ROOT/tools/coreml/make-models.py" --out "$OUT/models"
fi

$CC $CFLAGS -I "$CORE" -o "$OUT/ml-dump" "$ROOT/tools/coreml/ml-dump.c" \
    "$CORE/CharonMLProto.c" "$CORE/CharonMLSchema.c"

failures=0
for model in "$OUT"/models/*.mlmodel; do
    name=$(basename "$model" .mlmodel)
    if ! "$OUT/ml-dump" "$model" > "$OUT/$name.actual" 2> "$OUT/$name.err"; then
        echo "$name: FAIL - the reader refused a container coremltools wrote"
        sed 's/^/    /' "$OUT/$name.err"
        failures=$((failures + 1))
        continue
    fi
    if diff -u "$OUT/models/$name.ref" "$OUT/$name.actual" > "$OUT/$name.diff"; then
        echo "$name: OK - the tree read is identical to the specification's own parser's"
    else
        echo "$name: FAIL - the tree read differs from the specification's own parser's"
        head -20 "$OUT/$name.diff" | sed 's/^/    /'
        failures=$((failures + 1))
    fi
done

# Malformed containers must be refused rather than half-read. A model that is not read must
# not be run, so what the reader does with the four shapes below is part of what it promises.
python3 - "$OUT/models/glm.mlmodel" "$OUT" <<'PYTHON'
import os, sys
source, out = sys.argv[1], sys.argv[2]
data = open(source, "rb").read()
bad = {
    "truncated.mlmodel": data[: len(data) // 2],
    "garbage.mlmodel": b"\xff\xff\xff\xff\xff\xff\xff\xff" * 8,
    "short-length.mlmodel": b"\x0a\x7f\x01\x02\x03",
    "field-past-end.mlmodel": b"\x12\x40\x02\x01",
}
for name, payload in bad.items():
    open(os.path.join(out, name), "wb").write(payload)
PYTHON

for bad in truncated garbage short-length field-past-end; do
    if "$OUT/ml-dump" "$OUT/$bad.mlmodel" > /dev/null 2>&1; then
        echo "$bad: FAIL - a malformed container was read as a model"
        failures=$((failures + 1))
    else
        echo "$bad: OK - refused, as a malformed container must be"
    fi
done

if [ "$failures" -eq 0 ]; then
    echo "reader check: OK (0 failures)"
    exit 0
fi
echo "reader check: FAIL ($failures failures)"
exit 1
