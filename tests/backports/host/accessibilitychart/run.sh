#!/bin/sh
# accessibilitychart/run.sh - the chart and data classes of iOS 15.0 against the host's own
# Accessibility.framework.
#
# The system builds these nine classes as containers an assistive technology reads, and the port builds
# the same nine in Accessibility/CharonChartDescriptors.m. The check is: build the same tree in both
# and ask both the same questions, and the two answers must be the same.
#
# It runs on the host because the host has the framework - its SDK carries AXAudiograph.h, the very
# file the port's own SDK of 16.4 carries - and the two implementations are compiled into one program,
# the port's under names the system does not use, so neither can answer for the other. The port half
# links no Accessibility framework: its classes are its own.
#
# Three lines are expected to differ, and expected-differences.tsv writes out what each side answers on
# each of them and why. They are the three value-typed fields the host's own -copyWithZone: drops, which
# was measured and is in facts/Accessibility/Accessibility.md. Anything else that differs fails, and so
# does a declared difference that moves or disappears, so the file cannot go stale.
#
# Two things are not compared and the script says which, because a diff that pretends to cover them
# covers nothing:
#   * AXLiveAudioGraph publishes sound, and a program cannot read sound. What is held for it is the
#     shape of the class - its three class methods, its instance size, that it holds no state, and
#     that the calls raise nothing - which both sides can answer.
#   * its three class methods also leave one line in the port's log the first time each is used. A log
#     line is not a value either; the lines go to stderr and are kept beside this script's output.
#
# Usage: sh tests/backports/host/accessibilitychart/run.sh
#        ACCESSIBILITY_SRC=<dir>   build another copy of the port's sources (mutants.sh)
#        BUILD=<dir>               where the two programs and their output go
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
sources=${ACCESSIBILITY_SRC:-$root/packages/a/apple-backports/Accessibility}
build=${BUILD:-${TMPDIR:-/tmp}/charon-accessibilitychart}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
if [ ! -f "$sdk/System/Library/Frameworks/Accessibility.framework/Headers/AXAudiograph.h" ]; then
    echo "this host's SDK has no AXAudiograph, so the oracle is not here" >&2
    exit 2
fi
target=arm64-apple-macos26.0
common="-target $target -isysroot $sdk -fobjc-arc -O0 -Wall -Wno-nonnull -Wno-objc-protocol-property-synthesis"

# The port's own spelling of every class this case names, and of the two protocol names it looks up as
# strings. A -D renames the declaration as well, which is what keeps the two halves from colliding.
renames="-DAXChartDescriptor=CharonPortAXChartDescriptor
-DAXDataSeriesDescriptor=CharonPortAXDataSeriesDescriptor
-DAXDataPoint=CharonPortAXDataPoint
-DAXDataPointValue=CharonPortAXDataPointValue
-DAXNumericDataAxisDescriptor=CharonPortAXNumericDataAxisDescriptor
-DAXCategoricalDataAxisDescriptor=CharonPortAXCategoricalDataAxisDescriptor
-DAXLiveAudioGraph=CharonPortAXLiveAudioGraph
-DAXChart=CharonPortAXChart
-DAXDataAxisDescriptor=CharonPortAXDataAxisDescriptor
-DAXCHART_PROTOCOL=@\"CharonPortAXChart\"
-DAXDATAAXISDESCRIPTOR_PROTOCOL=@\"CharonPortAXDataAxisDescriptor\""

# The protocols' metadata is what lets a caller declare conformance, and in the port it comes from the
# object modules/apple/backports.lua generates out of the registry's implemented protocol rows. This is
# that object, written out so the case measures what the build emits, and both halves are given it:
# objc_getProtocol reads an image's protocol list, and a protocol no image in the program names is not
# in it. On the host the framework's own image does not name AXChart either - measured nil without a
# class adopting it, found with one - so a one-sided case would be comparing the port's generated
# object against the host's silence and calling it agreement.
cat > "$build/protocols.m" <<'PROTOCOLS'
#import <Foundation/Foundation.h>
#import <Accessibility/Accessibility.h>
static void charon_case_protocols(void) __attribute__((used));
static void charon_case_protocols(void)
{
    (void)@protocol(AXChart);
    (void)@protocol(AXDataAxisDescriptor);
}
PROTOCOLS

host_build() {
    xcrun clang $common "$here/cases.m" "$build/protocols.m" -framework Foundation \
        -framework Accessibility -framework CoreGraphics -o "$build/host" 2> "$build/host-build.log" || return 1
}
port_build() {
    # the renames are a list of -D flags and have to reach the shell unquoted
    # shellcheck disable=SC2086
    xcrun clang $common $renames "$here/cases.m" "$sources/CharonChartDescriptors.m" "$build/protocols.m" \
        -I"$root/packages/a/apple-backports" -framework Foundation -framework CoreGraphics \
        -o "$build/port" 2> "$build/port-build.log" || return 1
}
for half in host port; do
    if ! $half"_build"; then
        echo "the $half half did not build" >&2
        tail -20 "$build/$half-build.log" >&2
        exit 1
    fi
    "$build/$half" > "$build/$half.tsv" 2> "$build/$half.stderr" || {
        echo "the $half half did not run to its end" >&2
        tail -20 "$build/$half.stderr" >&2
        exit 1
    }
done

cases=$(wc -l < "$build/host.tsv" | tr -d ' ')
declared=$(( $(wc -l < "$here/expected-differences.tsv" | tr -d ' ') - 1 ))
echo "=== the two answers: $cases cases a side, $declared declared to differ"

python3 "$here/compare.py" "$build/host.tsv" "$build/port.tsv" "$here/expected-differences.tsv"
result=$?
if [ "$result" -ne 0 ]; then
    echo "the two answers do not match what this case declares"
    if ! diff -u "$build/host.tsv" "$build/port.tsv"; then
        # The whole diff, and not a summary of it: the point of printing it is that a reader can see
        # which case moved without re-running anything.
        :
    fi
    exit 1
fi
echo "identical on all $((cases - declared)) other cases: the system and the port answer the same"
echo "the port's own log lines, if any, are in $build/port.stderr"
