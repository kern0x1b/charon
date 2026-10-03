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
# WHICH MUTATION, because one variable drove both phases and the first phase reported its verdict and
# exited before the second was ever reached: AVFGLOBALSMUTANT=function planted the returned string and
# then the constant plant fired first and the run stopped. So the value names the target.
mutant=${AVFGLOBALSMUTANT:-0}
kind=constant
[ "$mutant" = function ] && kind=function
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

if [ "$mutant" != 0 ] && [ "$control" = 0 ] && [ "$kind" = constant ]; then
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

if [ "$mutant" != 0 ] && [ "$control" = 0 ] && [ "$kind" = constant ]; then
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

if [ "$mutant" != 0 ] && [ "$control" = 0 ] && [ "$kind" = constant ]; then
    if [ "$differs" = 0 ]; then
        echo "FAIL: the mutation left every value equal, so this check cannot fail and proves nothing"
        exit 1
    fi
    echo "ok  the mutation was noticed, on $differs row(s):"
    sed -n '1,12p' "$build/diff.log"
    exit 0
fi
# A function mutation still has to get through phase one, and phase one is then an ordinary run: it must
# be clean, or the function verdict below would be read on a tree whose constants are already wrong.
if [ "$mutant" != 0 ] && [ "$control" = 0 ] && [ "$kind" = function ]; then
    if [ "$differs" != 0 ]; then
        echo "FAIL: the constants differ on $differs row(s) before the function mutation is even applied"
        sed -n '1,12p' "$build/diff.log"
        exit 1
    fi
    echo "ok  the constants are clean, so the function mutation below is the only thing that can go red"
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

# ---------------------------------------------------------------------------------------------
# The four FUNCTIONS, the same way: the port's object compiled with each name defined to its
# charon_host_ spelling, linked beside a probe that calls Apple's own symbol and the port's, and the two
# answers printed side by side. The three caption constructors return a struct of two fields out of two
# arguments, so the comparison is over field values; the reaction lookup is compared for every type the
# port carries and for one it does not, where the host's own answer is measured too.
# ---------------------------------------------------------------------------------------------
fsource=AVFoundationFunctions180.m
[ -f "$avf/$fsource" ] || {
    echo "FAIL: $avf/$fsource does not exist, so the functions this run checks for are not there"
    exit 1
}
# The DEFINITION, wherever the return type leaves it: the three constructors start a line with their
# return type in front of the name and the reaction lookup starts its line with `NSString *`. Anchoring
# on `^NAME(` found none of the four, which is why the count check below first said 0.
fnames=$(grep -o '\(AVCaptionDimensionMake\|AVCaptionPointMake\|AVCaptionSizeMake\|AVCaptureReactionSystemImageNameForType\)(' \
    "$avf/$fsource" | sed 's/($//' | sort -u)
fn=$(printf '%s\n' "$fnames" | grep -c . || true)
[ "$fn" = 4 ] || {
    echo "FAIL: $fsource defines $fn of the four functions this check asks about, so this run would"
    echo "      compare something smaller than the claim"
    exit 1
}
echo "the port's $fsource defines $fn functions"

# Two renames in this copy, and both are needed and neither is a wildcard:
#   - the four function DEFINITIONS, so the port's answer is reachable under a prefixed name;
#   - the eight reaction-type CONSTANTS the lookup compares against, so it is asked with the port's own
#     carried strings rather than Apple's. Anchored on `isEqualToString:` on purpose: a plain
#     `AVCaptureReactionType` pattern also matches the parameter's TYPE in `NSString *f(AVCaptureReactionType
#     reactionType)` and on `NSString *` the compiler is right and the link is wrong.
# The four names are replaced WHEREVER they appear, not anchored at the start of a line: the three
# constructors are written `AVCaptionDimension AVCaptionDimensionMake(...)` and the lookup
# `NSString *AVCaptureReactionSystemImageNameForType(...)`, so neither has its name at column 0. An
# anchored pattern renamed NOTHING, the four symbols then resolved against the linked AVFoundation, every
# `charon_host_` pointer stayed NULL, and the probe segfaulted on the first call - a green-looking run
# that had compared nothing.
sed -E -e 's/(AVCaptionDimensionMake|AVCaptionPointMake|AVCaptionSizeMake|AVCaptureReactionSystemImageNameForType)\(/charon_host_\1(/g' \
       -e 's/isEqualToString:AVCaptureReactionType/isEqualToString:charon_host_AVCaptureReactionType/' \
    "$avf/$fsource" > "$build/src/$fsource.fn"
for name in AVCaptionDimensionMake AVCaptionPointMake AVCaptionSizeMake AVCaptureReactionSystemImageNameForType; do
    grep -q "charon_host_$name(" "$build/src/$fsource.fn" || {
        echo "FAIL: the copy of $fsource does not define charon_host_$name, so the probe would call a NULL"
        echo "      pointer and this run would prove nothing"
        exit 1
    }
done
# The rename has to have landed on all of them, or the port's lookup is silently comparing against
# something this copy never renamed and the link error below is the only thing that would say so.
for name in Balloons Confetti Fireworks Heart Lasers Rain ThumbsUp ThumbsDown; do
    grep -q "charon_host_AVCaptureReactionType$name" "$build/src/$fsource.fn" || {
        echo "FAIL: the copy of $fsource does not reference charon_host_AVCaptureReactionType$name, so the"
        echo "      lookup would compare against a symbol this build does not provide"
        exit 1
    }
done
if [ "$mutant" != 0 ] && [ "$control" = 0 ] && [ "$kind" = function ]; then
    python3 - "$build/src/$fsource.fn" <<'PERTURB'
import sys
path = sys.argv[1]
text = open(path).read()
# ONE returned string, so the plant changes what the port answers and nothing about its shape.
before = 'return @"heart.fill";'
after = 'return @"heart.PLANTED";'
if text.count(before) != 1:
    raise SystemExit("the mutation target is not unique (%d matches), so this run proves nothing"
                     % text.count(before))
out = text.replace(before, after)
if out.count(before) != 0 or out.count(after) != 1:
    raise SystemExit("the mutation did not take, so this run proves nothing")
open(path, "w").write(out)
print("# the mutation applied: one returned string in one function, changed and gone afterwards")
PERTURB
fi
# -x objective-c, because the copy is named .fn: clang's driver does not recognise that suffix, takes
# it for something to LINK, and with -c it exits 0 having written nothing at all - no error, no log line,
# no object. The next step then fails with "no such file or directory" and names the wrong thing.
if ! xcrun clang -fobjc-arc -w -x objective-c -include "$here/renamed.h" -I"$avf" \
        -c "$build/src/$fsource.fn" -o "$build/o/functions.o" \
        > "$build/o/functions.log" 2>&1; then
    echo "RUN FAILED: the port's $fsource did not build - a build failure is never a noticed mutation"
    head -8 "$build/o/functions.log"
    exit 1
fi
# The reaction TYPE constants the lookup compares against live in another object, so they are linked in
# beside it. Both objects are the 18.0 band - measured by tools/symbol-first-release.lua, not assumed - so
# neither is ever left out of a band the other is in.
#
# And that object needs the same DEFINITION-ONLY rename the five needed in phase one, for a new reason:
# this host's own macOS SDK DOES declare AVCaptureReactionTypeBalloons and its seven siblings
# (MacOSX.sdk/.../AVCaptureReactions.h:43), so an unrenamed copy collides with Apple's declaration -
# "redefinition of 'AVCaptureReactionTypeBalloons' with a different type". The probe reads the BARE name
# for the type it passes in, which is Apple's own symbol and the same string either way, so the port's
# lookup is still asked about the value it will really be asked about.
globals180="$avf/AVFoundationGlobals180.m"
sed -E 's/^NSString \*const ([A-Za-z_][A-Za-z0-9_]*) =/NSString *const charon_host_\1 =/' \
    "$globals180" > "$build/src/globals180.fn"
if ! xcrun clang -fobjc-arc -w -x objective-c -I"$avf" -c "$build/src/globals180.fn" -o "$build/o/globals180.o" \
        > "$build/o/globals180.log" 2>&1; then
    echo "RUN FAILED: the port's AVFoundationGlobals180.m did not build"
    head -8 "$build/o/globals180.log"
    exit 1
fi
if ! xcrun clang -fobjc-arc -w "$here/functions.m" "$build/o/functions.o" "$build/o/globals180.o" \
        -framework Foundation -framework CoreMedia -framework CoreGraphics -framework AVFoundation \
        -o "$build/functions" > "$build/functions.log" 2>&1; then
    echo "FAIL: the functions probe did not build"; head -12 "$build/functions.log"; exit 1
fi
for object in functions.o globals180.o; do
    [ -f "$build/o/$object" ] || {
        echo "FAIL: the compile of $object reported success and wrote no object, so the link below would"
        echo "      have measured nothing. Refusing to go on."
        exit 1
    }
done
"$build/functions" > "$build/functions.table" 2> "$build/functions.stderr" || {
    echo "FAIL: the functions probe did not run"; head -10 "$build/functions.stderr"; exit 1; }

fline=$(grep "^CONTROL	AVCaptionNoSuchConstructor	" "$build/functions.table" | cut -f3 || true)
[ "$fline" = "LACKS" ] || { echo "FAIL: the planted-function control answered [$fline], expected LACKS"; exit 1; }
echo "ok  control AVCaptionNoSuchConstructor = $fline"
fline=$(grep "^CONTROL	AVCaption	" "$build/functions.table" | cut -f3 || true)
case "$fline" in HAS*) : ;; *) echo "FAIL: the AVCaption control answered [$fline], expected HAS"; exit 1 ;; esac
echo "ok  control AVCaption = $fline"
# The arithmetic control: 0 and 2 are the only answer 0 percent can have, so a probe returning anything
# else has not run the port's function at all.
fline=$(grep "^CONTROL	AVCaptionDimensionMake(0,Percent)	" "$build/functions.table" | cut -f3 || true)
[ "$fline" = "0/2 0/2" ] || { echo "FAIL: the arithmetic control answered [$fline], expected 0/2 0/2"; exit 1; }
echo "ok  control AVCaptionDimensionMake(0,Percent) port and host = $fline"

frows=$(grep -c '	same$' "$build/functions.table" || true)
fdiffers=$(grep -c '	DIFFERENT$' "$build/functions.table" || true)
react=$(grep -c '^AVCaptureReactionType' "$build/functions.table" || true)
reactdiffers=$(grep '^AVCaptureReactionType' "$build/functions.table" | grep -vc 'host=\[\(.*\)\]	port=\[\1\]$' || true)
planted=$(grep "^PLANTED-TYPE	" "$build/functions.table" | cut -f2,3 || true)

if [ "$mutant" != 0 ] && [ "$control" = 0 ] && [ "$kind" = function ]; then
    if [ "$fdiffers" = 0 ] && [ "$reactdiffers" = 0 ]; then
        echo "FAIL: the mutation left every function answer equal, so this check cannot fail and proves nothing"
        exit 1
    fi
    echo "ok  the mutation was noticed: $fdiffers struct row(s) and $reactdiffers reaction row(s) differ"
    grep '	DIFFERENT$' "$build/functions.table" | head -4
    grep '^AVCaptureReactionType' "$build/functions.table" | grep -v 'host=\[\(.*\)\]	port=\[\1\]$' | head -4
    exit 0
fi
if [ "$mutant" != 0 ] && [ "$control" != 0 ]; then
    if [ "$fdiffers" != 0 ] || [ "$reactdiffers" != 0 ]; then
        echo "FAIL: the control is not clean: $fdiffers struct row(s) and $reactdiffers reaction row(s) differ"
        echo "      through the identical path, so the red would be the path and not the mutation"
        exit 1
    fi
    echo "ok  the control is clean: the unmutated function through the identical build-and-run path"
    exit 0
fi

if [ "$fdiffers" != 0 ] || [ "$reactdiffers" != 0 ]; then
    echo "FAIL: the port's function answers differ from the host's on $fdiffers struct row(s) and $reactdiffers reaction row(s)"
    grep '	DIFFERENT$' "$build/functions.table" | head -12
    grep '^AVCaptureReactionType' "$build/functions.table" | grep -v 'host=\[\(.*\)\]	port=\[\1\]$' | head -12
    exit 1
fi
echo "ok  $frows struct rows agree with the host and $react reaction types answer the same string"
echo "note: the type the port does not carry, measured on both sides: $planted"
log=$build
exit 0