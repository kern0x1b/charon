#!/bin/sh
# run.sh — differential host tests for the second UIKit batch: the backported sources are compiled for
# Mac Catalyst with their classes, selectors and constants renamed, so each test can put the backport and
# the system implementation side by side in one process. The spring curve is checked against a real
# CASpringAnimation, which needs AppKit, so that part runs as a plain macOS tool.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sources=${UIKIT2_SOURCES:-$here/../../../../packages/a/apple-backports/UIKit}
harness=${UIKIT2_HARNESS:-$here/../../device}
build=${UIKIT2_BUILD:-${TMPDIR:-/tmp}/charon-uikit2-host}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
frameworks="-framework LocalAuthentication -framework MobileCoreServices -framework SafariServices -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation"
flags="-DCHARON_HOST_DIFFERENTIAL=1 -fobjc-arc -fvisibility=hidden -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-protocol-method-implementation -Wno-incomplete-implementation -Wno-objc-property-implementation"
rm -rf "$build"
mkdir -p "$build/plain"
export CHARON_DATA_ASSETS="$here/../../device/data-assets/Assets.car"
if [ -n "${CHARON_DATA_ASSET_CATALOG:-}" ] && [ -f "$CHARON_DATA_ASSET_CATALOG" ]; then
    assetutil --info "$CHARON_DATA_ASSET_CATALOG" > "${TMPDIR:-/tmp}/charon-dataassets.json"
fi

. "$here/renames.sh"

group() {
    # $1: group name, $2: sources, $3: selectors to keep, $4: test source
    name=$1
    files=$2
    keep=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$keep" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/$test" "$harness/check.m" $built $frameworks -o "$build/$name-test"
    if "$build/$name-test" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed() {
    # $1: group name, $2: sources, $3: selectors to keep, $4: test source; the test runs in an application with a window
    name=$1
    files=$2
    keep=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$keep" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    bundle="$build/$name.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/windowed.m" "$here/$test" "$harness/check.m" $built $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    if "$bundle/Contents/MacOS/app" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" | grep -a 'FAIL\|checks=\|info' || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed_expected() {
    # $1: group name, $2: sources, $3: selectors to keep, $4: test source run against the port, $5: source that records what the system answers, in a process with none of the port's code
    name=$1
    files=$2
    keep=$3
    test=$4
    recorder=$5
    bundle="$build/$name-system.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -w -I"$harness" "$here/windowed.m" "$here/$recorder" "$harness/check.m" $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    expected="$build/$name.expected"
    if CHARON_EXPECTED="$expected" "$bundle/Contents/MacOS/app" > "$build/$name-system.log" 2>&1; then result=0; else result=$?; fi
    echo "$name-system: exit=$result log=$build/$name-system.log"
    [ "$result" = 0 ] || status=1
    CHARON_EXPECTED="$expected"
    export CHARON_EXPECTED
    windowed "$name" "$files" "$keep" "$test"
}

renamed_keep() {
    # $1: object files, $2: the selectors that are renamed; every other selector the objects define keeps its name
    printf '%s\n' $2 > "$build/rename.list"
    nm $1 | sed -n 's/.*[-+]\[[A-Za-z_]*(*[A-Za-z]*)* \([A-Za-z_][A-Za-z0-9_]*\).*\]$/\1/p' | grep -v '^charon_' | sort -u | grep -v -x -f "$build/rename.list" | tr '\n' ' '
}

windowed_renamed() {
    # $1: group name, $2: sources, $3: selectors that get renamed, $4: test source; as windowed, but only the classes and the named selectors are renamed
    name=$1
    files=$2
    renamed=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$(renamed_keep "$objects" "$renamed")" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    bundle="$build/$name.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/windowed.m" "$here/$test" "$harness/check.m" $built $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    if "$bundle/Contents/MacOS/app" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" | grep -a 'FAIL\|checks=\|info' || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

renamed() {
    # $1: group name, $2: sources, $3: selectors that get renamed, $4: test source; as group, but only the classes and the named selectors are renamed
    name=$1
    files=$2
    renamed=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$(renamed_keep "$objects" "$renamed")" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/$test" "$harness/check.m" $built $frameworks -o "$build/$name-test"
    if "$build/$name-test" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed_renamed_expected() {
    # $1: group name, $2: sources, $3: selectors that get renamed, $4: test source run against the port, $5: source that records what the system answers, in a process with none of the port's code
    name=$1
    files=$2
    renamed=$3
    test=$4
    recorder=$5
    bundle="$build/$name-system.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -w -I"$harness" "$here/windowed.m" "$here/$recorder" "$harness/check.m" $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    expected="$build/$name.expected"
    if CHARON_EXPECTED="$expected" "$bundle/Contents/MacOS/app" > "$build/$name-system.log" 2>&1; then result=0; else result=$?; fi
    echo "$name-system: exit=$result log=$build/$name-system.log"
    [ "$result" = 0 ] || status=1
    CHARON_EXPECTED="$expected"
    export CHARON_EXPECTED
    windowed_renamed "$name" "$files" "$renamed" "$test"
}

status=0
renamed textkit2 "NSTextRange15.m NSTextSelection15.m NSTextElement15.m NSTextSelectionNavigation15.m CharonTextLocation.m" "" textkit2_test.m
exit $status
