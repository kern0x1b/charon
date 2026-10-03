#!/bin/sh
# run.sh -- the AVFoundation constants the port carries, the port against the host, in one binary.
#
# One program. probe.m is compiled plain, so every BARE name in it is Apple's own symbol; the port's
# five AVFoundationGlobals*.m are compiled with every constant name defined to its `charon_host_`
# spelling and linked beside it, so the PREFIXED name is the port's own definition of the same
# constant. One process then reads both and prints them side by side, and the join below is a
# comparison of the two columns of one run rather than of two runs that could have drifted.
#
# A value the port invented cannot agree with the host's, which is the whole point: these are 116
# constants whose value is a fact about Apple's own image, and "a constant with an invented value" is a
# silent fake the tree forbids.
#
# Run DIRECTLY, not through heavy.sh: this is five small compiles and one run, and heavy.sh's job is the
# package builds.
#
# What makes it a check rather than a comparison:
#
#   * the names are READ from the port's own sources, never typed here, so the check cannot drift away
#     from what the port defines, and a name a source defines that the check does not ask about is
#     reported;
#   * the row count is DERIVED from the run ("names read: N rows: M") and compared against what the
#     sources hold, so an empty table is a red and not a clean diff of two empty files;
#   * the probe prints four controls and this script requires each to be what it must be, so a run that
#     loaded nothing cannot pass;
#   * the harness is PLANTED and the plant must go red: one value in one source is changed, and the run
#     must notice it. A check that cannot fail proves nothing. CONTROL=1 puts the unmutated sources
#     through the identical path and must stay clean, so a red is the mutation and not the path;
#   * a mutation that does not build is RUN FAILED with the compiler's own lines, so a build failure is
#     never counted as a noticed mutation.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
control=${CONTROL:-0}
mutant=${AVFGLOBALSMUTANT:-0}
build=${AVF_GLOBALS_BUILD:-$root/.agent-work/avf-globals-build}
rm -rf "$build"
mkdir -p "$build/src" "$build/o"

sources=$(cd "$avf" && ls AVFoundationGlobals*.m)
[ -n "$sources" ] || { echo "FAIL: no AVFoundationGlobals*.m under $avf, so there is nothing to check"; exit 1; }

# THE NAMES COME FROM THE SOURCES. Every `NSString *const <name> = ` line the five objects hold, read
# with grep, and nothing is typed into this script: a typed list of 116 names is a list that goes stale
# the moment a row is added, and the reviewer's first finding on a sibling harness was a file that
# contradicted itself over exactly that.
: > "$build/names.txt"
for source in $sources; do
    grep -o '^NSString \*const [A-Za-z_][A-Za-z0-9_]*' "$avf/$source" \
        | sed 's/^NSString \*const //' >> "$build/names.txt"
done
sort -u "$build/names.txt" > "$build/names.sorted"
mv "$build/names.sorted" "$build/names.txt"
declared=$(wc -l < "$build/names.txt" | tr -d ' ')
[ "$declared" -gt 0 ] || { echo "FAIL: no constant name was read from the port's sources"; exit 1; }
echo "the port's own sources declare $declared constants"

if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    # One value, one source, and the replacement is a string of the same shape that cannot be the
    # host's. Applied to a COPY, so the tree is never perturbed.
    echo "the mutation is applied to the renamed copy below, after the copy is made"
fi

# THE PORT'S DEFINITIONS ARE RENAMED IN THE COPY, NOT WITH -D. A -D macro renames every occurrence of
# the name, and on this host the macOS SDK's own AVFoundation headers DECLARE many of these constants
# (AVCaptureReactions.h:43 declares AVCaptureReactionTypeBalloons among them), so the macro renames the
# SDK's declaration too and the compile stops with "redefinition of charon_host_AVCaptureReactionTypeBalloons
# with a different type". What has to be renamed is the port's DEFINITION and nothing else, so the copy is
# rewritten textually on the `NSString *const <name> =` line and the import is left exactly as it was.
# pass 1: the renamed copy of every source, so the mutation below has all of them on disk whatever
# order they are listed in. It used to run inside the compile loop, and on the first source - which is
# not the mutated one - it stopped with FileNotFoundError, so the mutation could never fire and the
# mutant run proved nothing.
for source in $sources; do
    sed -E 's/^NSString \*const ([A-Za-z_][A-Za-z0-9_]*) =/NSString *const charon_host_\1 =/' \
        "$avf/$source" > "$build/src/$source"
done

if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    [ -f "$build/src/AVFoundationGlobals260.m" ] || {
        echo "FAIL: the mutation target's copy is not there, so this run proves nothing"; exit 1; }
    python3 - "$build/src/AVFoundationGlobals260.m" <<'PERTURB'
import sys
path = sys.argv[1]
text = open(path).read()
# One value, in the RENAMED copy, so the plant changes what the port holds and nothing else.
before = 'NSString *const charon_host_AVFileTypeDICOM = @"org.nema.dicom";'
after = 'NSString *const charon_host_AVFileTypeDICOM = @"org.nema.dicom.PLANTED";'
if text.count(before) != 1:
    raise SystemExit("the mutation target is not unique (%d matches), so this run proves nothing"
                     % text.count(before))
out = text.replace(before, after)
if out.count(before) != 0 or out.count(after) != 1:
    raise SystemExit("the mutation did not take, so this run proves nothing")
open(path, "w").write(out)
print("# the mutation applied: one value in one source, changed and gone afterwards")
PERTURB
fi

# pass 2: compile them.
objects=""
for source in $sources; do
    # shellcheck disable=SC2086
    if ! xcrun clang -fobjc-arc -w -I"$avf" -c "$build/src/$source" -o "$build/o/$source.o" \
            > "$build/o/$source.log" 2>&1; then
        echo "RUN FAILED: the port's $source did not build - a build failure is never a noticed mutation"
        head -8 "$build/o/$source.log"
        exit 1
    fi
    objects="$objects $build/o/$source.o"
done

# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w "$here/probe.m" $objects -framework Foundation -framework CoreFoundation \
    -o "$build/probe" > "$build/probe.log" 2>&1 || {
        echo "FAIL: the probe did not link or build"; head -12 "$build/probe.log"; exit 1; }
"$build/probe" "$build/names.txt" > "$build/table" 2> "$build/probe.stderr" || {
    echo "FAIL: the probe did not run"; head -10 "$build/probe.stderr"; exit 1; }

# 1. the controls, each of them named, so a run that loaded nothing cannot pass
check_control() {
    # cut -f3, not ${line#*TAB}: the shell's own parameter expansion cannot be relied on to carry a
    # literal tab out of a heredoc-written script, and when it did not the control compared the name
    # against "expected HAS" and stopped on a green run.
    line=$(grep "^CONTROL	$1	" "$build/table" | cut -f3 || true)
    case "$line" in
        "") echo "FAIL: control $1 printed nothing, so the run examined nothing"; exit 1 ;;
    esac
    value=$line
    if [ "$2" = "LACKS" ]; then
        [ "$value" = "LACKS" ] || { echo "FAIL: control $1 answered [$value], expected LACKS"; exit 1; }
    else
        case "$value" in
            HAS*|STR*|NUM*) : ;;
            *) echo "FAIL: control $1 answered [$value], expected HAS"; exit 1 ;;
        esac
    fi
    echo "ok  control $1 = $value"
}
check_control AVMediaTypeVideo HAS
check_control AVMediaTypeDepthData HAS
check_control AVMediaTypeCharonProbeNoSuchConstant LACKS
check_control AVPlayer HAS

# 2. the row count the probe reports must be the number the sources declare
read=$(sed -n 's/^names read: \([0-9][0-9]*\)  rows: \([0-9][0-9]*\).*/\1 \2/p' "$build/table" | tail -1)
set -- $read
if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "FAIL: the probe did not report 'names read: N  rows: M', so the row count cannot be checked"
    echo "      against the run's own output. Refusing to guess it from a literal."
    exit 1
fi
if [ "$1" != "$declared" ] || [ "$2" != "$declared" ]; then
    echo "FAIL: the port's sources declare $declared constants, the probe read $1 and emitted $2 rows,"
    echo "      so this run would compare something smaller than the claim"
    exit 1
fi
echo "ok  $declared constants declared, $1 names read, $2 rows emitted"

# 3. the join. One row per name, and the two columns must be equal. A row whose PORT column is LACKS is
#    a defect the join names: the port does not define a constant it declares.
# TAB separated, read with IFS set to the tab alone, because a value is "STR <the string>" and carries
# spaces of its own. Splitting the row on spaces gave this join 60 DIFFERS rows for 116 constants that all
# agreed, and it would have done the same to a genuine difference.
differs=0
port_lacks=0
compared=0
: > "$build/diff.log"
grep -v '^CONTROL	' "$build/table" | grep -v '^names read: ' | \
while IFS=$(printf '\t') read -r name host port; do
    case "$host" in
        LACKS)
            echo "HOST-LACKS	$name	the host does not export it at all, so there is no value to compare" \
                >> "$build/diff.log"
            continue ;;
    esac
    case "$port" in
        LACKS)
            echo "PORT-LACKS	$name	the port declares it and this check cannot see its definition" \
                >> "$build/diff.log"
            continue ;;
    esac
    if [ "$host" != "$port" ]; then
        echo "DIFFERS	$name	host=[$host] port=[$port]" >> "$build/diff.log"
    fi
done
differs=$(grep -c '^DIFFERS	' "$build/diff.log" || true)
port_lacks=$(grep -c '^PORT-LACKS	' "$build/diff.log" || true)
compared=$(grep -c '	host=\|	STR \|	NUM ' "$build/diff.log" || true)
agreed=$((declared - differs - port_lacks))
echo "the join compared $agreed rows that agree and $differs that differ"
[ "$port_lacks" = 0 ] || { cat "$build/diff.log"; echo "FAIL: $port_lacks port-side definitions were not found"; exit 1; }

if [ "$mutant" != 0 ] && [ "$control" = 0 ]; then
    if [ "$differs" = 0 ]; then
        echo "FAIL: the mutation left every value equal, so this check cannot fail and proves nothing"
        exit 1
    fi
    echo "ok  the mutation was noticed, on $differs row(s):"
    sed -n '1,12p' "$build/diff.log"
    exit 0
fi
if [ "$mutant" != 0 ] && [ "$control" != 0 ]; then
    if [ "$differs" != 0 ]; then
        echo "FAIL: the control is not clean: the unmutated sources through the identical path still"
        echo "      differ on $differs row(s), so the red is the path and not the mutation"
        exit 1
    fi
    echo "ok  the control is clean: the unmutated sources through the identical build-and-run path"
    exit 0
fi

if [ "$differs" != 0 ]; then
    echo "FAIL: the port's value differs from the host's on $differs of $declared constants"
    sed -n '1,24p' "$build/diff.log"
    exit 1
fi
if [ -s "$build/diff.log" ]; then
    echo "note: the host does not export these, so they have no value to compare:"
    cat "$build/diff.log"
fi
echo "ok  every one of the $declared constants the port defines holds the value the host's own symbol holds"
log=$build
exit 0