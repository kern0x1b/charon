#!/bin/sh
# Writes device/scenekit-lighting-expectations.h: macOS SceneKit's pixel for every case of the lighting grid
# (cases.swift), and a known-wrong renderer's pixel for the cases that depend on the specular exponent or the
# roughness. tests/backports/device/scenekit-lighting.m holds the port's shader to the first and must miss the second.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
DEVICE=${DEVICE:-$here/../../../device}
BUILD=${BUILD:-$(mktemp -d)}
EXPECTATIONS=${EXPECTATIONS:-$DEVICE/scenekit-lighting-expectations.h}
xcrun swiftc -O "$here/cases.swift" -o "$BUILD/cases"
"$BUILD/cases" "$BUILD/cases.json"
python3 "$here/../../foundation2/embed.py" "$BUILD/cases.json" "$EXPECTATIONS"
sed -i '' 's/foundation2_expectations/scenekit_lighting_expectations/' "$EXPECTATIONS"
echo "wrote $EXPECTATIONS"
