#!/bin/sh
# asan.sh — the person name suite under AddressSanitizer and UndefinedBehaviorSanitizer, so that a
# mid-sweep crash names the line and the side it is on rather than a signal number.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sources=${SOURCES:-$here/../../../../packages/a/apple-backports/Foundation}
harness=${HARNESS:-$here/../../device}
build=${BUILD:-/tmp/personname-asan}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
flags="-fobjc-arc -fvisibility=hidden -g -fsanitize=address,undefined -fno-omit-frame-pointer -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-incomplete-implementation -Wno-objc-property-implementation -Wno-nullability-completeness"
file=NSPersonNameComponentsFormatter9.m
rm -rf "$build"
mkdir -p "$build/plain" "$build/ported"
xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$file.o"
. "$here/../uikit2/renames.sh"
renames "$build/plain/$file.o" "*" > "$build/flags"
# shellcheck disable=SC2046
xcrun clang $target $flags $(cat "$build/flags") -c "$sources/$file" -o "$build/ported/$file.o"
xcrun clang $target $flags -I"$harness" "$here/test.m" "$harness/check.m" "$build/ported/$file.o" \
    -framework Foundation -framework CoreServices -o "$build/test"
ASAN_OPTIONS=detect_leaks=0:abort_on_error=0 UBSAN_OPTIONS=print_stacktrace=1 \
    "$build/test" > "$build/test.log" 2>&1 || echo "exit=$?"
grep -c '^ok ' "$build/test.log" || true
grep -E "ERROR: AddressSanitizer|runtime error|SUMMARY:" "$build/test.log" | head -6 || true
tail -4 "$build/test.log"
