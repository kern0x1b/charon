#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD:-$(mktemp -d)}
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations -o "$BUILD/differential" "$here/differential.m" \
    -framework Foundation -framework UniformTypeIdentifiers -framework CoreServices -ldl
"$BUILD/differential"
