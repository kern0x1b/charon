#!/bin/sh
# THIS SUITE COMPARES THE CLASSES: the class exists, it conforms to the protocol the SDK declares, and each accessor is spelled as the SDK spells it and lives where the SDK puts it. The sibling videotoolbox/run.sh compares the 135 STRING CONSTANTS, which are values rather than shapes.
# run.sh — a host differential for the port's VideoToolbox classes: the class exists, it conforms to the
# protocol the SDK declares, every accessor is spelled the SDK spells it, and each accessor lives WHERE
# the SDK declares it — on the class for a class property, on the instance otherwise. One mutation per
# covered class must change a record, and the mutation is the one the family is most likely to make: a
# class property that becomes an instance method, or the reverse.
#
# It is a shape comparison and not a value one, and the reason is measured rather than chosen: the
# host's VideoToolbox refuses dimensions it does not support — its own documentation says
# initWithFrameWidth: returns nil for them — so neither side can be put into a state where a value
# could be compared. What the host can be asked about is the shape, and that is what compare.py holds
# the port to.
#
# covered.txt says which classes the comparison asks about, so each class lands in it in the commit
# that adds the class. mutants.txt carries one mutation per covered class, in the file that class owns —
# one class per file is what makes each mutation's anchor unique, so mutate.py can insist on it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# The lists the run asks about come from the environment when it is given them, so a driver can ask about
# a class that is not committed yet WITHOUT writing the class into the committed lists first. A class that
# fails its differential must leave no trace that would make the next run skip it - which is exactly what
# appending to covered.txt before the commit did, and it cost four classes a run to find.
covered=${VTCLASS_COVERED:-$here/covered.txt}
gen=$here/../../../../.agent-work/generated/vt

# the generated table roundtrip-cases.h, which cases-roundtrip.m includes
appledir=${APPLEDIR:-$here/../../../../packages/a/apple-backports}
vt="$appledir/VideoToolbox"
# 0. THE PACKAGE RECIPE MUST PARSE, and this differential cannot see it: it compiles the value files
#    itself and never loads the recipe, so a recipe with a syntax error leaves the whole family green.
#    The light guard is the only check that loads it, and it found exactly that - a missing comma in
#    table.join, introduced by a rebase resolution, invisible here for eleven commits. So the guard runs
#    FIRST and its exit code is checked; a recipe that does not parse turns this run red.
light_tests=${LIGHT_TESTS:-$HOME/Git/projects/ios/coordination/run_light_tests.lua}
if [ "${VT_SKIP_LIGHT:-0}" != "1" ] && [ -f "$light_tests" ]; then
    xmake l "$light_tests" "$PWD" || {
        echo "the package recipe does not load, and this differential cannot see that: exit 1 above is"
        echo "descriptions_test, and the value files below were compiled without it"
        exit 1
    }
fi

build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path --sdk macosx)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc -w"
libs="-framework Foundation -framework CoreMedia -framework VideoToolbox"

# 0. the port's DECLARATIONS against SDK 26.2's own headers, before anything is compiled: a selector, an
#    argument count or a type that disagrees with the SDK is found here rather than by a caller, and the
#    initialiser of VTMotionBlurConfiguration was declared with four arguments where the SDK declares five
#    for twenty-six commits before anything noticed.
# with a default, so a bare ./run.sh needs nothing set; the driver exports the same path
VT_SDK=${VT_SDK:-$HOME/.xmake/packages/i/iphoneos-sdk/26.2/05d7872150914e1884a8de9d9dc71896/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk}
export VT_SDK
# 0a. PROVISION THE INPUTS. A clean tree has no .agent-work/generated/vt: probe-types.py and emit.py
#     both write there, and cases-roundtrip.m includes the header emit.py produces, so a run that skipped
#     them stopped with "roundtrip-cases.h file not found" - which is how a reviewer reached the mutants
#     and found nothing there. The runner generates what it needs, in order, and CHECKS that each step
#     produced its output rather than trusting the exit status.
rm -f "$gen/roundtrip-cases.h" "$gen/mutants.tsv"
python3 "$here/probe-types.py" || exit 1
runs=$here/../../../../.agent-work/runs/vt
[ -s "$here/type-branches.tsv" ] || { echo "the committed type-branches.tsv is missing, and the generator reads that one"; exit 1; }
python3 "$here/emit.py" "$VT_SDK" || exit 1
for generated in roundtrip-cases.h mutants.tsv summary.json; do
    [ -s "$gen/$generated" ] || { echo "emit.py produced no $generated"; exit 1; }
done
echo "provisioned: $(wc -l < "$runs/type-branches.tsv" | tr -d ' ') types, $(wc -l < "$gen/mutants.tsv" | tr -d ' ') mutants"

# The anchors are GENERATED, from the same emission that produced the accessors, and a stale hand-written
# one is how all sixteen mutants came to report as survivors. The generated list wins when it is there.
if [ -z "${VTCLASS_MUTANTS:-}" ] && [ -f "$gen/mutants.tsv" ]; then
    mutants=$gen/mutants.tsv
else
    mutants=${VTCLASS_MUTANTS:-$here/mutants.txt}
fi

python3 "$here/check-declarations.py" "$VT_SDK" --quiet
# A NAME IN NEITHER TABLE must be refused, and the refusal is run here rather than left to a reader:
# DECLARED_KEYS is the only way past the check that a property exists, so it is where a generator's own
# mistake would hide, and a control that is only ever run by hand is a control that is not run.
python3 "$here/decoy_test.py" || { echo "the decoy name was accepted"; exit 1; }

# 1. the host's own VideoToolbox
# every build's exit status is checked, and the binary is removed first: a run.sh that reuses the last
# build's binary after a compile failed answers with the PREVIOUS comparison and reports it as this one's
rm -f "$build/system" "$build/port"
xcrun clang $common -I"$here" "$here/record.m" "$here/cases.m" "$here/cases-roundtrip.m" -I"$gen" $libs -o "$build/system"
VTCLASS_COVERED="$covered" VTCLASS_RECORDS="$build/system.json" "$build/system"
echo "the host answered: $(python3 -c "import json; print(len(json.load(open('$build/system.json'))))")"

# 2. the port's own build, every class under names of its own
python3 "$here/rename.py" "$build/rename.h"
xcrun clang $common -DCHARON_HOST_DIFFERENTIAL=1 -DCHARON_VT_DECLARE_FOR_CASE=1 -include "$build/rename.h" -I"$here" -I"$vt" \
    "$here/record.m" "$here/cases.m" "$here/cases-roundtrip.m" -I"$gen" "$vt"/*.m $libs -o "$build/port"
VTCLASS_COVERED="$covered" VTCLASS_RECORDS="$build/port.json" "$build/port"
for side in system port; do
    # every covered class must have contributed its records; a run that stopped early is a red answer
    for cls in $(cat "$covered"); do
        key="class.$cls"
        grep -q "\"$key\"" "$build/$side.json" || {
            echo "$side: no record for $key - the build lost the class before it was asked anything"
            exit 1
        }
    done
done
python3 "$here/compare.py" "$build/system.json" "$build/port.json" "$here/cases.m"

# 3. one mutation per covered class. A mutation that does not apply is an error, not a pass, and a
#    mutation whose records are unchanged is a survivor: the comparison did not see it.
survived=0
while IFS="$(printf '\t')" read -r cls file from to; do
    [ -n "$cls" ] || continue
    grep -qx "$cls" "$covered" || continue
    label="$cls: $from -> $to"
    rm -rf "$build/mutant"
    mkdir -p "$build/mutant"
    cp "$vt"/*.m "$build/mutant/"
    if ! python3 "$here/mutate.py" "$build/mutant/$file" "$from" "$to" >/dev/null; then
        echo "MUTATION DID NOT APPLY: $label"
        survived=$((survived + 1))
        continue
    fi
    if ! xcrun clang $common -DCHARON_HOST_DIFFERENTIAL=1 -DCHARON_VT_DECLARE_FOR_CASE=1 -include "$build/rename.h" -I"$here" \
        -I"$build/mutant" -I"$vt" "$here/record.m" "$here/cases.m" "$here/cases-roundtrip.m" -I"$gen" "$build/mutant"/*.m $libs \
        -o "$build/mutant/run" >"$build/mutant/compile.log" 2>&1; then
        echo "MUTANT DID NOT COMPILE: $label"
        tail -5 "$build/mutant/compile.log"
        survived=$((survived + 1))
        continue
    fi
    rm -f "$build/mutant.json"
    VTCLASS_COVERED="$covered" VTCLASS_RECORDS="$build/mutant.json" timeout 90 "$build/mutant/run" >/dev/null 2>&1 || true
    if cmp -s "$build/port.json" "$build/mutant.json"; then
        echo "MUTANT SURVIVED: $label"
        survived=$((survived + 1))
    else
        python3 -c "
import json
a = json.load(open('$build/port.json')); b = json.load(open('$build/mutant.json'))
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k): print('  caught: %-58s %r -> %r' % (k, a.get(k), b.get(k)))"
    fi
done < "$mutants"

if [ "$survived" -ne 0 ]; then
    echo "$survived mutations survived"
    exit 1
fi
# WHAT WAS ACTUALLY MUTATED, AND WHAT WAS NOT. The verdict above says whether every mutation that ran was
# caught; it says nothing about the classes that had no mutation to run, and a class with no mutant looks
# exactly like a class that passed. So: per class, what was caught, and the classes with nothing - by NAME,
# compared against a checked-in list that this run fails against if it GROWS.
python3 - "$build/port.json" "$build/mutant.json" "$mutants" "$here/covered.txt" "$here/mutants-expected.txt" <<'PYEOF2'
import json, sys
base, mutant, mutants, covered, expected = sys.argv[1:6]
try:
    before, after = json.load(open(base)), json.load(open(mutant))
except ValueError:
    print("  (no mutant build to read)")
    before, after = {}, {}
mutated = {}
for line in open(mutants):
    if line.strip():
        mutated.setdefault(line.split("\t")[0], 0)
        mutated[line.split("\t")[0]] += 1
for cls in sorted(c for c in open(covered).read().split() if c):
    count = mutated.get(cls, 0)
    if not count:
        continue
    changed = [k for k in set(before) | set(after) if before.get(k) != after.get(k)]
    print("  %-48s %d mutant(s) applied, %d record(s) changed" % (cls, count, len(changed)))
skipped = sorted(c for c in open(covered).read().split() if c and c not in mutated)
import re as _re
listed = sorted(l for l in open(expected).read().split() if _re.match(r"^VT\w+$", l))
grew = [c for c in skipped if c not in listed]
vanished = [c for c in listed if c not in skipped]
if grew:
    print("  CLASSES WITH NO MUTANT THAT ARE NOT IN mutants-expected.txt: %s" % ", ".join(grew))
if vanished:
    print("  classes that now HAVE a mutant and can come off the list: %s" % ", ".join(vanished))
if skipped:
    print("  LISTED SKIP - no mutant, by name (%d): %s" % (len(skipped), ", ".join(skipped)))
else:
    print("  every covered class has a mutant")
if grew:
    sys.exit(1)
PYEOF2
echo "mutations: all caught"
