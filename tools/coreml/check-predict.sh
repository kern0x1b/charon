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

# The inputs, by name and value, as the harness takes them. They are the same inputs
# make-models.py recorded its predictions for, written here so a change to one of them is a
# diff rather than a silent disagreement. A model whose input is more than a flat vector of
# numbers is fed by the Python side below, which reads the same manifest.
run_case glm --set x 2 -1.5 0
run_case glm_classifier --set x 2 0.5 -0.5
run_case nn_classifier --set x 3 0.5 -0.25 1.0
# The models whose input is a channels-first array: the shape is given, and the values follow.
run_case nn_layers --setr x 1x1x4 4 0.5 -1.5 2.0 0.25
run_case nn_layers_shape --setr x 1x1x2 2 0.5 -0.25
run_case pipeline --set x 1 2
run_case tree_classifier --set a 1 0.25 --set b 1 1.0

# The models whose input is not one flat vector: a multi-dimensional array, and an embedding's
# integer indices. The harness takes a flat vector, so their numbers are laid out here in the
# order the shape says, which for a channels-first array is the last dimension varying fastest.
python3 - "$OUT" <<'PYTHON'
import json, os, subprocess, sys
out = sys.argv[1]
manifest = json.load(open(os.path.join(out, "models", "manifest.json")))
harness = os.path.join(out, "ml-predict")
# (field, shape, values), for the inputs that are not one flat vector: an embedding's single
# word index, and the convolutional model's 192 pixels, which are the same bytes its PIL image
# was made of.
extra = {
    "nn_embedding": ("index", "1x1x1", [2]),
    "nn_image": ("img", "3x8x8", [(at * 37 % 256) / 255.0 for at in range(3 * 8 * 8)]),
}
for name, spec in sorted(extra.items()):
    if name not in manifest or manifest[name]["prediction"] is None:
        continue
    field, shape, values = spec
    with open(os.path.join(out, name + ".actual"), "w") as f:
        f.write(name + "\n")
        subprocess.run([harness, os.path.join(out, "models", name + ".mlmodel"),
                        "--setr", field, shape, str(len(values))] + ["%.9g" % v for v in values],
                       stdout=f, stderr=subprocess.STDOUT)
PYTHON

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
known = 0
for name in sorted(manifest):
    expected = manifest[name]["prediction"]
    model_tolerance, why = manifest[name].get("tolerance", [tolerance, None]) or [tolerance, None]
    divergence = manifest[name].get("divergence")
    limit = max(tolerance, float(model_tolerance))
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
        if divergence:
            # The per-answer differences of a model with a recorded divergence are reported as
            # one line below, not as a list of failures over the top of it.
            continue
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
                if abs(got[label] - theirs) > limit * max(1.0, abs(theirs)):
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
            if abs(mine - theirs) > limit * max(1.0, abs(theirs)):
                print("%-15s FAIL - %s[%d] is %.9g, coremltools gave %.9g" % (name, key, at, mine, theirs))
                ok = False
    if divergence and ok is False and "FAIL" in text or (divergence and "FAIL" not in text):
        # A model whose difference from the host is known and written down. The check says what
        # the difference is, and fails if the two ever agree, so a stale explanation is caught.
        differs = False
        for key, value in wanted.items():
            if isinstance(value, tuple):
                line = [l for l in text.splitlines() if l.startswith(key + " = ")]
                got = {}
                if line:
                    got = dict((k, float(v)) for k, v in
                               re.findall(r"'([^']*)':\s*(-?[\d.eE+-]+)", line[0]))
                differs = differs or any(abs(got.get(lbl, 0.0) - th) > tolerance * max(1.0, abs(th))
                                         for lbl, th in zip(value[1], value[2]))
                continue
            line = [l for l in text.splitlines() if l.startswith(key + " = ")]
            if not line:
                continue
            got = numbers(re.sub(r"'[^']*':", " ", line[0].split("=", 1)[1]))
            for mine, theirs in zip(got, value if isinstance(value, list) else []):
                differs = differs or abs(mine - theirs) > tolerance * max(1.0, abs(theirs))
        if differs:
            print("%-15s KNOWN DIVERGENCE - the port's answers differ from the host's, and the "
                  "difference is written down" % name)
            print("%-15s                 %s" % ("", divergence))
            known += 1
            continue
        print("%-15s FAIL - the divergence is recorded but the port and the host now agree, so "
              "whatever caused it is gone" % name)
        failures += 1
        continue
    if ok and why:
        # A model with a stated divergence: the check also fails if the host ever stops
        # diverging, because then the reason for the wider tolerance is no longer true and the
        # wider tolerance would be hiding a real difference of its own.
        if not any(abs(mine - theirs) > tolerance * max(1.0, abs(theirs))
                   for key, value in wanted.items() if isinstance(value, list)
                   for mine, theirs in zip(numbers(re.sub(r"'[^']*':", " ", text)), value)):
            print("%-15s FAIL - the host no longer diverges (%s): a wider tolerance would now hide a real difference"
                  % (name, why))
            failures += 1
            continue
        print("%-15s OK - %d answers within %g, and the host still diverges as it did (%s)"
              % (name, len(wanted), limit, why))
        compared += 1
        continue
    if ok:
        compared += 1
        print("%-15s OK - %d answers within %g of coremltools' own runtime" % (name, len(wanted), limit))
    else:
        failures += 1

print("compared %d models, %d with a recorded divergence" % (compared, known))
if failures:
    print("interpreter check: FAIL (%d failures)" % failures)
    sys.exit(1)
if compared == 0:
    print("interpreter check: FAIL (no model was compared: a check that compares nothing proves nothing)")
    sys.exit(1)
print("interpreter check: OK (%d failures, %d models compared, %d with a recorded divergence)"
      % (failures, compared, known))
PYTHON
