#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
GRAPHICS=${GRAPHICS:-$here/../../../../packages/a/apple-backports/Graphics}
BUILD=${BUILD:-$(mktemp -d)}
renames="-DCGColorCreateCopyByMatchingToColorSpace=CharonHostCGColorCreateCopyByMatchingToColorSpace"
xcrun clang -fobjc-arc -w $renames -c "$GRAPHICS/CGColorMatching9.m" -o "$BUILD/port.o"
xcrun clang -fobjc-arc -w "$here/differential.m" "$BUILD/port.o" -framework CoreGraphics -framework Foundation -o "$BUILD/differential"
"$BUILD/differential"
