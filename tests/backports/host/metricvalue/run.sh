#!/bin/sh
# run.sh — a host differential for the shared value machinery (packages/a/apple-backports/CharonValueStore.h)
# and for the MetricKit value classes built on it.
#
# What the host can answer: the system's own MetricKit writing a value nothing measured, which is an
# empty object — measured, an MXCPUMetric and an MXMetricPayload this process never filled in give
# -dictionaryRepresentation with no keys and -JSONRepresentation that parses as {}. The port must
# answer that the same way.
#
# What the host cannot answer is a populated value: nothing on the host populates one either, so the
# filled-in half is checked against the port's own contract — exactly the properties the SDK header
# declares, the JSON agreeing with the dictionary, and the archive round trip. The key spelling is a
# choice, and the case file says why.
#
# The three mutations are of the shared machinery itself, which is the point of having it in one
# header: a change to the conversion table or the property walk has to change a record here, or the
# header is not holding anything.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
metrickit=${METRICKIT:-$here/../../../../packages/a/apple-backports/MetricKit}
store=${STORE:-$here/../../../../packages/a/apple-backports/CharonValueStore.h}
registry=${REGISTRY:-$here/../../../../packages/a/apple-backports/registry/MetricKit/ios13.json}
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path --sdk macosx)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -F $sdk/System/Library/Frameworks -iframework $sdk/System/iOSSupport/System/Library/Frameworks -fobjc-arc -w"
libs="-framework Foundation -framework MetricKit"

xcrun clang $common "$here/record.m" "$here/cases.m" $libs -o "$build/system"
METRICVALUE_RECORDS="$build/system.json" "$build/system"
echo "records: $(python3 -c "import json; print(len(json.load(open('$build/system.json'))))")"

python3 "$here/rename.py" "$registry" "$build/rename.h"
port() {
    dir=$1
    xcrun clang $common -DCHARON_METRICVALUE_PORT=1 -DCHARON_HOST_DIFFERENTIAL=1 -include "$build/rename.h" -I"$here" -I"$dir" -I"$metrickit" \
        "$here/record.m" "$here/cases.m" "$dir"/*.m $libs -o "$dir/run"
}
rm -rf "$build/port"; mkdir -p "$build/port"
cp "$metrickit"/*.m "$metrickit"/*.h "$build/port/"
cp "$store" "$build/CharonValueStore.h"
port "$build/port"
METRICVALUE_RECORDS="$build/port.json" "$build/port/run"
python3 "$here/compare.py" "$build/system.json" "$build/port.json"

survived=0
mutant() {
    label=$1; from=$2; to=$3
    rm -rf "$build/mutant"; mkdir -p "$build/mutant"
    cp "$metrickit"/*.m "$metrickit"/*.h "$build/mutant/"
    cp "$store" "$build/mutant/CharonValueStore.h"
    python3 "$here/mutate.py" "$build/mutant/CharonValueStore.h" "$from" "$to" >/dev/null
    port "$build/mutant"
    rm -f "$build/mutant.json"
    METRICVALUE_RECORDS="$build/mutant.json" timeout 60 "$build/mutant/run" >/dev/null 2>&1 || true
    if cmp -s "$build/port.json" "$build/mutant.json"; then echo "MUTANT SURVIVED: $label"; survived=$((survived + 1)); fi
}
mutant "the date becomes a wall-clock reading" "@([(NSDate *)value timeIntervalSinceReferenceDate])" "@([(NSDate *)value timeIntervalSince1970])"
mutant "a measurement becomes a string" "return @([(NSMeasurement *)value doubleValue]);" "return [value description];"
mutant "the walk stops at the object's own class" "for (Class current = cls; current && current != [NSObject class]; current = class_getSuperclass(current))" "for (Class current = cls; current; current = current == cls ? NULL : class_getSuperclass(current))"
if [ "$survived" -ne 0 ]; then echo "$survived mutations of the shared value machinery survived; the differential is not holding"; exit 1; fi
echo "mutations: all caught"
