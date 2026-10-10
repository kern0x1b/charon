#!/bin/sh
# The library's sources compiled for armv7 at the iOS 6.0 deployment target, syntax only, with -Wall -Werror, against each iPhoneOS
# SDK given: the SDK the port's package builds with and any newer one the port's API is checked against (26.2). A source that
# stops compiling for the device stops here, and the header needs no flag from the build for either SDK: the version an SDK
# gives itself decides what CharonCoreMIDI.h declares.
# Usage: sh syntax.sh <iPhoneOS.sdk> [<iPhoneOS.sdk> ...]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
CORE=${COREMIDI:-$here/../../../../packages/a/apple-backports/CoreMIDI}
if [ $# -eq 0 ]; then
    echo "usage: sh syntax.sh <iPhoneOS.sdk> [<iPhoneOS.sdk> ...]" >&2
    exit 2
fi
failed=0
for sdk in "$@"; do
    for path in "$CORE"/*.m "$CORE"/*.c; do
        if ! xcrun clang -target armv7-apple-ios6.0 -isysroot "$sdk" -fobjc-arc -Wall -Werror -I"$CORE" -fsyntax-only "$path"; then
            echo "FAIL $(basename "$path") against $sdk" >&2
            failed=$((failed + 1))
        fi
    done
done
echo "syntax: $# SDK(s), failures $failed"
[ "$failed" -eq 0 ]
