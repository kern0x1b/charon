#!/bin/sh
# run.sh — the notification/key/option constants of slice avf-1, the port against the host.
#
# One program (probe.m) linked twice. Linked plain, every name is Apple's own exported symbol and the
# table it prints is the host's. Linked with the rename list and the port's four objects, the same
# names are the port's own definitions and the same table is read out of them. The two tables are
# diffed.
#
# The harness COMPILES the port's sources, LINKS them beside Apple's, and READS the port's object.
# Three things that gives which reading the sources would not:
#
#   * a name the port does not define is a LINK ERROR, so a missing constant cannot read as "both
#     sides absent and therefore equal";
#   * the value and the bytes are both compared, and a value that is not valid UTF-8 answers NULL from
#     -UTF8String, so text alone would print "(null)" on both sides and pass;
#   * a run that compared nothing fails. The row count is asserted on both sides and against the count
#     this slice claims, so an empty table is a red and not a clean diff of two empty files.
#
# The mutant is the check's own falsifiability, and the control is what says the red is the mutation:
#
#   AVFMUTANT=1            perturbs one value by one byte and the diff must go red on that row
#   AVFMUTANT=1 CONTROL=1  runs the UNMUTATED source through the identical build-and-run path and must
#                          stay green
#   AVFMUTANT=1 BREAK=1    breaks a file so it does not compile, which must be RUN FAILED and exit 1:
#                          a build failure is never a noticed mutation
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
build=${AVF_NOTICE_BUILD:-$root/.agent-work/avf-notifications}
expected=${AVF_NOTICE_ROWS:-33}
sources="AVFoundationKeys9 AVFoundationKeys11 AVFoundationKeys16 AVFoundationKeysUnheld"
control=${CONTROL:-0}
break=${BREAK:-0}
mutant=${AVFMUTANT:-0}
rm -rf "$build"
mkdir -p "$build/src" "$build/o"

renames=""
for source in $sources; do
    names=$(sed -n 's/^NSString \*const \([A-Za-z0-9_]*\) = .*/\1/p' "$avf/$source.m")
    [ -n "$names" ] || { echo "FAIL: $source.m defines no constant"; exit 1; }
    for name in $names; do renames="$renames -D$name=charon_host_$name"; done
done

# The copies come FIRST and the perturbation second: a perturb that ran before its file existed
# raised FileNotFoundError, and a harness that calls that "noticed" would be counting a crash.
for source in $sources; do cp "$avf/$source.m" "$build/src/$source.m"; done
total=0
for source in $sources; do total=$((total + $(grep -c '^NSString \*const' "$avf/$source.m"))); done
if [ "$total" != "$expected" ]; then
    echo "FAIL: the sources define $total constants and this slice claims $expected"; exit 1
fi

# The table the probe reads: one row per constant, from the sources in the tree, written into the
# build directory and not into the checkout - it is generated on every run.
: > "$build/table.inc"
for source in $sources; do
    sed -n 's/^NSString \*const \([A-Za-z0-9_]*\) = .*/    { "\1", \&\1 },/p' "$build/src/$source.m" >> "$build/table.inc"
done

if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    if [ "$break" != 0 ]; then
        python3 - "$build/src/AVFoundationKeys16.m" <<'PERTURB'
import sys
path = sys.argv[1]
text = open(path).read()
before = 'NSString *const AVFragmentedMovieWasDefragmentedNotification'
if before not in text:
    raise SystemExit("the control did not apply, so this run proves nothing")
text = text.replace(before, 'this is not C at all')
open(path, 'w').write(text)
PERTURB
    else
        # One value, one byte: the notification's own name loses its last character. A differential
        # over strings cannot miss that, and a differential over addresses could not see it at all.
        # Aimed at the 16.0 object because the first aim was a name the 9.3.6 object carries - the
        # split put it there, and the perturb said so by name rather than passing for the wrong reason.
        python3 - "$build/src/AVFoundationKeys16.m" <<'PERTURB'
import sys
path = sys.argv[1]
text = open(path).read()
before = '@"AVFragmentedMovieWasDefragmentedNotification"'
after = '@"AVFragmentedMovieWasDefragmentedNotificatio"'
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
xcrun clang -fobjc-arc -w -I"$build" "$here/probe.m" -framework Foundation -framework AVFoundation \
    -o "$build/host" > "$build/host.log" 2>&1 || { echo "FAIL: the host probe did not build"; head -8 "$build/host.log"; exit 1; }
set +e; "$build/host" > "$build/host.table" 2> "$build/host.stderr"; host_status=$?; set -e

# 2. the same probe against the port's own definitions, in one binary with Apple's
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w -I"$build" $renames "$here/probe.m" $objects \
    -framework Foundation -framework AVFoundation -o "$build/port" > "$build/port.log" 2>&1 || {
        echo "FAIL: the port probe did not link - a name the port does not define is a link error"
        head -10 "$build/port.log"
        exit 1
    }
set +e; "$build/port" > "$build/port.table" 2> "$build/port.stderr"; port_status=$?; set -e

# 3. neither table may be smaller than the claim, or the diff compares less than it says
for side in host port; do
    rows=$(grep -c ' = ' "$build/$side.table" || true)
    if [ "$rows" -ne "$expected" ]; then
        echo "FAIL: the $side table has $rows rows and this slice claims $expected, so the diff below"
        echo "      would compare something smaller than the claim"
        exit 1
    fi
done

# 4. the diff
if diff -u "$build/host.table" "$build/port.table" > "$build/diff.log" 2>&1; then
    if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
        echo "FAIL: the mutant left the tables equal, so this check cannot fail and proves nothing"
        exit 1
    fi
    if [ "$mutant" != 0 ] && [ "$control" != 0 ]; then
        echo "ok  the control is green: the unmutated source through the identical build-and-run path"
    else
        echo "ok  the port's $expected constants answer exactly what Apple's do, text and bytes both"
    fi
    echo "log=$build"
    exit 0
fi
if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    echo "ok  the mutant went red, on this row and no other:"
    sed -n '1,40p' "$build/diff.log"
    echo "log=$build"
    exit 0
fi
echo "FAIL: the port's table differs from the host's"
cat "$build/diff.log"
exit 1
