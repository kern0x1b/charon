#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
UIKIT=${UIKIT:-$here/../../../../packages/a/apple-backports/UIKit}
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-incomplete-implementation -Wno-objc-protocol-method-implementation -Wno-nullability-completeness -Wno-missing-noescape"
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
mkdir -p "$BUILD"
xcrun clang -fobjc-arc -fvisibility=hidden $target $quiet -c "$UIKIT/UITableView+BatchUpdates.m" -o "$BUILD/batch.o"
perl -0777 -pi -e 's/__objc_catlist\0\0/__charon_catlist/g' "$BUILD/batch.o"
xcrun clang -fobjc-arc $target $quiet "$here/differential.m" "$here/../foundation2/host-attach.c" "$BUILD/batch.o" \
    -framework UIKit -framework Foundation -framework QuartzCore -o "$BUILD/differential"
"$BUILD/differential"
