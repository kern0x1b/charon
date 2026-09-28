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
# The same 100-step sequence again under AddressSanitizer and UndefinedBehaviorSanitizer, because the
# un-sanitized run is the one that reads a number: the fixture kept its frames in a literal-sized
# array, and a longer sequence wrote past it - which is a segfault with no diagnosis in it. The
# sanitizers name the buffer and the index, and this is what stops it coming back.
clang -fobjc-arc -w -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
    -DCHARON_TRACKER_OFFLINE -DCHARON_TRACKER_SYNTHETIC \
    -I"$ARKit" -I"$sdk/System/Library/Frameworks/ARKit.framework/Headers" \
    "$here/spatial-tracker-diff.m" "$ARKit/CharonARTracker.m" \
    -framework Foundation -framework CoreGraphics -framework CoreMedia -framework CoreVideo \
    -o "$BUILD/tracker-diff-sanitized" || { echo "FAIL: the sanitized build did not link"; exit 1; }
sanitized=$(ASAN_OPTIONS=detect_leaks=0 "$BUILD/tracker-diff-sanitized" 2>&1)
printf '%s\n' "$sanitized" | grep -qE "ERROR: AddressSanitizer|runtime error" && {
    printf '%s\n' "$sanitized" | grep -E "ERROR: AddressSanitizer|runtime error|SUMMARY" | head -3
    echo "FAIL: the sanitized run reports a fault"; exit 1; }
echo "ok the 100-step sequence is clean under AddressSanitizer and UndefinedBehaviorSanitizer"

"$BUILD/tracker-diff" | tee "$BUILD/tracker-diff.txt"
grep -q '^spatial tracker differential' "$BUILD/tracker-diff.txt" || {
    echo "FAIL: the differential printed no verdict"; exit 1; }
grep -q 'tracking: yes' "$BUILD/tracker-diff.txt" || {
    echo "FAIL: the tracker does not report tracking, so its pose is not being carried"; exit 1; }

# The accuracy floor, asserted rather than printed. The error must not grow past what the facts record,
# so a regression that deletes refinePose, halves the step clamp or changes the landmark depth again
# turns this red rather than printing a worse number under a green line. The floor is the delivery's own
# measured value and is deliberately not the target: a tracker at 114 degrees is not right, and the
# gate's job here is to keep it from getting worse while the work that makes it right lands.
# Rotation is read in degrees and distance in metres, which are the units the verdict line prints the
# thresholds in; the line also carries radians, and 2.16 of those is 124 degrees, so reading the wrong
# one would pass a tracker that is nowhere near the truth.
floor() {
    awk -v k="$1" -v limit="$2" -v unit="$3" '
        index($0, k) > 0 { seen = 1
            if (unit == "deg") { if (match($0, /\(([0-9]+\.[0-9]+) deg\)/)) v = substr($0, RSTART + 1, RLENGTH - 6) + 0 }
            else { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+$/) { v = $i + 0; break } }
            if (v == "") { printf "FAIL: no %s in the verdict line for %s\n", unit, k; failed = 1 }
            else if (v > limit) { printf "FAIL: %s is %.5g %s, over the floor of %g\n", k, v, unit, limit; failed = 1 }
            else printf "ok %s is %.5g %s, within the floor of %g\n", k, v, unit, limit
            exit }
        END { if (!seen) { printf "FAIL: the verdict line for %s is not in the output\n", k; exit 1 }
              exit failed ? 1 : 0 }' "$BUILD/tracker-diff.txt"
}
floor "rotation error: mean" 0.01 deg
floor "distance error: mean" 0.70 m

echo "ok the tracker carries its pose, finds its planes, and holds the accuracy floor the facts record"
