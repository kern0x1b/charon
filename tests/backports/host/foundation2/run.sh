#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
DEVICE=${DEVICE:-$here/../../device}
BUILD=${BUILD:-$(mktemp -d)}
EXPECTATIONS=${EXPECTATIONS:-$DEVICE/foundation2-expectations.h}
sources=${SOURCES:-$(cat "$here/sources.txt")}
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-incomplete-implementation -Wno-objc-protocol-method-implementation -Wno-nullability-completeness"
rm -rf "$BUILD/plain" "$BUILD/renamed"
mkdir -p "$BUILD/plain" "$BUILD/renamed"
for source in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet -c "$FOUNDATION/$source" -o "$BUILD/plain/$source.o"
done
renames=""
for name in $(xcrun nm -gU "$BUILD"/plain/*.o | awk 'NF == 3 {print $3}' | grep -E '^_OBJC_CLASS_\$_|^_[A-Za-z][A-Za-z0-9]*$' | sed -e 's/^_OBJC_CLASS_\$_//' -e 's/^_//' | sort -u); do
    renames="$renames -D$name=CharonHost$name"
done
echo "renamed:$renames"
for source in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet $renames -c "$FOUNDATION/$source" -o "$BUILD/renamed/$source.o"
    perl -0777 -pi -e 's/__objc_catlist\0\0/__charon_catlist/g' "$BUILD/renamed/$source.o"
done
xcrun clang -fobjc-arc $quiet -I"$DEVICE" "$here/differential.m" "$here/host-attach.c" "$DEVICE/foundation2-cases.m" "$BUILD"/renamed/*.o \
    -framework Foundation -o "$BUILD/differential"
"$BUILD/differential" "$BUILD/expectations.json" -AppleLocale en_US -AppleLanguages '(en)'
python3 "$here/embed.py" "$BUILD/expectations.json" "$EXPECTATIONS"
