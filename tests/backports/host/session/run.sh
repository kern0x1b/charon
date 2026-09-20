#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
DEVICE=${DEVICE:-$here/../../device}
CHECK=${CHECK:-$DEVICE}
BUILD=${BUILD:-$(mktemp -d)}
sources="NSURLSession.m NSURLSessionTaskMetrics.m NSURLSessionConfiguration.m NSURLSessionConfiguration+BackgroundIdentifier.m NSURLSessionTask+Priority.m NSURLSession+AllTasks.m"
quiet="-Wno-deprecated-declarations -Wno-incomplete-implementation -Wno-objc-protocol-method-implementation"
mkdir -p "$BUILD/plain" "$BUILD/renamed"
for source in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet -c "$FOUNDATION/$source" -o "$BUILD/plain/$source.o"
done
renames=""
for name in $(xcrun nm -gU "$BUILD"/plain/*.o | awk 'NF == 3 {print $3}' | grep -E '^_OBJC_CLASS_\$_|^_[A-Za-z][A-Za-z0-9]*$' | sed -e 's/^_OBJC_CLASS_\$_//' -e 's/^_//' | sort -u); do
    renames="$renames -D$name=CharonHost$name"
done
for source in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet $renames -c "$FOUNDATION/$source" -o "$BUILD/renamed/$source.o"
done
xcrun clang -fobjc-arc $quiet -I"$DEVICE" -I"$CHECK" "$here/differential.m" "$DEVICE/session-scenarios.m" "$CHECK/check.m" "$BUILD"/renamed/*.o \
    -framework Foundation -framework SystemConfiguration -o "$BUILD/differential"
echo "renamed:$renames"
exec "$here/with-server.sh" "$BUILD/differential" "$@"
