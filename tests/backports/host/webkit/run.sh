#!/bin/sh
# run.sh — records what the system's WKWebView does for every case of device/webkit-cases.m, under Mac Catalyst,
# and writes the answers where the device test reads them, so the port over UIWebView is held to the same ones.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
xcrun clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w -I"$device" \
    "$here/record.m" "$device/webkit-cases.m" -framework UIKit -framework WebKit -framework Foundation -o "$build/record"
(cd "$build" && ./record "$build/webkit.json" > "$build/webkit.log" 2>&1)
python3 "$here/../foundation2/embed.py" "$build/webkit.json" "$device/webkit-expectations.h"
sed -i.bak 's/foundation2_expectations/webkit_expectations/' "$device/webkit-expectations.h" && rm -f "$device/webkit-expectations.h.bak"
echo "records: $(python3 -c "import json,sys; print(len(json.load(open('$build/webkit.json'))))")"
