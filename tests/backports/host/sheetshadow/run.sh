#!/bin/sh
# run.sh - asks the host's UIKit and Core Animation, under Mac Catalyst, what UIKit's "magic" sheet shadow is made of, and
# checks that the vibrant colour matrix 16.0 gives it (-[_UIShadowView _updateShadowVisualStyling], with the lower
# intensity the sheet's drop shadow view sets) takes its colour from what lies behind the layer: over red, blue, grey and
# white it leaves the matrix of that destination, laid over it with the layer's alpha, not the layer's own black. A
# colour matrix that makes the layer red is the control that the capture shows filters at all. The port cannot draw what
# a filter reads from behind a layer on iOS 6 (facts/UIKit/UISheetPresentationController.md); this fails if the host
# ever stops reading the destination.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
app="$build/sheetshadow.app"
mkdir -p "$app/Contents/MacOS"
xcrun clang -target arm64-apple-ios16.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w \
    "$here/record.m" -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -o "$app/Contents/MacOS/app"
cp "$here/record.plist" "$app/Contents/Info.plist"
codesign -s - --force "$app" > /dev/null 2>&1
timeout 60 "$app/Contents/MacOS/app"
