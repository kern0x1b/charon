#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
suite=${1:?usage: run.sh percentencoding|stringcase|calendar [rounds] [seed]}
shift
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
build=${FUZZ_BUILD:-${TMPDIR:-/tmp}/charon-fuzz-host}/$suite
case $suite in
    percentencoding) sources="NSString+URLUtilities.m NSCharacterSet+URLUtilities.m NSData+Base64.m"; defaults= ;;
    stringcase) sources="NSString+LocalizedCase.m NSString+Containment.m NSString+Transform.m"; defaults="-AppleLocale en_US -AppleLanguages (en)" ;;
    calendar) sources="NSCalendar+Components.m NSCalendar+Weekend.m NSDateComponents+Validation.m CharonCalendarUnits.m"; defaults= ;;
    *) echo "no fuzzer $suite" >&2; exit 2 ;;
esac
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-incomplete-implementation -Wno-objc-protocol-method-implementation -Wno-nullability-completeness"
rm -rf "$build"
mkdir -p "$build/plain" "$build/prefixed" "$build/renamed"
for s in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet -c "$FOUNDATION/$s" -o "$build/plain/$s.o"
done
printf '#import <Foundation/Foundation.h>\n' > "$build/prefixed/declarations.h"
for s in $sources; do
    python3 "$here/../prefix_selectors.py" "$FOUNDATION/$s" "$build/prefixed/$s" charonHost_ --declarations="$build/prefixed/declarations.h" -fobjc-arc $quiet -- "$build"/plain/*.o
done
for s in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet -I"$FOUNDATION" -include "$build/prefixed/declarations.h" -c "$build/prefixed/$s" -o "$build/renamed/$s.o"
    perl -0777 -pi -e 's/__objc_catlist\0\0/__charon_catlist/g' "$build/renamed/$s.o"
done
xcrun clang -fobjc-arc -w -I"$here" "$here/$suite.m" "$here/fuzz.m" "$here/../foundation2/host-attach.c" "$build"/renamed/*.o -framework Foundation -o "$build/fuzz"
FUZZ_TOLERATED="$here/tolerated/$suite.txt" "$build/fuzz" "${1:-0}" "${2:-0}" $defaults
