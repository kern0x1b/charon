#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sources=${INTERACTIONS_SOURCES:-$here/../../../../packages/a/apple-backports/UIKit}
harness=${INTERACTIONS_HARNESS:-$here/../../device}
build=${INTERACTIONS_BUILD:-${TMPDIR:-/tmp}/charon-interactions-host}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
files="UIView+Interactions.m NSObject+AccessibilityAttributedStrings.m UIKitConstants11.m"
constants="UIAccessibilitySpeechAttributeQueueAnnouncement UIAccessibilitySpeechAttributeIPANotation UIAccessibilityTextAttributeHeadingLevel UIAccessibilityTextAttributeCustom UIImagePickerControllerImageURL UIActivityTypeMarkupAsPDF"
frameworks="-framework UIKit -framework Foundation -framework CoreGraphics"
rm -rf "$build"
mkdir -p "$build/plain" "$build/ours"
for file in $files; do
    xcrun clang $target -fobjc-arc -fvisibility=hidden -w -c "$sources/$file" -o "$build/plain/$file.o"
done
plain=""
for file in $files; do plain="$plain $build/plain/$file.o"; done
rename() {
    awk '{
        t = $0
        if (t ~ /^set[A-Z]/) { rest = substr(t, 4); print "-D" t "=setCharonHost" rest; print "-D" tolower(substr(rest, 1, 1)) substr(rest, 2) "=charonHost" rest }
        else print "-D" t "=charonHost" toupper(substr(t, 1, 1)) substr(t, 2)
    }' | sort -u
}
selectors=$(nm $plain | sed -n 's/.*[-+]\[[A-Za-z_]*([A-Za-z]*) \([A-Za-z_]*\).*\]$/\1/p' | grep -v '^charon_' | rename)
for constant in $constants; do selectors="$selectors -D$constant=CharonHost$constant"; done
printf '%s\n' $selectors > "$build/flags"
objects=""
for file in $files; do
    xcrun clang $target -fobjc-arc -fvisibility=default -w $(cat "$build/flags") -c "$sources/$file" -o "$build/ours/$file.o"
    objects="$objects $build/ours/$file.o"
done
xcrun clang $target -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new -I"$harness" \
    "$here/differential.m" "$harness/check.m" $objects $frameworks -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
