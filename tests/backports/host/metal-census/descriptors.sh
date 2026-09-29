#!/bin/sh
# descriptors.sh - the 14.0 descriptors against Apple's own objects, and the mutation the case must
# notice.
#
#     sh tests/backports/host/metal-census/descriptors.sh
#     SELF_TEST=1 sh tests/backports/host/metal-census/descriptors.sh   # prove_defined's own halves
#
# Run from packages/a/apple-backports. ONE clang line builds the case TOGETHER WITH the port source,
# the way argbinding.sh does it: the device object and the host case cannot be linked together, and
# the failure looks like a missing main rather than a mismatched architecture.
#
# NO DEVICE IS EVER CREATED, and the case is built so that it CANNOT be: a descriptor is
# [[X alloc] init] on both sides, and MTLCreateSystemDefaultDevice() HANGS on a machine with no GPU.
# So the oracle is Apple's own object of the same class, and the port is compared to it property by
# property. The check below refuses a case that has linked a device, because a case that made one
# would either hang or be measuring something else.
#
# A MUTATION THAT DOES NOT BUILD IS "RUN FAILED", NEVER RED - the same rule and the same reason as in
# argbinding.sh: a mutation compiled with a wrong -I depth once left the previous binary in place and
# a green run was read off an object that no longer existed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
work=${WORK:-$root/.agent-work/runs/metal-census/descriptors}
# ONE guard for every script that removes a scratch path - see work-guard.sh.
. "$here/work-guard.sh"
work_ok "$work" || { echo "FAIL: WORK=$work is not a usable scratch path; see work-guard.sh" >&2; exit 1; }
S="$root/packages/a/apple-backports"
SRC="$S/Metal/MTLDescriptors14.m"
rm -rf "$work"
mkdir -p "$work"

sdk=$(xcrun --show-sdk-path --sdk macosx)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks"
common="$common -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc"
common="$common -I $S/Metal -I $S -I $S/MetalKit -I $root/tests/backports/host/metalblit/gl-stub"

# THE PORT'S CLASSES MUST BE DEFINED IN THE BINARY. Metal has an API on the host too, so a case can
# pass by measuring Apple's class instead of the port's.
prefix='_OBJC_CLASS_$_'
class_list="CharonMetalAccelerationStructureDescriptor CharonMetalAccelerationStructureGeometryDescriptor CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor CharonMetalAccelerationStructureTriangleGeometryDescriptor CharonMetalPrimitiveAccelerationStructureDescriptor CharonMetalInstanceAccelerationStructureDescriptor CharonMetalVisibleFunctionTableDescriptor CharonMetalIntersectionFunctionTableDescriptor CharonMetalCounterSampleBufferDescriptor CharonMetalComputePassSampleBufferAttachmentDescriptor CharonMetalResourceStatePassSampleBufferAttachmentDescriptor CharonMetalRenderPassSampleBufferAttachmentDescriptor CharonMetalComputePassDescriptor CharonMetalResourceStatePassDescriptor CharonMetalBinaryArchiveDescriptor CharonMetalComputePassSampleBufferAttachmentDescriptorArray CharonMetalRenderPassSampleBufferAttachmentDescriptorArray CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray CharonMetalLinkedFunctions CharonMetalIntersectionFunctionDescriptor"
prove_defined() {   # $1 nm output
    for name in $class_list; do
        symbol="${prefix}${name}"
        defined=$(printf '%s\n' "$1" | awk -v s="$symbol" 'index($0, s){n++} END{print n+0}')
        if [ "$defined" -eq 0 ]; then
            echo "MISSING $symbol - the case would measure the HOST's Metal, not the port's" >&2
            return 1
        fi
    done
    count=$(printf '%s\n' "$1" | awk -v p="$prefix" 'index($0, p "CharonMetal"){n++} END{print n+0}')
    expected=0
    for symbol in $class_list; do expected=$((expected + 1)); done
    if [ "$count" -ne "$expected" ]; then
        echo "FAIL: $count of the port's $expected class symbols are defined in the binary" >&2
        return 1
    fi
    echo "  the port's classes are DEFINED in the binary: $count of $expected"
}

if [ -n "${SELF_TEST:-}" ]; then
    selfdir="$root/.agent-work/runs/metal-census/descriptors-self-test"
    work_ok "$selfdir" || { echo "FAIL: the self-test scratch is not under .agent-work" >&2; exit 1; }
    rm -rf "$selfdir"; mkdir -p "$selfdir" || exit 1
    fake="$selfdir/symbols"
    for name in $class_list; do
        if [ "$name" = "CharonMetalLinkedFunctions" ]; then continue; fi   # the one that is missing
        printf '%s S %s%s\n' "0000000000000100" "$prefix" "$name" >> "$fake"
    done
    if prove_defined "$(cat "$fake")"; then
        echo "FAIL: the self-test passed with a class missing from the symbol table" >&2
        rm -rf "$selfdir"; exit 1
    fi
    echo "  ok   the self-test's NEGATIVE: the class that is not defined is named"
    : > "$fake"
    for name in $class_list; do printf '%s S %s%s\n' "0000000000000100" "$prefix" "$name" >> "$fake"; done
    if ! prove_defined "$(cat "$fake")"; then
        echo "FAIL: the self-test's full list was refused, so prove_defined is not usable" >&2
        rm -rf "$selfdir"; exit 1
    fi
    echo "  ok   the self-test's POSITIVE: the full list of ${class_list} passes"
    rm -rf "$selfdir"
    exit 0
fi

# $1 output name, $2 case source, $3 port source. ALWAYS REBUILDS.
build() {   # $1 output name, $2 case source, $3 port source
    rm -f "$work/$1" "$work/$1.o"
    # shellcheck disable=SC2086
    xcrun clang $common -framework Foundation -framework Metal -o "$work/$1" "$2" "$3" \
        > "$work/$1.link" 2>&1 || {
        echo "RUN FAILED  $1 does not build - this is a build failure, not a red test" >&2
        sed -n '/error:/,$p' "$work/$1.link" | head -1 | sed 's/^/    /' >&2
        exit 1
    }
    # A case that linked a device could hang or measure something else, and this family must not.
    if otool -L "$work/$1" | tail -n +2 | grep -q "MTLDevice.h\|newArgumentEncoder"; then
        echo "FAIL: $1 appears to have reached for a device" >&2
        exit 1
    fi
}

# A mutation is SCOPED TO ITS CLASS, not matched by text: several of these getters answer the same
# constant, and a plain text replace hits whichever comes first in the file.
mutate_scoped() {   # $1 mutant name, $2 class, $3 old return, $4 new return
    cp "$SRC" "$work/$1.m"
    python3 - "$work/$1.m" "$2" "$3" "$4" <<'PY'
import re, sys
path, cls, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path).read()
i = text.index("@implementation %s\n" % cls)
head, body = text[:i], text[i:]
assert old in body, "the mutation must match the code it is mutating: %r" % old
body = body.replace(old, new, 1)
open(path, "w").write(head + body)
PY
}

expect_red() {   # $1 label, $2 output name
    if "$work/$2" > "$work/$2.out" 2>&1; then
        echo "FAIL  $1 is NOT red - this class is measured by nothing" >&2
        exit 1
    fi
    line=$(grep -m1 'FAIL' "$work/$2.out" | sed 's/^ *FAIL /  /')
    if [ -z "$line" ]; then
        echo "FAIL  $1 produced no assertion line - see $work/$2.out" >&2
        exit 1
    fi
    echo "  red  $line"
}

echo "the differential, against Apple's own objects, with no device created:"
build real "$here/descriptors.m" "$SRC"
prove_defined "$(nm -g "$work/real" 2>/dev/null)" || exit 1
timeout 120 "$work/real" || { echo "FAIL: the descriptor differential failed" >&2; exit 1; }

# THE CONTROL the failure mode needs: a mutation that does NOT compile is RUN FAILED with a non-zero
# exit, and is never counted as a red test.
echo "the control: a mutation that does not compile is RUN FAILED, not red"
cp "$SRC" "$work/broken.m"
printf '\nthis is not valid Objective-C;\n' >> "$work/broken.m"
rm -f "$work/broken" "$work/broken.o"
# shellcheck disable=SC2086
if xcrun clang $common -framework Foundation -framework Metal -o "$work/broken" \
    "$here/descriptors.m" "$work/broken.m" > "$work/broken.link" 2>&1; then
    echo "FAIL: the control's broken mutation COMPILED, so it proves nothing" >&2
    exit 1
fi
if [ -e "$work/broken" ]; then
    echo "FAIL: the control left a binary behind, which is how a stale object read as green" >&2
    exit 1
fi
echo "  ok   RUN FAILED: the broken mutation did not build, and no binary was left to run"

echo "the mutations: one per class that owns a member no other class shares"
mutate_scoped m1 CharonMetalVisibleFunctionTableDescriptor \
    "@synthesize functionCount = _functionCount;" \
    "- (NSUInteger)functionCount { return 0; }   // MUTATION: the count is dropped"
build mutant-m1 "$here/descriptors.m" "$work/m1.m"
expect_red "M1 MTLVisibleFunctionTableDescriptor -functionCount" mutant-m1

mutate_scoped m2 CharonMetalIntersectionFunctionTableDescriptor \
    "@synthesize functionCount = _functionCount;" \
    "- (NSUInteger)functionCount { return 0; }   // MUTATION: the count is dropped"
build mutant-m2 "$here/descriptors.m" "$work/m2.m"
expect_red "M2 MTLIntersectionFunctionTableDescriptor -functionCount" mutant-m2

mutate_scoped m3 CharonMetalCounterSampleBufferDescriptor \
    "@synthesize sampleCount = _sampleCount;" \
    "- (NSUInteger)sampleCount { return 0; }   // MUTATION: the count is dropped"
build mutant-m3 "$here/descriptors.m" "$work/m3.m"
expect_red "M3 MTLCounterSampleBufferDescriptor -sampleCount" mutant-m3

echo "descriptors: the differential is green, the control is RUN FAILED, and all three mutants are red"
# THE SCRATCH IS REMOVED HERE.
rm -rf "$work"
