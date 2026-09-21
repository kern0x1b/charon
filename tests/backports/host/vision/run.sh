#!/bin/sh
# run.sh — records what the system's Vision answers for every case of device/vision-cases.m in a Mac Catalyst binary, writes the answers
# where the device test reads them, then compiles the port's Vision classes under names of their own (Charon<name>) and holds them to the
# same records, with mutants of the port that each have to be told apart.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
vision=${VISION:-$here/../../../../packages/a/apple-backports/Vision}
registry=${REGISTRY:-$here/../../../../packages/a/apple-backports/registry/Vision/ios11.json}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
frameworks="-iframework $sdk/System/iOSSupport/System/Library/Frameworks"
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk $frameworks -fobjc-arc -w"
libs="-framework Foundation -framework CoreGraphics -framework CoreImage -framework CoreVideo -framework ImageIO"

xcrun clang $common -I"$device" "$here/record.m" "$device/vision-cases.m" $libs -framework Vision -o "$build/system"
VISION_RECORDS="$build/system.json" "$build/system"
python3 "$here/../foundation2/embed.py" "$build/system.json" "$device/vision-expectations.h"
sed -i.bak 's/foundation2_expectations/vision_expectations/' "$device/vision-expectations.h" && rm -f "$device/vision-expectations.h.bak"
echo "records: $(python3 -c "import json; print(len(json.load(open('$build/system.json'))))")"

python3 - "$registry" "$build/rename.h" <<'PY'
import json, sys
names = set()
for entry in json.load(open(sys.argv[1]))["entries"]:
    if entry["kind"] in ("class", "constant", "function"):
        names.add(entry["api"].replace("()", ""))
with open(sys.argv[2], "w") as out:
    for name in sorted(names):
        out.write("#define %s Charon%s\n" % (name, name))
PY

port() {
    dir=$1
    xcrun clang $common -include "$build/rename.h" -I"$device" -I"$vision" "$here/record.m" "$device/vision-cases.m" \
        "$dir/VNConstants.m" "$dir/VNObservations.m" "$dir/VNRecognizedObjectObservation.m" "$dir/VNRequests.m" "$dir/VNHandlers.m" $libs -o "$dir/run"
}
mkdir -p "$build/port"
cp "$vision"/*.m "$vision/CharonVision.h" "$build/port/"
port "$build/port"
VISION_RECORDS="$build/port.json" "$build/port/run"
if cmp -s "$build/system.json" "$build/port.json"; then echo "port: same as the system"; else
    python3 - "$build/system.json" "$build/port.json" <<'PY'
import json, sys
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
for key in sorted(a):
    if a[key] != b.get(key):
        print("DIFF", key)
        print("  system", a[key][:400])
        print("  port  ", str(b.get(key))[:400])
PY
    echo "port: DIFFERS"; exit 1
fi

survived=0
mutant() {
    file=$1; from=$2; to=$3
    rm -rf "$build/mutant"; mkdir -p "$build/mutant"
    cp "$vision"/*.m "$vision/CharonVision.h" "$build/mutant/"
    python3 - "$build/mutant/$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
assert old in text, old
open(path, "w").write(text.replace(old, new, 1))
PY
    port "$build/mutant"
    rm -f "$build/mutant.json"
    VISION_RECORDS="$build/mutant.json" timeout 60 "$build/mutant/run" > /dev/null 2>&1 || true
    if cmp -s "$build/system.json" "$build/mutant.json"; then echo "MUTANT SURVIVED: $file $from -> $to"; survived=$((survived + 1)); fi
}
mutant VNConstants.m "return CGPointMake(normalizedPoint.x * (double)imageWidth, normalizedPoint.y * (double)imageHeight);" "return CGPointMake(normalizedPoint.x * (double)imageHeight, normalizedPoint.y * (double)imageWidth);"
mutant VNConstants.m "x = imageRect.origin.x / (double)imageWidth;" "x = imageRect.origin.x / (double)imageHeight;"
mutant VNConstants.m "if (imageWidth) {" "if (imageWidth > 1) {"
mutant VNConstants.m "faceBoundingBox.origin.x * width + faceBoundingBox.size.width * width * (double)faceLandmarkPoint.x" "faceBoundingBox.size.width * width * (double)faceLandmarkPoint.x"
mutant VNConstants.m "faceBoundingBox.size.height * (double)imageHeight * (double)faceLandmarkPoint.y" "faceBoundingBox.size.height * (double)imageHeight * (double)faceLandmarkPoint.x"
mutant VNConstants.m 'VNBarcodeSymbology const VNBarcodeSymbologyQR = @"VNBarcodeSymbologyQR";' 'VNBarcodeSymbology const VNBarcodeSymbologyQR = @"QR";'
mutant VNConstants.m "return CGRectEqualToRect(normalizedRect, CGRectMake(0, 0, 1, 1));" "return normalizedRect.size.width == 1;"
mutant VNRequests.m "_minimumAspectRatio = 0.5f;" "_minimumAspectRatio = 0.4f;"
mutant VNRequests.m "_quadratureTolerance = 30;" "_quadratureTolerance = 45;"
mutant VNRequests.m "_maximumObservations = 1;" "_maximumObservations = 2;"
mutant VNRequests.m "_minimumSize = 0.2f;" "_minimumSize = 0.25f;"
mutant VNRequests.m "_trackingLevel = VNRequestTrackingLevelFast;" "_trackingLevel = VNRequestTrackingLevelAccurate;"
mutant VNRequests.m "_regionOfInterest = CGRectMake(0, 0, 1, 1);" "_regionOfInterest = CGRectMake(0, 0, 1, 0.5);"
mutant VNRequests.m "_imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop;" "_imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFit;"
mutant VNRequests.m "_symbologies = [[self class] supportedSymbologies];" "_symbologies = @[];"
mutant VNRequests.m "copy->_results = nil;" "copy->_results = nil; copy->_usesCPUOnly = NO;"
mutant VNObservations.m "_confidence = 1;" "_confidence = 0.5f;"
mutant VNObservations.m "_requestRevision = requestRevision;" "_requestRevision = requestRevision + 1;"
mutant VNObservations.m "return [self observationWithRequestRevision:0 boundingBox:boundingBox];" "return [self observationWithRequestRevision:1 boundingBox:boundingBox];"
mutant VNObservations.m "return YES;" "return NO;"
mutant VNObservations.m "return charon_vision_clone(self, zone);" "return [[VNObservation alloc] init];"
mutant VNHandlers.m "VNErrorUnsupportedRevision" "VNErrorNotImplemented"
mutant VNHandlers.m "if (handler)
            handler(request, failure);" "if (handler)
            handler(request, nil);"
mutant VNHandlers.m "succeeded = NO;" "succeeded = YES;"
echo "mutants surviving: $survived"
[ "$survived" -eq 0 ]
