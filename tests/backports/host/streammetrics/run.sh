#!/bin/sh
# run.sh — the four names a stream task's transaction reports about the socket, against the host's own.
#
# The port's classes are compiled under names of their own (uikit2/renames.sh with "*", which renames
# the classes and leaves the selectors), so the two sides never meet. The listener is the test's own
# and writes one byte when a connection lands, and the test bounds its own run, so a run that goes
# wrong fails rather than hanging the host test sweep.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sources=${SOURCES:-$here/../../../../packages/a/apple-backports/Foundation}
harness=${HARNESS:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
flags="-fobjc-arc -fvisibility=hidden -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-incomplete-implementation -Wno-objc-property-implementation -Wno-nullability-completeness"
files="NSURLSessionStreamTask9.m NSURLSession+StreamTask9.m CharonStreamTaskState.m NSURLSessionTaskMetrics.m NSURLSessionTaskTransactionMetrics+Counts13.m"
mkdir -p "$build/plain" "$build/ported"
. "$here/../uikit2/renames.sh"
objects=""
for file in $files; do
    xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$file.o"
    objects="$objects $build/plain/$file.o"
done
renames "$objects" "*" > "$build/flags"
built=""
for file in $files; do
    # shellcheck disable=SC2046
    xcrun clang $target $flags $(cat "$build/flags") -c "$sources/$file" -o "$build/ported/$file.o"
    built="$built $build/ported/$file.o"
done
xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/test.m" "$harness/check.m" "$here/../foundation2/host-attach.c" $built \
    -framework Foundation -framework CoreServices -framework Security -framework SystemConfiguration -o "$build/test"
if command -v gtimeout >/dev/null 2>&1; then outer="gtimeout 300"; else outer=""; fi
if $outer "$build/test" > "$build/test.log" 2>&1; then result=0; else result=$?; fi
grep -v '^ok ' "$build/test.log" || true
echo "streammetrics: exit=$result log=$build/test.log"
exit "$result"
