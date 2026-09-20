#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
harness=${PROBES_HARNESS:-$here/../../device}
build=${PROBES_BUILD:-${TMPDIR:-/tmp}/charon-probes-host}
sources="DCDevice.m DCErrorDomain.m ARConfiguration.m ARImageTrackingConfiguration.m NFCReaderSession.m"
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
renames=""
for name in DCDevice DCErrorDomain ARConfiguration ARWorldTrackingConfiguration AROrientationTrackingConfiguration ARFaceTrackingConfiguration \
            ARImageTrackingConfiguration ARObjectScanningConfiguration ARErrorDomain ARReferenceObjectArchiveExtension NFCReaderSession \
            NFCNDEFReaderSession NFCErrorDomain; do
    renames="$renames -D$name=CharonHost$name"
done
rm -rf "$build"
mkdir -p "$build"
objects=""
for source in $sources; do
    xcrun clang $target -fobjc-arc -fvisibility=hidden -w $renames -I"$FOUNDATION" -c "$FOUNDATION/$source" -o "$build/$source.o"
    objects="$objects $build/$source.o"
done
xcrun clang $target -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new -I"$harness" \
    "$here/differential.m" "$harness/check.m" $objects \
    -framework UIKit -framework DeviceCheck -framework ARKit -framework CoreNFC -framework Foundation -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
