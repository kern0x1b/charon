#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
AV=${AV:-$here/../../../../packages/a/apple-backports/AVFoundation}
BUILD=${BUILD:-$(mktemp -d)}
mkdir -p "$BUILD"
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
renames="$renames -DCMVideoFormatDescriptionGetHEVCParameterSetAtIndex=CharonHostCMVideoFormatDescriptionGetHEVCParameterSetAtIndex"
renames="$renames $(cat "$here/formatdescription-renames.txt")"
for object in "$AV"/*.m; do
    case "$(basename "$object")" in CMFormatDescription*|CMTime71*|CMSampleBuffer*) ;; *) continue ;; esac
    xcrun clang -fobjc-arc $quiet $renames -c "$object" -o "$BUILD/$(basename "$object" .m).o"
done
for test in timeratio pcmdata createready constants; do
    if [ ! -f "$here/$test.m" ]; then
        echo "note: $here/$test.m is missing, so its checks are not run"
        exit 1
    fi
    xcrun clang -fobjc-arc $quiet "$here/$test.m" "$BUILD"/*.o -framework CoreMedia -framework CoreVideo -framework AudioToolbox -framework Foundation -o "$BUILD/$test"
    "$BUILD/$test"
done
# The CMTagCollection family: the port's file as its own image, so its names are reached through
# dlopen(RTLD_LOCAL | RTLD_FIRST) while the probe's own calls reach the host's CoreMedia. No renaming,
# no -D, and no system header is touched.
xcrun clang -dynamiclib -fobjc-arc $quiet -I"$AV" -DkCMTagInvalid=port_kCMTagInvalid \
    -DkCMTagCategoryKey=port_kCMTagCategoryKey -DkCMTagValueKey=port_kCMTagValueKey -DkCMTagDataTypeKey=port_kCMTagDataTypeKey -framework Foundation -framework CoreMedia -framework CoreVideo \
    -o "$BUILD/libCharonCMTag.dylib" "$AV/CMTagCollection17.m"
xcrun clang -fobjc-arc $quiet "$here/tagcollectionimage.m" -framework CoreMedia -framework CoreVideo -framework Foundation \
    -o "$BUILD/tagcollectionimage"
"$BUILD/tagcollectionimage" "$BUILD/libCharonCMTag.dylib"
# The HEVC reader is held against a real hvcC - the record of an ffmpeg/libx265 stream, committed here
# beside the test that reads it - every truncation of it, and single-byte flips of it. Under
# AddressSanitizer, because a reader that walks off the end of a record is exactly the bug this is for.
hvc="$here/hvcC-x265.bin"
if [ ! -f "$hvc" ]; then
    echo "note: the HEVC oracle $hvc is missing, so CMVideoFormatDescriptionGetHEVCParameterSetAtIndex is unchecked"
    exit 1
fi
xcrun clang -fobjc-arc -w -fsanitize=address -g $quiet "$here/hevcreader.m" "$BUILD/CMFormatDescription11.o" \
    -framework CoreMedia -framework CoreVideo -framework Foundation -o "$BUILD/hevcreader"
"$BUILD/hevcreader" "$hvc"
