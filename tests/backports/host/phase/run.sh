#!/bin/sh
# values.sh — the host oracle for PHASE's spatial-audio value types.
#
# PHASE's own value types - the directivity and distance-model parameter classes and the pair of
# numbers - are the attenuation maths, and they are the classes a host differential can settle: the
# host's own PHASE.framework is the same framework, so each value it holds is an answer the port's
# can be held to. A class the host does not carry is reported as such and not skipped quietly, and
# the run is a failure if the host has no PHASE at all, so nothing passes vacuously.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=${PHASE_VALUES_BUILD:-${TMPDIR:-/tmp}/charon-phase-values}
rm -rf "$build"
mkdir -p "$build"
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations \
    "$here/values.m" -framework Foundation -framework PHASE -o "$build/values" 2> "$build/build.err" || {
        echo "FAIL building"; head -8 "$build/build.err"; exit 1; }
"$build/values" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
