#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
BUILD=${BUILD:-$(mktemp -d)}
sed 's/^- (NSComparisonResult)compare:/- (NSComparisonResult)charonHostCompare:/' "$FOUNDATION/NSUUID+Compare.m" > "$BUILD/NSUUID+Compare.m"
xcrun clang -fobjc-arc -mmacosx-version-min=10.11 -w "$here/differential.m" "$BUILD/NSUUID+Compare.m" -framework Foundation -o "$BUILD/differential"
"$BUILD/differential" "$BUILD/expectations.h"
cp "$BUILD/expectations.h" "$here/../../device/ios1516-expectations.h"
