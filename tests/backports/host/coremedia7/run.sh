#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
AV=${AV:-$here/../../../../packages/a/apple-backports/AVFoundation}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-availability"
renames="-DCMTimeMultiplyByRatio=CharonHostCMTimeMultiplyByRatio"
renames="$renames -DCMSampleBufferCopyPCMDataIntoAudioBufferList=CharonHostCMSampleBufferCopyPCMDataIntoAudioBufferList"
renames="$renames -DCMSampleBufferCreateReady=CharonHostCMSampleBufferCreateReady"
renames="$renames -DCMSampleBufferCreateReadyWithImageBuffer=CharonHostCMSampleBufferCreateReadyWithImageBuffer"
renames="$renames -DCMAudioSampleBufferCreateReadyWithPacketDescriptions=CharonHostCMAudioSampleBufferCreateReadyWithPacketDescriptions"
renames="$renames -DCMSampleBufferCallBlockForEachSample=CharonHostCMSampleBufferCallBlockForEachSample"
renames="$renames -DCMSampleBufferCreateWithMakeDataReadyHandler=CharonHostCMSampleBufferCreateWithMakeDataReadyHandler"
renames="$renames -DCMSampleBufferCreateForImageBufferWithMakeDataReadyHandler=CharonHostCMSampleBufferCreateForImageBufferWithMakeDataReadyHandler"
renames="$renames -DCMAudioSampleBufferCreateWithPacketDescriptionsAndMakeDataReadyHandler=CharonHostCMAudioSampleBufferCreateWithPacketDescriptionsAndMakeDataReadyHandler"
renames="$renames $(cat "$here/formatdescription-renames.txt")"
for object in "$AV"/*.m; do
    case "$(basename "$object")" in CMFormatDescription*|CMTime71*|CMSampleBuffer*) ;; *) continue ;; esac
    xcrun clang -fobjc-arc $quiet $renames -c "$object" -o "$BUILD/$(basename "$object" .m).o"
done
for test in timeratio pcmdata createready constants; do
    [ -f "$here/$test.m" ] || continue
    xcrun clang -fobjc-arc $quiet "$here/$test.m" "$BUILD"/*.o -framework CoreMedia -framework CoreVideo -framework AudioToolbox -framework Foundation -o "$BUILD/$test"
    "$BUILD/$test"
done
