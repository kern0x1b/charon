#!/bin/sh
# The shear engine held against the host's own shears, over translates, filter scales and both edging modes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ACCELERATE=${ACCELERATE:-$here/../../../../packages/a/apple-backports/Accelerate}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness"
rm -rf "$BUILD"; mkdir -p "$BUILD"
xcrun clang -fobjc-arc -isysroot "$sdk" $quiet -I"$ACCELERATE" "$here/differential.m" \
    -framework Accelerate -framework Foundation -o "$BUILD/differential"
"$BUILD/differential" > "$BUILD/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$BUILD/log" || true
echo "log=$BUILD/log"
exit $result
