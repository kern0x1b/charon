#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
AV=${AV:-$here/../../../../packages/a/apple-backports/AVFoundation}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-availability"
renames="-DCMTimeMultiplyByRatio=CharonHostCMTimeMultiplyByRatio"
xcrun clang -fobjc-arc $quiet $renames -c "$AV/CMTime71.m" -o "$BUILD/port.o"
xcrun clang -fobjc-arc $quiet "$here/timeratio.m" "$BUILD/port.o" -framework CoreMedia -framework CoreVideo -framework Foundation -o "$BUILD/timeratio"
"$BUILD/timeratio"
