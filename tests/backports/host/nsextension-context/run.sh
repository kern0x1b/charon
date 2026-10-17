#!/bin/sh
# run.sh - a fresh NSExtensionContext, asked the same questions on the host (Catalyst) and on the port's class, from one
# probe source (probe.m).
#
# Two lines are not compared the same way. The host's completeRequestReturningItems:completionHandler: does not call back
# on a context no extension host has started, so that line is held to the host's golden (expected.txt: callback 0).
# The port calls back once with expired NO, by the ruling that the context answers what an application's own context
# answers. Every other line is the host's, line for line.
#
# The plant: a port whose hostedViewMinimumAllowedSize answers 1 by 1. Its diff against the host must be non-empty.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
P=${PORT_DIR:-$here/../../../../packages/a/apple-backports}
build=${NSEXTENSION_BUILD:-$(runs_fresh charon-nsextension-context)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
flags="$target -fobjc-arc -fvisibility=hidden -w -DCHARON_HOST_BUILD"
probe_flags="$target -fno-objc-arc -fvisibility=hidden -w"
frameworks="-framework Foundation -framework UIKit -framework CoreGraphics -framework IntentsUI"
mkdir -p "$build/port" "$build/plant"

xcrun clang $probe_flags "$here/probe.m" $frameworks -o "$build/host"
"$build/host" > "$build/host.txt"
if ! diff -u "$here/expected.txt" "$build/host.txt"; then
    echo "FAIL: the host answers differently from expected.txt (lines above)"
    exit 1
fi
echo "PASS: $(wc -l < "$build/host.txt" | tr -d ' ') host lines, the golden answer"

# The port's class, compiled under renamed symbols (CharonHostNSExtensionContext), as the other host harnesses do.
xcrun clang $flags -c "$P/IntentsUI/CharonNSExtensionContext.m" -o "$build/plain.o"
renames=""
for name in $(xcrun nm -gU "$build/plain.o" | awk 'NF == 3 {print $3}' | grep -E '^_OBJC_CLASS_\$_' | sed -e 's/^_OBJC_CLASS_\$_//' | sort -u); do
    renames="$renames -D$name=CharonHost$name"
done
xcrun clang $flags $renames -c "$P/IntentsUI/CharonNSExtensionContext.m" -o "$build/port/CharonNSExtensionContext.o"
xcrun clang $probe_flags -DPORT "$here/probe.m" "$build/port/CharonNSExtensionContext.o" $frameworks -o "$build/port-probe"
"$build/port-probe" > "$build/port.txt"

grep -v '^completeRequest callback' "$build/host.txt" > "$build/host-cmp.txt"
grep -v '^completeRequest callback' "$build/port.txt" > "$build/port-cmp.txt"
if ! diff -u "$build/host-cmp.txt" "$build/port-cmp.txt"; then
    echo "FAIL: the port answers differently from the host (lines above)"
    exit 1
fi
if ! grep -qx 'completeRequest callback 1 expired 0' "$build/port.txt"; then
    echo "FAIL: the port's completion is not called once with expired NO, as the ruling says:"
    grep '^completeRequest callback' "$build/port.txt"
    exit 1
fi
echo "PASS: $(wc -l < "$build/port-cmp.txt" | tr -d ' ') lines alike; the completion is called once, expired NO, as ruled"

# The plant: the port's minimum size answers 1 by 1, in the first of its two CGSizeZero returns.
awk 'BEGIN { done = 0 } /return CGSizeZero;/ && !done { sub(/return CGSizeZero;/, "return CGSizeMake(1, 1);"); done = 1 } { print }' \
    "$P/IntentsUI/CharonNSExtensionContext.m" > "$build/plant/plant.m"
if cmp -s "$P/IntentsUI/CharonNSExtensionContext.m" "$build/plant/plant.m"; then
    echo "FAIL: the plant edit changed nothing, so the plant is not a plant"
    exit 1
fi
xcrun clang $flags $renames -c "$build/plant/plant.m" -o "$build/plant/plant.o"
xcrun clang $probe_flags -DPORT "$here/probe.m" "$build/plant/plant.o" $frameworks -o "$build/plant-probe"
status=0
"$build/plant-probe" > "$build/plant.txt" || status=$?
if [ "$status" -ne 0 ]; then
    echo "PLANT: the planted port stopped with status $status, which differs from the host, as it must"
    exit 0
fi
grep -v '^completeRequest callback' "$build/plant.txt" > "$build/plant-cmp.txt"
if diff -q "$build/host-cmp.txt" "$build/plant-cmp.txt" >/dev/null; then
    echo "FAIL: the planted port agrees with the host, so the comparison cannot fail"
    exit 1
fi
echo "PLANT: the planted port differs from the host, as it must"
