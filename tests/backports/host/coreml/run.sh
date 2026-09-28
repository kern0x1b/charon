#!/bin/sh
# run.sh — the Core ML host differential: what this host's own Core ML answers for a set of real
# .mlmodel containers is recorded, the port's classes are then compiled under names of their own
# (Charon<name>) over the port's own reader and interpreter, held to the same record, and each
# difference is either fixed in the port or written down. Mutants of the port each have to be
# caught, so a rule that quietly stops being applied cannot pass.
#
# The prediction *numbers* of one container, nn_image, are a recorded divergence and are compared
# separately: facts/CoreML/CoreML.md sets out what has been ruled out for it, and the check fails
# if a difference appears in any other container.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
coreml=${COREML:-$root/packages/a/apple-backports/CoreML}
registry=${REGISTRY:-$root/packages/a/apple-backports/registry/CoreML}
models=${MODELS:-$root/.agent-work/runs/coreml-predict/models}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -fobjc-arc -w -Wno-unguarded-availability"
libs="-framework Foundation -framework CoreGraphics -framework CoreVideo -framework CoreML"

if [ ! -d "$models" ]; then
    echo "no containers in $models: run sh tools/coreml/make-models.py --out $models first"
    exit 1
fi

# 1. what the system's own Core ML answers. COREML_HOST tells the cases file to compile each
#    container with the framework's own compiler first: this host refuses to read an uncompiled
#    .mlmodel, and the two runs below are of one model in the two forms each framework reads.
xcrun clang $common -DCOREML_HOST=1 -I"$here" "$here/record.m" "$here/cases.m" $libs -o "$build/system"
COREML_RECORDS="$build/system.json" "$build/system" "$models"

# 2. the same questions of the port, with every Core ML name it answers behind a Charon prefix so
#    that the two sets of classes can sit in one binary. The registry says which names those are:
#    the classes and protocols this port carries, and the constants it exports -- a constant the
#    port also defines would be a duplicate of the framework's own.
python3 - "$registry" "$build/rename.h" <<'PY'
import glob, json, os, sys
names = set()
for path in glob.glob(os.path.join(sys.argv[1], "*.json")):
    for entry in json.load(open(path))["entries"]:
        if entry["kind"] in ("class", "protocol", "constant", "function"):
            names.add(entry["api"].replace("()", ""))
with open(sys.argv[2], "w") as out:
    for name in sorted(names):
        out.write("#define %s Charon%s\n" % (name, name))
PY

# Compiles the port from the sources in $1 -- the whole package, its C files and the generated
# table as well as its Objective-C -- and writes the binary into $2. A mutant is a copy of the whole
# tree, so a mutant of a .c, a .h or a .m is really compiled; taking the C from the pristine tree
# would make the whole mutant layer vacuous, because the binary would be the pristine one whatever
# the copy says, and `mutants surviving: 0` would be a line that cannot fail.
port() {
    src=$1
    dir=$2
    mkdir -p "$dir"
    xcrun clang $common -include "$build/rename.h" -I"$here" -I"$src" \
        "$here/record.m" "$here/cases.m" \
        "$src"/CharonML*.c "$src"/*.m $libs -o "$dir/run"
}
mkdir -p "$build/port"
port "$coreml" "$build/port"
COREML_RECORDS="$build/port.json" "$build/port/run" "$models"

# 3. the comparison: every key must be in both files, and must hold the same value, except the
#    numbers of the prediction of a container that is a recorded divergence.
# One difference is recorded rather than failed, and it is a measurement rather than a tolerance:
# the numbers of nn_image's prediction, which facts/CoreML/CoreML.md records and the interpreter
# check holds to coremltools' own runtime. It is printed by name below.
COREML_DIVERGENT=${COREML_DIVERGENT:-nn_image} python3 - "$build/system.json" "$build/port.json" <<'PY'
import json, os, sys
system, port = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
divergent = os.environ.get("COREML_DIVERGENT", "")
differences, missing = [], []
for key in sorted(set(system) | set(port)):
    if key not in system or key not in port:
        missing.append(key)
    elif system[key] != port[key]:
        differences.append((key, system[key], port[key]))
# A number may differ by the width of the type it is stored in: the host runs the same arithmetic
# on its own hardware, in float32, and the port's interpreter is measured against coremltools' own
# runtime to 1e-5 by tools/coreml/check-predict.sh. Here the tolerance is a float32's, and a number
# beyond it is still reported -- unless the container is one facts/CoreML/CoreML.md records as a
# divergence, whose whole point is that the two do not agree.
TOLERANCE = float(os.environ.get("COREML_TOLERANCE", "1e-3"))

def numeric(key, want, got):
    """A recorded value is one number or a comma-joined list of them, and it is compared number by
    number: a string that is not a number at all is not within a tolerance of anything."""
    left, right = str(want).split(","), str(got).split(",")
    if len(left) != len(right):
        return False
    for one, other in zip(left, right):
        try:
            if abs(float(one) - float(other)) > TOLERANCE:
                return False
        except ValueError:
            return False
    return True

informational, hard = [], []
for key, want, got in differences:
    # Recorded, in each case, by what the framework answered and not by how a key is spelled: the
    # numbers of the prediction of a container this port and this host are a measured divergence
    # apart, and a key the framework has no answer for -- it raised -- has nothing to compare
    # against. A prefix rule could not notice either of those ceasing to be true, and a rule that
    # exempts a prefix is a rule that hides a regression in whatever the prefix names.
    recorded = ((key.startswith("value/") and divergent and ("/" + divergent + "/") in key)
                or str(want).startswith("raised "))
    if recorded:
        informational.append((key, want, got))
    elif key.startswith("value/") and numeric(key, want, got):
        pass  # within the tolerance of the type, which is not a difference
    else:
        hard.append((key, want, got))
for key, want, got in hard:
    print("DIFF", key)
    print("  system", want[:300])
    print("  port  ", got[:300])
for key in missing:
    print("MISSING", key)
for key, want, got in informational:
    print("divergent (recorded):", key)
    print("  system", want[:200])
    print("  port  ", got[:200])
print("compared %d keys, %d differ, %d missing, %d recorded divergences" %
      (len(set(system) | set(port)), len(hard), len(missing), len(informational)))
if hard or missing:
    print("port: DIFFERS")
    raise SystemExit(1)
print("port: same as the system")
PY

# 4. mutants: each of these has to change the PORT's own record, or the rule it stands for is not
#    being applied. Not one is here: -[MLModel predictionFromFeatures:error:]'s skip of an undefined
#    value, which is the rule that keeps an optional input the caller left out from being sent as an
#    empty value. No container exercises it -- the specification's isOptional is not set on any
#    input of any model tools/coreml/make-models.py writes -- so a mutant of it would survive for a
#    reason that is the corpus's and not the rule's. Writing a container with an optional input is
#    what puts it back, and it is the first thing the next round does.
survived=0
ran=0
mutant() {
    ran=$((ran + 1))
    file=$1
    from=$2
    to=$3
    rm -rf "$build/mutant"
    mkdir -p "$build/mutant"
    cp "$coreml"/*.m "$coreml"/*.h "$coreml"/CharonML*.c "$coreml"/*.inc "$build/mutant/" 2>/dev/null || true
    python3 - "$build/mutant/$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
assert old in text, old
open(path, "w").write(text.replace(old, new, 1))
PY
    port "$build/mutant" "$build/mutant" 2>/dev/null || { echo "mutant did not build: $file $from -> $to"; survived=$((survived + 1)); return; }
    rm -f "$build/mutant.json"
    COREML_RECORDS="$build/mutant.json" "$build/mutant/run" "$models" > /dev/null 2>&1 || true
    if cmp -s "$build/port.json" "$build/mutant.json"; then
        echo "MUTANT SURVIVED: $file $from -> $to"
        survived=$((survived + 1))
    fi
}
mutant MLFeatureDescription.m "if (value.isUndefined) {
        return _optional;" "if (value.isUndefined) {
        return YES;"
mutant MLFeatureDescription.m "if (value.type != _type) {
        return NO;" "if (value.type == 12345) {
        return NO;"
mutant MLFeatureDescription.m "        if (_multiArrayConstraint.dataType != (MLMultiArrayDataType)0 &&" "        if (0 &&"
mutant CharonMLConstraints.h "            if ([constraint.enumeratedShapes[index] isEqualToArray:shape]) {
                return YES;
            }" "            if (YES) {
                return YES;
            }"
mutant CharonMLConstraints.h "        return [[MLMultiArrayShapeConstraint alloc] charon_initWithType:MLMultiArrayShapeConstraintTypeEnumerated" "        return [[MLMultiArrayShapeConstraint alloc] charon_initWithType:MLMultiArrayShapeConstraintTypeRange"
mutant MLModel.m "type = charon_ml_feature_type_of(described->type);" "type = MLFeatureTypeDouble;"
mutant MLModel.m "answer = [self predictionFromFeatures:one options:options error:error];" "answer = nil;
        (void)options;"
mutant MLModel.m "charon_ml_error(error, CHARON_ML_ERROR_IO,
                        @\"a model is read from a file" "charon_ml_error(error, CHARON_ML_ERROR_GENERIC,
                        @\"a model is read from a file"
mutant MLParameter.m "return [[[self class] alloc] charon_initWithName:name scope:nil];" "return [[[self class] alloc] charon_initWithName:[name uppercaseString] scope:nil];"
mutant MLArrayBatchProvider12.m "        } else if ([dictionary[name] count] != count) {" "        } else if (0) {"
mutant MLFeatureProvider.m "        return [MLFeatureValue featureValueWithInt64:[object longLongValue]];" "        return [MLFeatureValue featureValueWithDouble:[object doubleValue]];"
mutant MLFeatureProvider.m "    if ([object isKindOfClass:[NSArray class]]) {" "    if (0) {"
mutant MLFeatureValue.m "    if (_type != MLFeatureTypeInt64 || _value.kind != CHARON_ML_VALUE_NUMBER) {" "    if (_value.kind != CHARON_ML_VALUE_NUMBER) {"
mutant MLFeatureValue.m "    if (_value.kind != CHARON_ML_VALUE_STRING) {
        return nil;
    }" "    if (_value.kind == CHARON_ML_VALUE_NONE) {
        return nil;
    }"
mutant MLFeatureValue.m "        _value = charon_ml_value_string_copy(text.UTF8String, strlen(text.UTF8String));" "        _value = charon_ml_value_string_copy(\"\", 0);"
mutant MLFeatureValue.m "    [coder encodeObject:self.multiArrayValue forKey:@\"array\"];" "    [coder encodeObject:nil forKey:@\"array\"];"
mutant MLFeatureValue.m "        _multiArray = array;" "        _multiArray = nil;"
mutant MLConstants.m '@"com.apple.CoreML"' '@"CoreML"'
echo "mutants: $ran run, $survived surviving"
[ "$survived" -eq 0 ]
