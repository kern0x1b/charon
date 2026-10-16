#!/bin/sh
# run.sh - the port's CGAffineTransformDecompose and CGAffineTransformMakeWithComponents, held to the host's own
# CoreGraphics (differential.m). The port's source is compiled for this host with both functions renamed, so the
# host's and the port's stand side by side in one binary.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
GRAPHICS=${GRAPHICS:-$here/../../../../packages/a/apple-backports/Graphics}
BUILD=${BUILD:-$(runs_fresh charon-affine-components)}
mkdir -p "$BUILD"
renames="-DCGAffineTransformDecompose=CharonHostDecompose -DCGAffineTransformMakeWithComponents=CharonHostMakeWithComponents"
xcrun clang -fobjc-arc -mmacosx-version-min=10.12 -w $renames -I"$GRAPHICS" -c "$GRAPHICS/CGAffineTransform16.m" \
    -o "$BUILD/port.o"
xcrun clang -fobjc-arc -mmacosx-version-min=10.12 -w "$here/differential.m" "$BUILD/port.o" \
    -framework CoreGraphics -framework Foundation -o "$BUILD/differential"
"$BUILD/differential"
