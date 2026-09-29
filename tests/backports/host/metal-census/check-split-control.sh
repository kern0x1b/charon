#!/bin/sh
# check-split-control.sh - the control for check 2 of pre-export.sh, on Security's mixed object.
#
#     sh tests/backports/host/metal-census/check-split-control.sh
#
# Check 2 of pre-export.sh - "one object, one release" - needs a control that is KNOWN to be a
# defect, and the gate already has one: SecProtocolMetadataAccessors13_0.m as it stood before the fix,
# whose 13 accessors are first exported at iOS 12.0 and whose sec_protocol_metadata_get_server_name
# is first exported at 16.0, so the object carried two releases' API and the gate refused it.
#
# Two halves, and the second is the half that matters: the PRE-FIX file must FAIL and the FIXED PAIR
# must PASS. A check with only a negative has not been shown to pass on good input, and the one failure
# it has seen is the same failure every time for the same reason.
#
# Nothing here touches the tree: the sources come from git into a scratch under this worktree's
# .agent-work/runs, and the objects are compiled there.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
work=${WORK:-$root/.agent-work/runs/metal-census/split-control}
SDK=""
for candidate in "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk; do
    if [ -f "$candidate/SDKSettings.json" ]; then SDK="$candidate"; break; fi
done
[ -n "$SDK" ] || { echo "FAIL: no iOS 16.4 SDK" >&2; exit 1; }
rm -rf "$work"
mkdir -p "$work/src" "$work/obj" "$work/obj-fixed"

build() {   # $1 source dir, $2 objects dir
    for source in "$1"/*.m; do
        xcrun clang -target armv7-apple-ios6.1.3 -isysroot "$SDK" -fobjc-arc -Os -g0 -Wall \
            -Wno-unguarded-availability-new -Wno-unguarded-availability \
            -Werror=objc-missing-property-synthesis -c "$source" -o "$2/$(basename "${source%.m}").o" \
            > "$2/$(basename "${source%.m}").build" 2>&1 || {
            echo "FAIL: $source does not compile" >&2; exit 1; }
    done
}

# the PRE-FIX file: one object, two releases
( cd "$root" && git show 8326dfbff^:packages/a/apple-backports/Security/SecProtocolMetadataAccessors13_0.m ) \
    > "$work/src/SecProtocolMetadataAccessors13_0.m"
build "$work/src" "$work/obj"
echo "the NEGATIVE - the pre-fix object, which must fail:"
if ( cd "$work/src" && ONLY_SPLIT=1 SPLIT_DIR="$work/obj" SPLIT_OUT="$work/split.txt" WORK="$work/w1" \
        sh "$here/pre-export.sh" > "$work/negative.out" 2>&1 ); then
    echo "FAIL: the pre-fix object PASSED, so check 2 detects nothing" >&2
    sed 's/^/    /' "$work/negative.out" >&2
    exit 1
fi
grep -E "^error: release-split" "$work/negative.out" | sed 's/^/    /' || true

# the FIXED pair: two objects, one release each
rm -f "$work/src"/*.m
( cd "$root" && git show c4f6fcdb7:packages/a/apple-backports/Security/SecProtocolMetadataAccessors13_0.m ) \
    > "$work/src/SecProtocolMetadataAccessors13_0.m"
( cd "$root" && git show c4f6fcdb7:packages/a/apple-backports/Security/SecProtocolMetadataAccessors16_0.m ) \
    > "$work/src/SecProtocolMetadataAccessors16_0.m"
build "$work/src" "$work/obj-fixed"
echo "the POSITIVE - the fixed pair, which must pass:"
( cd "$work/src" && ONLY_SPLIT=1 SPLIT_DIR="$work/obj-fixed" SPLIT_OUT="$work/split-fixed.txt" \
    WORK="$work/w2" sh "$here/pre-export.sh" ) | sed 's/^/    /'
echo "check-split-control: the negative fails and the positive passes"
