#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
AV=${AV:-$here/../../../../packages/a/apple-backports/AVFoundation}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-availability"
xcrun clang -fobjc-arc $quiet -DCMVideoFormatDescriptionGetH264ParameterSetAtIndex=CharonHostCMVideoFormatDescriptionGetH264ParameterSetAtIndex -c "$AV/CMVideoFormatDescription7.m" -o "$BUILD/port.o"
xcrun clang -fobjc-arc $quiet "$here/differential.m" "$BUILD/port.o" -framework CoreMedia -framework Foundation -framework AudioToolbox -o "$BUILD/differential"
"$BUILD/differential"
