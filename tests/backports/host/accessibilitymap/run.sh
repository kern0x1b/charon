#!/bin/sh
# accessibilitymap/run.sh - AXBrailleMap against the host's own Accessibility.framework.
#
# The system builds this class as the pin state of a braille display, and the port builds the same class
# in Accessibility/CharonBrailleMap.m. The check is: build the same tree in both and ask both the same
# questions, and the two answers must be the same.
#
# The map comes out of NSClassFromString and alloc on both sides because the header marks -init and +new
# unavailable, so a program that compiled `[[AXBrailleMap alloc] init]` would not build. The host half's
# map is the one its braille service would have made, and the port half's is a fresh one, and the two
# have to answer alike for a zero-sized map that accepts pins - which is what every case here asks.
#
# One question is not asked of the system, because the system cannot be asked it: how a map of a given
# size behaves. The header gives no way to make one, so the port adds `+charon_mapWithDimensions:` and
# factory-probe.m checks that, building the port half alone. Nothing is compared about what
# -presentImage: shows, because a program cannot read a display.
#
# Usage: sh tests/backports/host/accessibilitymap/run.sh
#        ACCESSIBILITY_SRC=<dir>   build another copy of the port's sources (mutants.sh)
#        BUILD=<dir>               where the two programs and their output go
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
sources=${ACCESSIBILITY_SRC:-$root/packages/a/apple-backports/Accessibility}
build=${BUILD:-${TMPDIR:-/tmp}/charon-accessibilitymap}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
if [ ! -f "$sdk/System/Library/Frameworks/Accessibility.framework/Headers/AXBrailleMap.h" ]; then
    echo "this host's SDK has no AXBrailleMap, so the oracle is not here" >&2
    exit 2
fi
target=arm64-apple-macos26.0
common="-target $target -isysroot $sdk -fobjc-arc -O0 -Wall -Wno-nonnull -Wno-objc-protocol-property-synthesis"

# The port's own spelling of the class, and of the name the case looks it up by. A -D renames the
# declaration as well, which is what keeps the two halves from colliding.
renames="-DAXBrailleMap=CharonPortAXBrailleMap
-DAXBrailleMapRenderer=CharonPortAXBrailleMapRenderer
-DAXBRAILLEMAP_CLASS=@\"CharonPortAXBrailleMap\""

# The protocol's metadata is what lets a caller declare conformance, and in the port it comes from the
# object modules/apple/backports.lua generates out of the registry's implemented protocol rows. The host
# half is not given it: the system's own framework names this protocol in its protocol list - measured,
# `objc_getProtocol("AXBrailleMapRenderer")` answers found on the host without anything of the case's -
# and the port half is, because that object is part of what the port ships.
cat > "$build/protocols.m" <<'PROTOCOLS'
#import <Foundation/Foundation.h>
#import <Accessibility/Accessibility.h>
static void charon_case_protocols(void) __attribute__((used));
static void charon_case_protocols(void)
{
    (void)@protocol(AXBrailleMapRenderer);
}
PROTOCOLS

host_build() {
    xcrun clang $common "$here/cases.m" -framework Foundation -framework Accessibility \
        -framework CoreGraphics -o "$build/host" 2> "$build/host-build.log" || return 1
}
port_build() {
    # the renames are a list of -D flags and have to reach the shell unquoted
    # shellcheck disable=SC2086
    xcrun clang $common $renames "$here/cases.m" "$sources/CharonBrailleMap.m" "$build/protocols.m" \
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
echo "=== the two answers: $cases cases a side"
if python3 "$here/../common/compare.py" "$build/host.tsv" "$build/port.tsv" "$here/expected-differences.tsv"; then
    # The image: the host writes no such line, because the system's method shows a picture on a display
    # and says nothing. The port does, and says it once.
    lines=$(awk '/AXBrailleMap -presentImage:/ {n++} END {print n+0}' "$build/port.stderr")
    if [ "$lines" -ne 1 ]; then
        echo "the port wrote $lines lines for -presentImage:, and the case called it once: a member that does nothing says so once"
        exit 1
    fi
    echo "say-once: -presentImage: called once, $lines line in the port's log"
    echo "identical on all $cases cases: the system and the port answer the same"

    # The factory, which only the port has, checked on its own and not against the system.
    if ACCESSIBILITY_SRC="$sources" FACTORY_BUILD="$build/factory" sh "$here/factory-probe.sh" > "$build/factory.log" 2>&1; then
        sed 's/^/factory: /' "$build/factory.log"
    else
        echo "the factory probe did not pass:" >&2
        cat "$build/factory.log" >&2
        exit 1
    fi
    exit 0
fi
echo "the two answers do not match what this case declares"
if ! diff -u "$build/host.tsv" "$build/port.tsv"; then
    :
fi
exit 1
