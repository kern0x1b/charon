#!/bin/sh
# values.sh — the host oracle for PHASE's spatial-audio value types, with the port's own classes in
# the same binary.
#
# Two halves, and the second is the one that can fail:
#
#   the host half asks the host's own PHASE.framework for the documented defaults of a *fresh* object
#   of each class - not a value set and read back, which was never a measurement of a default;
#
#   the port half compiles the port's own PHASEValueTypes15.m with its class names renamed, so
#   charon_host_PHASECardioidDirectivityModelSubbandParameters sits beside Apple's in one binary, and
#   holds a fresh port object to the same eight numbers the host's fresh object answers. A default the
#   port gets wrong is then a difference, not a comment.
#
# A class the host does not carry is reported and skipped; the run fails outright if the host has no
# PHASE at all, so nothing passes vacuously.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${PHASE_ROOT:-$(cd "$here/../../../.." && pwd)}
AVFAUDIO="$root/packages/a/apple-backports/AVFAudio"
build=${PHASE_VALUES_BUILD:-${TMPDIR:-/tmp}/charon-phase-values}
rm -rf "$build"
mkdir -p "$build"

# Every class the port's PHASE source defines, renamed. The list is written out rather than derived: a
# derived one spans the whole folder and renames classes this binary does not compile.
renames=""
for name in PHASENumericPair PHASEDistanceModelParameters PHASEDistanceModelFadeOutParameters \
             PHASEGeometricSpreadingDistanceModelParameters PHASEDirectivityModelParameters \
             PHASECardioidDirectivityModelSubbandParameters PHASEConeDirectivityModelSubbandParameters \
             PHASECardioidDirectivityModelParameters PHASEConeDirectivityModelParameters PHASEEngine
do
    renames="$renames -D$name=charon_host_$name"
done

# One -c and one -o per source: a single -c with two inputs and one -o is rejected, which is what
# this did the first time.
port_objects=""
for source in "$AVFAUDIO/PHASEValueTypes15.m" "$AVFAUDIO/PHASEEngine15.m"; do
    name=$(basename "$source")
    # shellcheck disable=SC2086
    xcrun clang -fobjc-arc -w $renames -I"$AVFAUDIO" -I"$root/modules" \
        -c "$source" -o "$build/$name.o" 2> "$build/$name.err" || {
            echo "FAIL compiling $name"; head -6 "$build/$name.err"; exit 1; }
    port_objects="$port_objects $build/$name.o"
done

# shellcheck disable=SC2086
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations "$here/values.m" $port_objects \
    -framework Foundation -framework PHASE -o "$build/values" 2> "$build/link.err" || {
        echo "FAIL linking"; head -8 "$build/link.err"; exit 1; }

"$build/values" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
