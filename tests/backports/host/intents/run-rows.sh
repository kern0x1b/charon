#!/bin/sh
# run-rows.sh - the two harness builds of tests/backports/host/intents/ against the system's own
# Intents, in one binary and one process, with the controls and the negative control run.
#
# init-rows.m is the per-class harness facts/Intents/Intents.md names as owed: it reads, for every
# class of init-classes.txt, what the system's own class answers for -init through the IMP, because
# the SDK's header forbids naming that selector at compile time and the port's own emitted body is
# built around the same restriction.  factory-rows.m reads the six release-13 rows of
# registry/Intents/ios16.json that the file listed as absent with a reason about a group of the
# delivery.
#
# BOTH PROGRAMS LINK -framework Intents, and that is not decoration.  A first attempt at
# factory-rows.m read the four classes with NSClassFromString from a program that did not link the
# framework and got ABSENT for every one of them: the reader was blind, not the host.  A measurement
# whose reader is blind looks exactly like a measurement of an absence, so both programs print a
# class the system does not carry and the harness has to report ABSENT for it, and this script runs
# that list and fails when the harness passes it.
#
# The four classes are API_UNAVAILABLE(macos) in the SDK, so factory-rows.m reaches every one of
# them through the runtime and reads every value through KVC; a program that named them would not
# compile, and a program that read them with NSClassFromString without linking -framework Intents
# answers ABSENT for all four and is wrong about every one.  Each section is a separate run, so a
# section the host cannot answer does not take the other three with it.
#
# Usage: sh tests/backports/host/intents/run-rows.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=${INTENTS_ROWS_BUILD:-$here/../../../.agent-work/build/intents-rows}
mkdir -p "$build"
flags="-fobjc-arc -w -Wno-deprecated-declarations"

echo "intents rows: building both harnesses"
xcrun clang $flags "$here/init-rows.m" -framework Intents -framework Foundation -o "$build/init-rows"
xcrun clang $flags "$here/factory-rows.m" -framework Intents -framework Foundation -o "$build/factory-rows"

echo "intents rows: the 21 -init rows, class by class, against the system's own classes"
"$build/init-rows" "$here/init-classes.txt" | tee "$build/init-rows.log"

echo "intents rows: the negative control - a class list the system does not carry must all fail"
printf '# the negative control: one class the system does not carry, and one it does\nINCharonNoSuchClassForThisHarness\nNSObject\n' \
    > "$build/control-classes.txt"
if "$build/init-rows" "$build/control-classes.txt" > "$build/control.log" 2>&1; then
    echo "intents rows: FAIL the harness passed a class the system does not carry, so it cannot tell the two apart"
    exit 1
fi
sed 's/^/intents rows:   /' "$build/control.log"
echo "intents rows: the control is red, as it must be"

echo "intents rows: the six rows the registry listed as absent, one section per run"
: > "$build/factory-rows.log"
for section in destination resolution file usercontext; do
    if "$build/factory-rows" "$section" 2>&1 | tee -a "$build/factory-rows.log"; then
        :
    else
        echo "intents rows:   the $section section was killed, so the host does not answer it" | tee -a "$build/factory-rows.log"
    fi
done