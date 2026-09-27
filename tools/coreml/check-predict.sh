#!/bin/sh
# The CoreML interpreter, measured against coremltools: every container the reader check writes
# is run over a fixed input, and the values the port produces are compared with the ones
# coremltools' own runtime produced for the same model and the same input, on this host.
#
# What it proves: that the arithmetic of the kinds of model under test -- a dense classifier,
# a convolutional one, a tree ensemble, a GLM, a pipeline, and each of the layers those reach
# -- is the arithmetic Core ML specifies. A model with no host input recorded (an image model
# this host has no image for) is listed and not compared, and the script fails if one that was
# meant to be compared was not.
#
# Usage: sh tools/coreml/check-predict.sh <directory for the run output>
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORE=$ROOT/packages/a/apple-backports/CoreML
OUT=${1:-$ROOT/.agent-work/runs/coreml-predict}
CC=${CC:-clang}
CFLAGS="-std=c99 -Wall -Wextra -Wno-unused-parameter -O1 -fsanitize=address"
# The float an interpreter and a compiled runtime may differ by, and the same every time: a
# conv accumulates in a different order on the two, and float32 has seven digits of it.
TOLERANCE=${TOLERANCE:-1e-5}

mkdir -p "$OUT"
echo "interpreter check -> $OUT"

if [ ! -f "$OUT/models/manifest.json" ]; then
    python3 "$ROOT/tools/coreml/make-models.py" --out "$OUT/models"
fi

$CC $CFLAGS -I "$CORE" -o "$OUT/ml-predict" "$ROOT/tools/coreml/predict-main.c" \
    "$CORE"/CharonML*.c

# The inputs, by name and value, as the harness takes them. They are the same inputs
# make-models.py recorded its predictions for, written here so a change to one of them is a
# diff rather than a silent disagreement.
run_case() {
    name=$1
    shift
    printf '%s\n' "$name" > "$OUT/$name.actual"
    "$OUT/ml-predict" "$OUT/models/$name.mlmodel" "$@" >> "$OUT/$name.actual" 2>&1 || true
}

run_case glm --set x 2 -1.5 0
run_case nn_classifier --set x 3 0.5 -0.25 1.0
run_case pipeline --set x 1 2
run_case tree_classifier --set a 1 0.25 --set b 1 1.0

# coremltools prints its own answers the same way, from the same models and the same inputs,
# so the two files are compared rather than the numbers parsed out of them.
python3 - "$OUT" "$TOLERANCE" <<'PYTHON'
import json, os, re, subprocess, sys
out, tolerance = sys.argv[1], float(sys.argv[2])
manifest = json.load(open(os.path.join(out, "models", "manifest.json")))

def numbers(text):
    return [float(v) for v in re.findall(r"-?\d+\.?\d*(?:e[-+]?\d+)?", text)]

def strings(text):
    return re.findall(r"= '([^']*)'", text)

failures = 0
compared = 0
for name in sorted(manifest):
    expected = manifest[name]["prediction"]
    if expected is None:
        print("%-15s SKIP - no host input recorded for this kind of model" % name)
        continue
    actual_path = os.path.join(out, name + ".actual")
    if not os.path.exists(actual_path):
        print("%-15s FAIL - the interpreter was not run" % name)
        failures += 1
        continue
    text = open(actual_path).read()
    if "ml-predict:" in text:
        print("%-15s FAIL - the interpreter refused the model: %s" % (name, text.strip().splitlines()[-1]))
        failures += 1
        continue
    wanted = {}
    for key, value in expected.items():
        if isinstance(value, str):
            wanted[key] = value
        elif isinstance(value, dict):
            # A dictionary of class labels to scores: the keys and the values are both checked,
            # because a dictionary with the right numbers under the wrong labels is a different
            # answer to an application reading it by name.
            wanted[key] = ("dict", sorted(value.keys()), [value[k] for k in sorted(value.keys())])
        elif isinstance(value, list):
            wanted[key] = numbers(re.sub(r"[\[\]]", " ", json.dumps(value)))
        else:
            wanted[key] = [value]
    ok = True
    for key, value in wanted.items():
        if key not in text:
            print("%-15s FAIL - no answer named '%s'" % (name, key))
            ok = False
            continue
        if isinstance(value, str):
            if ("'%s'" % value) not in text:
                print("%-15s FAIL - '%s' should be '%s'" % (name, key, value))
                ok = False
            continue
        line = [l for l in text.splitlines() if l.startswith(key + " = ")]
        if not line:
            print("%-15s FAIL - no answer line for '%s'" % (name, key))
            ok = False
            continue
        if isinstance(value, tuple):
            # A dictionary is a mapping and not a sequence: the keys are compared as a set and
            # each score against the one under the same key, because the order a dictionary's
            # keys come out in is not part of what it says.
            raw = re.findall(r"'([^']*)':\s*(-?[\d.eE+-]+)", line[0])
            got = dict((k, float(v)) for k, v in raw)
            if sorted(got) != list(value[1]):
                print("%-15s FAIL - '%s' has the keys %s, coremltools gave %s"
                      % (name, key, sorted(got), list(value[1])))
                ok = False
                continue
            for label, theirs in zip(value[1], value[2]):
                if abs(got[label] - theirs) > tolerance * max(1.0, abs(theirs)):
                    print("%-15s FAIL - %s['%s'] is %.9g, coremltools gave %.9g"
                          % (name, key, label, got[label], theirs))
                    ok = False
            continue
        got = numbers(re.sub(r"'[^']*':", " ", line[0].split("=", 1)[1]))
        if len(got) != len(value):
            print("%-15s FAIL - '%s' has %d values, coremltools gave %d" % (name, key, len(got), len(value)))
            ok = False
            continue
        for at, (mine, theirs) in enumerate(zip(got, value)):
            if abs(mine - theirs) > tolerance * max(1.0, abs(theirs)):
                print("%-15s FAIL - %s[%d] is %.9g, coremltools gave %.9g" % (name, key, at, mine, theirs))
                ok = False
    if ok:
        compared += 1
        print("%-15s OK - %d answers within %g of coremltools' own runtime" % (name, len(wanted), tolerance))
    else:
        failures += 1

print("compared %d models" % compared)
if failures:
    print("interpreter check: FAIL (%d failures)" % failures)
    sys.exit(1)
if compared == 0:
    print("interpreter check: FAIL (no model was compared: a check that compares nothing proves nothing)")
    sys.exit(1)
print("interpreter check: OK (0 failures)")
PYTHON
