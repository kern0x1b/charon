#!/bin/sh
# run.sh — records what the system's own UIKit answers for every case of device/uikitconst-cases.m,
# under Mac Catalyst, and writes the answers where the device test reads them. The reordering inside a live
# collection view is checked on the device, in device/collectiontransition.m.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
xcrun clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w -I"$device" \
    "$here/record.m" "$device/uikitconst-cases.m" -framework UIKit -framework Foundation -framework CoreGraphics -o "$build/record"
(cd "$build" && ./record "$build/uikitconst.json" > "$build/uikitconst.log" 2>&1)
python3 "$here/../foundation2/embed.py" "$build/uikitconst.json" "$device/UIKitConstants-expectations.h"
sed -i.bak 's/foundation2_expectations/UIKitConstants_expectations/' "$device/UIKitConstants-expectations.h" && rm -f "$device/UIKitConstants-expectations.h.bak"
echo "records: $(python3 -c "import json; print(len(json.load(open('$build/uikitconst.json'))))")"
