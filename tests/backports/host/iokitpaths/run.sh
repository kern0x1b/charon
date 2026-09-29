#!/bin/sh
# run.sh - the port's IORegistryEntryCopyFromPath, IORegistryEntryCopyPath, IOMainPort and
# kIOMainPortDefault (renamed charonHost_*) against the host's own IOKit, asked the same questions.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/IOKit}
harness=${IOKITPATHS_HARNESS:-$here/../../device}
build=${IOKITPATHS_BUILD:-$(mktemp -d)}
rm -rf "$build"
mkdir -p "$build"
renames="-DIORegistryEntryCopyFromPath=charonHost_IORegistryEntryCopyFromPath
-DIORegistryEntryCopyPath=charonHost_IORegistryEntryCopyPath
-DIOMainPort=charonHost_IOMainPort
-DkIOMainPortDefault=charonHost_kIOMainPortDefault"
# shellcheck disable=SC2086
xcrun clang -fvisibility=hidden -w $renames -c "$port/IORegistryPaths.c" -o "$build/port.o"
xcrun clang -fobjc-arc -Wall -I"$harness" \
    "$here/differential.m" "$harness/check.m" "$build/port.o" \
    -framework Foundation -framework IOKit -o "$build/differential"
"$build/differential"
