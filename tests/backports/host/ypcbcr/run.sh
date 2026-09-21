#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ACCELERATE=${ACCELERATE:-$here/../../../../packages/a/apple-backports/Accelerate}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness"
renames=""
for name in kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 \
            kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4 kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2 \
            vImageConvert_YpCbCrToARGB_GenerateConversion vImageConvert_ARGBToYpCbCr_GenerateConversion \
            vImageConvert_420Yp8_CbCr8ToARGB8888 vImageConvert_420Yp8_Cb8_Cr8ToARGB8888 \
            vImageConvert_ARGB8888To420Yp8_CbCr8 vImageConvert_ARGB8888To420Yp8_Cb8_Cr8 \
            vImageExtractChannel_ARGB8888; do
    renames="$renames -D$name=charonHost_$name"
done
mkdir -p "$BUILD"
xcrun clang -fobjc-arc -isysroot "$sdk" $quiet $renames -c "$ACCELERATE/vImageYpCbCr8.m" -o "$BUILD/ypcbcr.o"
xcrun clang -fobjc-arc -isysroot "$sdk" $quiet "$here/differential.m" "$BUILD/ypcbcr.o" \
    -framework Accelerate -framework Foundation -o "$BUILD/differential"
"$BUILD/differential"
