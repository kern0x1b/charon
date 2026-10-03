#!/bin/sh
# unavailableinit.sh - the oracle for the five registry rows that say a MetalKit class has no -init of
# its own.
#
#     sh tests/backports/host/metal-census/unavailableinit.sh
#
# MetalKit's headers declare `- (nonnull instancetype)init NS_UNAVAILABLE` on MTKMesh, MTKSubmesh,
# MTKMeshBuffer, MTKMeshBufferAllocator and MTKTextureLoader, so the port defines no such method and
# the row is `absent`. That is only the same answer as Apple's if Apple's own class does not define one
# either, and this is what measures that - with TWO controls, because `class_getInstanceMethod`
# searches superclasses and so answers non-nil for every NSObject subclass: NSObject itself is asked
# as the control, and NSMutableDictionary, which does override -init, is asked to show that an
# override is visible to this measurement at all. A nonsense class name is the third control.
#
# NO DEVICE IS CREATED and none is needed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
work=${WORK:-$root/.agent-work/runs/metal-census/unavailableinit}
# ONE guard for every script that removes a scratch path - see work-guard.sh.
. "$here/work-guard.sh"
work_ok "$work" || { echo "FAIL: WORK=$work is not a usable scratch path; see work-guard.sh" >&2; exit 1; }
rm -f "$work/unavailableinit" "$work/unavailableinit.o"
mkdir -p "$work"

sdk=$(xcrun --show-sdk-path --sdk macosx)
target="-target arm64-apple-ios17.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
xcrun clang $target -fobjc-arc -O0 -framework Foundation -framework MetalKit \
    -o "$work/unavailableinit" "$here/unavailableinit.m" || {
    echo "RUN FAILED  the case does not build or link" >&2
    exit 1
}
timeout 120 "$work/unavailableinit" || { echo "FAIL: the init measurement failed" >&2; exit 1; }

# THE MUTATION: a case that reported "no override" for a class that DOES override -init would be a
# harness that cannot fail. Nothing of the port is involved - this is Apple's own framework - so the
# mutation is in the CASE: the control class's own -init is deleted, which makes it inherit NSObject's
# and must turn the control's check red.
echo "the mutation: the case's control class no longer overrides -init"
sed '/^- (instancetype)init { return \[super init\]; }$/d' "$here/unavailableinit.m" > "$work/mutant.m"
rm -f "$work/mutant"
xcrun clang $target -fobjc-arc -O0 -framework Foundation -framework MetalKit \
    -o "$work/mutant" "$work/mutant.m" || { echo "RUN FAILED  the mutant does not build" >&2; exit 1; }
if timeout 120 "$work/mutant" > "$work/mutant.out" 2>&1; then
    echo "FAIL  the mutation is NOT red - the override control measures nothing" >&2
    exit 1
fi
line=$(grep -m1 'FAIL' "$work/mutant.out" | sed 's/^ *FAIL /  /')
if [ -z "$line" ]; then
    echo "FAIL  the mutation produced no assertion line - see $work/mutant.out" >&2
    exit 1
fi
echo "  red  $line"

echo "unavailableinit: the measurement is green and its control is red"
# THE SCRATCH IS REMOVED HERE, except the mutant's log, which is the evidence.
rm -f "$work/unavailableinit" "$work/unavailableinit.o" "$work/mutant" "$work/mutant.m"