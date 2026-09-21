#!/bin/sh
# run.sh — records what the system's UIPresentationController does for every case of device/tail1-cases.m, in a
# Mac Catalyst application with a window, and writes the answers where the device test reads them.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
app="$build/record.app"
mkdir -p "$app/Contents/MacOS"
xcrun clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w -I"$device" \
    "$here/../uikit2/windowed.m" "$here/record.m" "$device/tail1-cases.m" "$device/check.m" -framework UIKit -framework Foundation -framework CoreGraphics -o "$app/Contents/MacOS/app"
cp "$here/../uikit2/windowed.plist" "$app/Contents/Info.plist"
codesign -s - --force "$app" > /dev/null 2>&1
TAIL1_RECORDS="$build/tail1.json" "$app/Contents/MacOS/app" > "$build/tail1.log" 2>&1 || true
python3 "$here/../foundation2/embed.py" "$build/tail1.json" "$device/tail1-expectations.h"
sed -i.bak 's/foundation2_expectations/tail1_expectations/' "$device/tail1-expectations.h" && rm -f "$device/tail1-expectations.h.bak"
echo "records: $(python3 -c "import json; print(len(json.load(open('$build/tail1.json'))))")"
