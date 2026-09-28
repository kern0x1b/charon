#!/bin/sh
# build-renderer-differential.sh -- the renderer's five properties and its arithmetic, asked of the
# system's own renderer and of the port's in one process, under Mac Catalyst. The port's file is
# compiled under a second name with -D so both are live, and a mutant compiles a second copy of it
# with one rect changed, so the comparison can be shown to go red.
#
#   DDR_ROOT=<the checkout> sh .agent-work/plan-and-analysis/uikit-a/probe/build-renderer-differential.sh
#
# A heavy build, so it runs through heavy.sh, detached, and its log is read afterwards.
set -eu
root=${DDR_ROOT:?set DDR_ROOT to the port checkout}
probe=$root/.agent-work/plan-and-analysis/uikit-a/probe
port=$root/packages/a/apple-backports/UIKit/UITextDragPreviewRenderer11.m
build=${TMPDIR:-/tmp}/charon-renderer-differential
sdk=$(xcrun --show-sdk-path)
mkdir -p "$build"

run() {
    label=$1
    files=$2
    clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" \
        -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w \
        -D_UITextDragPreviewRenderer=CharonPortTextDragPreviewRenderer \
        -I "$root/packages/a/apple-backports/UIKit" \
        $files "$probe/renderer-compare.m" \
        -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
        -o "$build/$label"
    "$build/$label" > "$build/$label.log" 2>&1 || true
    printf '%s: ' "$label"
    tail -1 "$build/$label.log"
}

# the clean pair: the port's renderer against the system's
run clean "-I$probe $port"

# the mutant: one rect off by a point, which is what a wrong adjustment looks like
sed 's/^        firstLineRect->origin = CGPointMake(firstLineRect->origin.x + origin.x,$/        firstLineRect->origin = CGPointMake(firstLineRect->origin.x + origin.x + 1,/' \
    "$port" > "$build/renderer-mutant.m"
grep -c "origin.x + 1" "$build/renderer-mutant.m"
run mutant "-I$probe $build/renderer-mutant.m"
