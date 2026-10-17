#!/bin/sh
# run.sh - the host's answer for the two deprecated -[INRideDriver initWithHandle:...] initialisers: what each one
# stores, measured on the Catalyst host's own Intents (probe.m) and compared with expected.txt, the golden answer.
#
# This is the host half only. The port half, the port's IN10_0_1.m answering the same probe under renamed classes, is
# not built here: IN10_0_1.m includes CharonIntents262.h, which re-declares what the Catalyst SDK already declares
# (duplicate definitions), and the Foundation headers of the 16.4 and 26.2 iPhoneOS SDKs fail under Catalyst (NSURL.h
# includes a header that target does not carry). Until that build
# exists the two rows stay owed, and this golden is what their host answer is kept by.
#
# The plant: one golden line changed must make the diff non-empty, or the comparison cannot fail.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
build=${RIDE_DRIVER_BUILD:-$(runs_fresh charon-intents-ride-driver)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
xcrun clang -fno-objc-arc -w $target -framework Foundation -framework Intents "$here/probe.m" -o "$build/host"
"$build/host" > "$build/run.txt"
if ! diff -u "$here/expected.txt" "$build/run.txt"; then
    echo "FAIL: the host answers differently from expected.txt (lines above)"
    exit 1
fi
echo "PASS: $(wc -l < "$build/run.txt") host lines, the golden answer"
sed '1s/displayName=Alice Smith/displayName=Alice/' "$here/expected.txt" > "$build/plant.txt"
if diff -q "$build/run.txt" "$build/plant.txt" >/dev/null; then
    echo "FAIL: the plant agrees with the golden, so the comparison cannot fail"
    exit 1
fi
echo "PLANT: the changed golden differs from the host, as it must"
