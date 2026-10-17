#!/bin/sh
# run.sh - what the host RUNTIME does with -[INDateComponentsRange initWithEKRecurrenceRule:] and its getter
# -[INDateComponentsRange EKRecurrenceRule], asked by probe.m on macOS and on Catalyst.
#
# The two hosts must agree, and both must match expected.txt, the golden answer. The plant is the golden with one
# number changed: the comparison must fail on it, or it cannot fail at all.
#
# This is the host's answer, not the port's: the port's implementation is decided from it (facts/Intents/Intents.md,
# "EventKit's recurrence rule"). The host raises for a daily rule, and drops a weekly rule's second day and its end, so
# its getter is not a round trip of what it is given.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
build=${EK_BUILD:-$(runs_fresh charon-intents-ek)}
sdk=$(xcrun --show-sdk-path)
catalyst="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
frameworks="-framework Foundation -framework Intents -framework EventKit"
flags="-fno-objc-arc -w"

xcrun clang $flags "$here/probe.m" $frameworks -o "$build/macos"
"$build/macos" > "$build/macos.txt"
xcrun clang $flags $catalyst "$here/probe.m" $frameworks -o "$build/catalyst"
"$build/catalyst" > "$build/catalyst.txt"

if ! diff -u "$here/expected.txt" "$build/macos.txt"; then
    echo "FAIL: macOS answers differently from expected.txt (lines above)"
    exit 1
fi
if ! diff -u "$build/macos.txt" "$build/catalyst.txt"; then
    echo "FAIL: Catalyst answers differently from macOS (lines above)"
    exit 1
fi
echo "PASS: $(wc -l < "$build/macos.txt") lines, macOS and Catalyst alike, the golden answer"

# The plant: the golden with the daily frequency changed (Daily is 3). It must not match the runtime.
sed 's/number 3$/number 9/' "$here/expected.txt" > "$build/plant.txt"
if diff -q "$build/plant.txt" "$build/macos.txt" >/dev/null; then
    echo "FAIL: the planted golden agrees with the runtime, so the comparison cannot fail"
    exit 1
fi
echo "PLANT: the changed golden differs from the runtime, as it must"
