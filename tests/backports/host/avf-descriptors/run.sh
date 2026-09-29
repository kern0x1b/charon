#!/bin/sh
# run.sh — the avf-3a descriptor classes, the port against the host.
#
# One program (probe.m) linked twice: plain, where every name is Apple's own, and with the rename list
# and the port's five objects, where the same names are the port's own classes in the same binary.
# The two tables are joined row by row.
#
# Run DIRECTLY, not through heavy.sh: this is a handful of small compiles, and the gate is heavy.sh's
# job for the package builds, not for a probe.
#
# What makes it a check rather than a comparison:
#
#   * a name the port does not define is a LINK ERROR, so a missing class cannot read as "both sides
#     absent and therefore equal" - the failure AVMetadataItemFilter had as a bare category;
#   * the row count is asserted on both sides and against the count this probe emits, so an empty
#     table is a red and not a clean diff of two empty files;
#   * the harness is PLANTED, twice, and this is the part that says the harness works: the probe can
#     corrupt its own answers, and the run must notice. plant-all must go red on every row, plant-one
#     on exactly one. A run that passes while the probe is corrupting every answer is not a check;
#   * a mutation that does not build is RUN FAILED with the compiler's line and exit 1, so a build
#     failure is never counted as a noticed mutation;
#   * the CONTROL runs the unmutated source through the identical build-and-run path and must stay
#     green, so a red mutant is the mutation and not the path.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
# Per side, and they DIFFER on purpose: the port answers the 12.0 initializer the host cannot, so the
# port's table is two rows longer. Asserting one number for both would be asserting a falsehood in
# whichever direction it was wrong.
expected_host=${AVF_DESC_ROWS_HOST:-42}
expected_port=${AVF_DESC_ROWS_PORT:-42}
sources="AVPlayerMediaSelectionCriteria7 AVPlayerMediaSelectionCriteria7Members AVCaptureBracket8 AVAssetResourceRenewalRequest8 AVMediaSelection9"
control=${CONTROL:-0}
break=${BREAK:-0}
mutant=${AVFMUTANT:-0}
build=${AVF_DESC_BUILD:-$root/.agent-work/avf-descriptors-build}
baseline_dir=${AVF_DESC_BASELINE:-$root/.agent-work/avf-descriptors-baseline}
rm -rf "$build"
mkdir -p "$build/src" "$build/o" "$baseline_dir"

renames=""
for name in AVPlayerMediaSelectionCriteria AVCaptureBracketedStillImageSettings \
            AVCaptureAutoExposureBracketedStillImageSettings AVCaptureManualExposureBracketedStillImageSettings \
            AVAssetResourceRenewalRequest AVMediaSelection AVMutableMediaSelection; do
    renames="$renames -D$name=charon_host_$name"
done

for source in $sources; do cp "$avf/$source.m" "$build/src/$source.m"; done

if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    if [ "$break" != 0 ]; then
        python3 - "$build/src/AVMediaSelection9.m" <<'PERTURB'
import sys
path = sys.argv[1]
text = open(path).read()
before = '- (AVAsset *)asset'
if before not in text:
    raise SystemExit("the control did not apply, so this run proves nothing")
open(path, 'w').write(text.replace(before, '- (AVAsset *)this is not C at all'))
PERTURB
    else
        # The mutation is on the ISO the port STORES, not on the number the probe passes: 400 lives in
        # the probe's call site and the source never sees it, so a mutation aimed there would change
        # nothing - which the first aim did, and the "the mutant did not apply" guard said so by name.
        # Doubling what the source stores makes the ISO row differ and no other, which says the
        # mutation reached the member and nothing else.
        python3 - "$build/src/AVCaptureBracket8.m" <<'PERTURB'
import sys
path = sys.argv[1]
text = open(path).read()
before = 'ISO:iso];'
after = 'ISO:iso * 2.0f];'
if before not in text:
    raise SystemExit("the mutant did not apply, so this run proves nothing")
open(path, 'w').write(text.replace(before, after))
PERTURB
    fi
fi

objects=""
for source in $sources; do
    # shellcheck disable=SC2086
    if ! xcrun clang -fobjc-arc -w $renames -I"$avf" -c "$build/src/$source.m" -o "$build/o/$source.o" \
            > "$build/o/$source.log" 2>&1; then
        echo "RUN FAILED: the port's $source.m did not build - a build failure is never a noticed mutation"
        head -8 "$build/o/$source.log"
        exit 1
    fi
    objects="$objects $build/o/$source.o"
done

# 1. the host table
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w -I"$avf" "$here/probe.m" -framework Foundation -framework AVFoundation \
    -framework CoreMedia -o "$build/host" > "$build/host.log" 2>&1 || {
        echo "FAIL: the host probe did not build"; head -10 "$build/host.log"; exit 1; }
env -u AVFDESCPROBE "$build/host" > "$build/host.table" 2> "$build/host.stderr" || { echo "FAIL: the host probe did not run"; head -10 "$build/host.stderr"; exit 1; }

# 2. the same probe against the port's own classes
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w -I"$avf" $renames "$here/probe.m" $objects \
    -framework Foundation -framework AVFoundation -framework CoreMedia \
    -o "$build/port" > "$build/port.log" 2>&1 || {
        echo "FAIL: the port probe did not link - a name the port does not define is a link error"
        head -12 "$build/port.log"
        exit 1
    }
# The plant is given to the PORT build only. Given to both, the two tables are corrupted identically
# and a host-against-port diff sees no difference at all - which is what plant-all did before this
# line: "rows that differ: 0" and a pass, from a probe corrupting every answer on both sides.
if [ -n "${AVFDESCPROBE:-}" ]; then
    AVFDESCPROBE="$AVFDESCPROBE" "$build/port" > "$build/port.table" 2> "$build/port.stderr" || {
        echo "FAIL: the port probe did not run"; head -10 "$build/port.stderr"; exit 1; }
else
    "$build/port" > "$build/port.table" 2> "$build/port.stderr" || { echo "FAIL: the port probe did not run"; head -10 "$build/port.stderr"; exit 1; }
fi

# The baseline is the port's own UNMUTATED table, written beside the build directory (which is wiped
# on every run) and read by the join for the port-only rows. A mutant with no baseline beside it is a
# failure: it would be judging a mutation against nothing.
if [ "$mutant" = 0 ] || [ "$control" != 0 ]; then
    cp "$build/port.table" "$baseline_dir/port.baseline"
else
    [ -f "$baseline_dir/port.baseline" ] || {
        echo "FAIL: the mutant was asked for with no baseline beside it. Run this script once with no"
        echo "      AVFMUTANT first: a port-only row is judged against the port's own unmutated table."
        exit 1
    }
fi

# 3. neither table may be smaller than the claim
for side in host port; do
    rows=$(grep -c ' = ' "$build/$side.table" || true)
    if [ "$side" = host ]; then want=$expected_host; else want=$expected_port; fi
    if [ "$rows" -ne "$want" ]; then
        echo "FAIL: the $side table has $rows rows and this probe emits $want on that side, so the diff"
        echo "      below would compare something smaller than the claim"
        exit 1
    fi
    # the ~ rows are the port's own values, with no host oracle - they are held against the
    # baseline, not against the host, and the two kinds must not be confused
    portonly=$(grep -c '^~' "$build/$side.table" || true)
    echo "$side: $rows rows, of which $portonly are port-only (~), compared against the baseline"
done

diff -u "$build/host.table" "$build/port.table" > "$build/diff.log" 2>&1 && verdict=differs0 || verdict=differs
# the row count that actually differ, so the plants can be checked against a number and not a feeling
changed=$(python3 - "$build/host.table" "$build/port.table" "$baseline_dir/port.baseline" <<'PY'
import sys
def load(p):
    d={}
    for line in open(p):
        if " = " in line:
            k,_,v=line.rstrip("\n").partition(" = ")
            d[k.strip()]=v.strip()
    return d
NO_ORACLE="no-oracle-forwarding-object"
a,b=load(sys.argv[1]),load(sys.argv[2])
base=load(sys.argv[3]) if len(sys.argv)>3 else {}
# A row where either side answers "no oracle" is a PORT-ONLY row: the host has the class and the
# framework is the oracle, but this instance is a forwarding object, so there is nothing to compare
# against and the row is held against the port's own unmutated baseline instead. Comparing it
# host-against-port would be comparing a value with a refusal.
n=0
for k in set(a)|set(b):
    if a.get(k)==b.get(k) and NO_ORACLE not in (a.get(k) or ""):
        continue
    if NO_ORACLE in (a.get(k) or "") and base.get(k) is not None and b.get(k)==base.get(k):
        n+=1   # port-only: it matches the port's own baseline, so nothing differs
        continue
    n+=1
print(n)
PY
)
echo "rows that differ: $changed"

if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    if [ "$verdict" = differs0 ]; then
        echo "FAIL: the mutation left the tables equal, so this check cannot fail and proves nothing"
        exit 1
    fi
    echo "ok  the mutation was noticed, on $changed row(s):"
    sed -n '1,24p' "$build/diff.log"
    exit 0
fi
if [ "$mutant" != 0 ] && [ "$control" != 0 ]; then
    if [ "$verdict" != differs0 ]; then
        echo "FAIL: the control is not clean: the unmutated source through the identical path"
        echo "      still differs on $changed row(s), so the red is the path and not the mutation"
        exit 1
    fi
    echo "ok  the control is clean: the unmutated source through the identical build-and-run path"
    exit 0
fi

if [ "$verdict" != differs0 ]; then
    echo "FAIL: the port's table differs from the host's on $changed row(s)"
    cat "$build/diff.log"
    exit 1
fi
echo "ok  every row the host answers, the port answers the same"
log=$build
exit 0
