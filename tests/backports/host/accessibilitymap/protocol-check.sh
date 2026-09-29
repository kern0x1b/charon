#!/bin/sh
# protocol-check.sh - build and run the real-name protocol check, with the port's objects and the
# protocol object the build generates, under the names an application writes.
#
# The generated object is written by modules/apple/backports.lua's protocol_sources() from the
# registry's implemented protocol rows, exactly as the build writes it, so what is linked here is what
# the library ships.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
sources=${ACCESSIBILITY_SRC:-$root/packages/a/apple-backports/Accessibility}
build=${PROTOCOL_BUILD:-${TMPDIR:-/tmp}/charon-accessibilitymap-protocol}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
# The protocol source, written here as the build writes it: one @protocol() per implemented protocol row
# of this library. It is a copy of the name rather than a run of the build's generator, and that is a
# limitation this check has and says so - a registry row that named a protocol which does not exist
# would not turn it red, because the name it asks about comes from this file. What the check does hold is
# that the port's own protocol resolves by the name an application writes, in a binary that links the
# port's objects and this object, with a control that answers nil for a name that does not exist.
cat > "$build/protocols.m" <<'PROTOCOLS'
#import <Foundation/Foundation.h>
#import <Accessibility/Accessibility.h>
static void charon_case_protocols(void) __attribute__((used));
static void charon_case_protocols(void)
{
    (void)@protocol(AXBrailleMapRenderer);
}
PROTOCOLS
xcrun clang -target arm64-apple-macos26.0 -isysroot "$sdk" -fobjc-arc -O0 -Wall -Wno-nonnull \
    -include "$sources/CharonBrailleMap.h" \
    "$here/protocol-check.m" "$sources/CharonBrailleMap.m" "$build/protocols.m" \
    -I"$root/packages/a/apple-backports" -I"$sources" \
    -framework Foundation -framework CoreGraphics -o "$build/protocol" 2> "$build/build.log" || {
        echo "the protocol check did not build" >&2
        tail -20 "$build/build.log" >&2
        exit 1
    }
"$build/protocol"
