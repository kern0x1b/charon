#!/bin/sh
# The car home screen's geometry, checked for the three head-unit resolutions the CarPlay design
# names: 800x480 (15:9, Table 23-9), 960x540 (16:9) and 1280x720 (16:9). The layout is a pure
# function of the screen, so this compiles the port's own file on the host and compares what it
# decides with the numbers the car screen's own constraints require.
#
# The pixels are the device's to answer, not the host's: the skeuomorphic look is the release's own
# UIKit, which does not exist here. That is what the emulator call test is for, and what the
# snapshots are.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/CarPlay}
build=${MAPKIT_CARPLAY_BUILD:-${TMPDIR:-/tmp}/charon-mapkit-carplay}
rm -rf "$build"
mkdir -p "$build"
xcrun clang -fobjc-arc -Wall -I"$port" -c "$port/CharonCarPlayLayout.m" -o "$build/layout.o"
xcrun clang -fobjc-arc -Wall -framework Foundation -framework CoreGraphics \
    -I"$port" "$here/differential.m" "$build/layout.o" -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
