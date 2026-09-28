#!/bin/sh
# Two processes, one probe, the same inputs: the system's ModelIO and the port's own sources built
# for macOS, each run separately over the input files the probe itself writes, each writing what it
# computed as canonical text. The two files are then compared line by line.
#
# The port process links the port's own sources and NOT the system ModelIO, so the two never meet in
# one runtime; port-support.m supplies the handful of symbols ModelIO itself exports that a release
# without it has to carry. Nothing in the comparison is tuned: a line that differs is reported.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
MODELIO=${MODELIO:-$here/../../../../packages/a/apple-backports/ModelIO}
BUILD=${BUILD:-$(mktemp -d)}
quiet="-Wno-unknown-pragmas -Wno-unused-value -Wno-nonnull -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-protocol-method-implementation -Wno-nullability-completeness -Wno-availability -Wno-objc-missing-property-synthesis -Wno-incomplete-implementation"
VERTICES=${VERTICES:-$here/../../../../packages/a/apple-backports/MetalKit/MDLVertexDescriptor9.m}
carried="MDLAnimatedValue11.m MDLAnimatedValue16.m MDLAssetResolver11.m MDLMaterial101.m MDLMeshBuffer11.m MDLTransformStack11.m MDLTransformStack16.m MDLTransform9.m MDLObject9.m MDLMeshBuffer9.m MDLSubmesh9.m MDLMesh9.m MDLMeshGenerators9.m MDLMaterial9.m MDLTexture9.m MDLVoxelArray9.m MDLAsset9.m"
rm -rf "$BUILD/host" "$BUILD/port"
mkdir -p "$BUILD/host" "$BUILD/port"

# The system answers: the probe alone, against the framework the host carries.
xcrun clang -fobjc-arc $quiet -DMDL_TEXTURE_TAKES_IS_CUBE=1 -DMDL_PLANE_TAKES_INWARD_NORMALS=0 "$here/probe.m" -framework ModelIO -framework CoreGraphics -framework ImageIO \
    -framework CoreServices -framework Foundation -o "$BUILD/host/probe"

# The port answers: the probe, the port's own sources, and the symbols ModelIO would have exported.
# The readers live in a category of MDLAsset, so MDLAsset9.m is compiled with the rest.
for file in $carried; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet -c "$MODELIO/$file" -o "$BUILD/port/${file%.m}.o"
done
# The vertex descriptor and its attribute and layout are the port's too, and live beside the port's
# other sources in the MetalKit library, which libModelIOBackports.dylib therefore needs.
xcrun clang -fobjc-arc -fvisibility=hidden $quiet -c "$VERTICES" -o "$BUILD/port/MDLVertexDescriptor9.o"
xcrun clang -fobjc-arc $quiet -c "$here/port-support.m" -o "$BUILD/port/port-support.o"
xcrun clang -fobjc-arc $quiet -DMDL_TEXTURE_TAKES_IS_CUBE=0 -DMDL_PLANE_TAKES_INWARD_NORMALS=1 -I"$here" "$here/probe.m" "$BUILD/port"/*.o -framework CoreGraphics -framework ImageIO \
    -framework CoreServices -framework Foundation -o "$BUILD/port/probe"

mkdir -p "$BUILD/host/in" "$BUILD/port/in"
"$BUILD/host/probe" "$BUILD/host/in" > "$BUILD/host/answers.txt" 2> "$BUILD/host/err.txt" || {
    echo "the system probe failed:"; tail -5 "$BUILD/host/err.txt"; exit 1; }
cp "$BUILD/host/in"/* "$BUILD/port/in/" 2>/dev/null || true
"$BUILD/port/probe" "$BUILD/port/in" > "$BUILD/port/answers.txt" 2> "$BUILD/port/err.txt" || {
    echo "the port probe failed:"; tail -5 "$BUILD/port/err.txt"; exit 1; }

# The inputs are the same files: the port reads the ones the system wrote, so both are measured over
# byte-identical inputs rather than over two runs of the same generator.
if ! cmp -s "$BUILD/host/in/cube.obj" "$BUILD/port/in/cube.obj"; then
    echo "the two processes were not given the same inputs"; exit 1
fi

python3 "$here/compare.py" "$BUILD/host/answers.txt" "$BUILD/port/answers.txt" "$1"
status=$?
echo "answers: $BUILD/host/answers.txt $BUILD/port/answers.txt"
exit $status
