#!/bin/sh
# Records macOS SceneKit's answers for the matrix functions, a node's rotation conventions and SCNView's defaults
# into device/scenekit-expectations.h, which tests/backports/device/scenekit.m holds the port to.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
DEVICE=${DEVICE:-$here/../../device}
BUILD=${BUILD:-$(mktemp -d)}
EXPECTATIONS=${EXPECTATIONS:-$DEVICE/scenekit-expectations.h}
mkdir -p "$BUILD"
xcrun swiftc -O "$here/oracle.swift" -o "$BUILD/oracle"
"$BUILD/oracle" "$BUILD/expectations.json"
python3 "$here/../foundation2/embed.py" "$BUILD/expectations.json" "$EXPECTATIONS"
sed -i '' 's/foundation2_expectations/scenekit_expectations/' "$EXPECTATIONS"
echo "wrote $EXPECTATIONS"
