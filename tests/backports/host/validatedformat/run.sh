#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
build=${VALIDATEDFORMAT_BUILD:-${TMPDIR:-/tmp}/charon-validatedformat-host}
rm -rf "$build"
mkdir -p "$build"
xcrun clang -fobjc-arc -w "-DCHARON_VALIDATED_FORMAT=\"$FOUNDATION/NSString+ValidatedFormat.m\"" "$here/fuzz.m" -framework Foundation -o "$build/fuzz"
"$build/fuzz" "${1:-20000}"
