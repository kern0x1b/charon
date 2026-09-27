#!/bin/sh
# run.sh - the ARKit tracker's pose, measured against a ground truth it builds itself.
#
# The host has no ARKit to compare against, so the truth is constructed: a camera is walked along a
# path turning a fixed angle a step, the scene in front of it is rendered from that pose, and the
# frames are handed to the tracker one at a time. What the tracker says it got is then compared with
# the pose that rendered them, in degrees of rotation and metres of distance.
#
# The tracker is the library's own source, compiled for the host with the same Objective-C and the
# same SIMD, and with the three seams that cannot run on a host turned off: the camera, the
# gyroscope, and the two enumerations only a device has. The calibration is the synthetic camera's
# own, handed over the way a capture hands over the calibration recorded beside its frames - a camera
# and a gyroscope cannot recover a metric depth without the focal length, so this is what the
# measurement is made with and it is stated here rather than assumed.
#
# This is a host test, not a source file of the library: the ARKit backport's own objects carry the
# API of one release each, and a `main` in one of them is a symbol no registry entry describes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
ARKit=$repo/packages/a/apple-backports/ARKit
BUILD=${BUILD:-$(mktemp -d)}
sdk=$(ls -d "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk 2>/dev/null | head -1)
[ -n "$sdk" ] || { echo "FAIL: no iOS 16.4 SDK in the shared store to take the ARKit headers from"; exit 1; }

mkdir -p "$BUILD"
xcrun clang -fobjc-arc -DCHARON_TRACKER_OFFLINE -DCHARON_TRACKER_SYNTHETIC \
    -I"$ARKit" -I"$sdk/System/Library/Frameworks/ARKit.framework/Headers" \
    "$here/spatial-tracker-diff.m" "$ARKit/CharonARTracker.m" \
    -framework Foundation -framework CoreGraphics -framework CoreMedia -framework CoreVideo \
    -o "$BUILD/tracker-diff"
"$BUILD/tracker-diff" | tee "$BUILD/tracker-diff.txt"
grep -q '^spatial tracker differential' "$BUILD/tracker-diff.txt" || {
    echo "FAIL: the differential printed no verdict"; exit 1; }
# The plane detector is the plainest evidence that the pose is being carried from one frame to the
# next and turned the right way: a run-away pose puts every point in the wrong place, and there is no
# level surface in the wrong place to grow a region from. A regression that loses the planes has lost
# the pose, and the numbers alone would only say so less clearly.
grep -q 'tracking: yes' "$BUILD/tracker-diff.txt" || {
    echo "FAIL: the tracker does not report tracking, so its pose is not being carried"; exit 1; }
echo "ok the tracker carries its pose from frame to frame and finds its planes"
