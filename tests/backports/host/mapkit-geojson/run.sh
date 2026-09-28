#!/bin/sh
# The GeoJSON decoder, against the host's own MKGeoJSONDecoder, over the RFC 7946 cases and five
# mutations -- in two processes, because the port's decoder carries Apple's own class name and
# macOS's MapKit has one of the same name.
#
# The port's decoder is built as a DYSLIB here, loaded with RTLD_LOCAL, and every case is run twice:
# once with it loaded and once without, and the two transcripts compared. Nothing is renamed and
# nothing is linked statically, so neither side's class is disturbed -- which is the whole of what the
# first version of this probe got wrong.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../.agent-work/plan-and-analysis/geojson}
build=${MAPKIT_GEOJSON_BUILD:-${TMPDIR:-/tmp}/charon-mapkit-geojson}
rm -rf "$build"
mkdir -p "$build"
# The port's own decoder, as a MACOS dylib: a macOS process will not load an iOS one
# ("incompatible platform (have 'iOS', need 'macOS')", which is what the first version of this probe
# hit). Nothing is renamed, and the class symbols are the ones the port itself exports.
#
# The device half -- that the same source compiles for armv7-apple-ios6.0 with the package's flags --
# is NOT repeated here: that is what the package gate builds, and repeating it in a probe only
# duplicates it with different flags. (Building an iOS dylib in a probe also wants libarclite for ARC
# below iOS 7, which neither the Command Line Tools' clang nor charon's LLVM ships.)
#
# CHARON_HOST_PROBE: the host's MapKit declares MKAddressFilter, which the port's own header also
# declares under Apple's name, so on a host the host's declaration is used.
xcrun clang -fobjc-arc -Wall -fPIC -dynamiclib \
    -DCHARON_HOST_PROBE=1 -I"$port" \
    -framework Foundation -framework MapKit -framework CoreLocation \
    "$port/MKGeoJSONDecoder.m" -o "$build/libGeoJSONBackport.dylib" 2>"$build/dylib.log" || {
        grep -m3 error: "$build/dylib.log" || true; exit 1; }

# The host's own runner: the same program with no dylib loaded answers with Apple's own decoder.
xcrun clang -fobjc-arc -Wall \
    -framework Foundation -framework MapKit -framework CoreLocation \
    "$here/runner.m" -o "$build/host-runner" 2>"$build/host.log" || { grep -m3 error: "$build/host.log" || true; exit 1; }
xcrun clang -fobjc-arc -Wall \
    -framework Foundation -framework MapKit -framework CoreLocation \
    -ldl "$here/runner.m" -o "$build/port-runner" 2>>"$build/port.log" || {
        grep -m3 error: "$build/port.log" || true; exit 1; }

checks=0
# The dylib really loaded: if it did not, every case would silently answer with Apple's own.

failures=0
log="$build/log"
: > "$log"
compare() {
    name=$1; json=$2; expect=$3
    checks=$((checks + 1))
    "$build/host-runner" "$name" "$json" > "$build/host.txt" 2>&1 || true
    CHARON_PORT_DYLIB="$build/libGeoJSONBackport.dylib" DYLD_INSERT_LIBRARIES="$build/libGeoJSONBackport.dylib" \
        "$build/port-runner" "$name" "$json" > "$build/port.txt" 2>&1 || true
    # The port's image and Apple's own will be named differently, and so will the errors the two
    # word differently, so only the DECISION and the geometry are compared.
    port_image=$(awk '/^  decoder_class_image/{print $2}' "$build/port.txt" | head -1)
    if [ "$port_image" = "/System/Library/Frameworks/MapKit.framework/Versions/A/MapKit" ]; then
        echo "FAIL $name: the port process answered with Apple's own decoder -- the dylib did not load" >> "$log"
        failures=$((failures + 1))
        continue
    fi
    host_refused=$(awk '/^  refused/{print $2}' "$build/host.txt" | head -1)
    port_refused=$(awk '/^  refused/{print $2}' "$build/port.txt" | head -1)
    host_count=$(awk '/^  count/{print $2}' "$build/host.txt" | head -1)
    port_count=$(awk '/^  count/{print $2}' "$build/port.txt" | head -1)
    if [ "$expect" = "refused" ]; then
        if [ "$port_refused" = "1" ]; then
            echo "ok $name: the port refused it, and the host $([ "$host_refused" = 1 ] && echo did too || echo did not, which the facts record)" >> "$log"
        else
            echo "FAIL $name: the port did not refuse a document it must" >> "$log"
            failures=$((failures + 1))
        fi
        continue
    fi
    if [ "$port_count" != "$host_count" ]; then
        echo "FAIL $name: the port decoded $port_count objects where the host decoded $host_count" >> "$log"
        failures=$((failures + 1))
        continue
    fi
    awk '/^      point/{print}' "$build/host.txt" > "$build/host-points.txt"
    awk '/^      point/{print}' "$build/port.txt" > "$build/port-points.txt"
    if ! cmp -s "$build/host-points.txt" "$build/port-points.txt"; then
        echo "FAIL $name: the coordinates differ from the host's" >> "$log"
        diff "$build/host-points.txt" "$build/port-points.txt" | head -4 >> "$log"
        failures=$((failures + 1))
        continue
    fi
    awk '/^    identifier|^    shapes|^    shape/{print}' "$build/host.txt" > "$build/host-members.txt"
    awk '/^    identifier|^    shapes|^    shape/{print}' "$build/port.txt" > "$build/port-members.txt"
    if ! cmp -s "$build/host-members.txt" "$build/port-members.txt"; then
        echo "FAIL $name: the features' own members differ from the host's" >> "$log"
        diff "$build/host-members.txt" "$build/port-members.txt" | head -4 >> "$log"
        failures=$((failures + 1))
        continue
    fi
    echo "ok $name: $port_count objects, same shapes and same coordinates as the host" >> "$log"
}

# RFC 7946 3.1.1: a position is [longitude, latitude] with an optional elevation.
compare "Point" '{"type":"Point","coordinates":[-122.4194,37.7749,10]}' "ok"
compare "Point, two elements" '{"type":"Point","coordinates":[2.3522,48.8566]}' "ok"
compare "LineString" '{"type":"LineString","coordinates":[[-77.03,38.9],[-77.05,38.91]]}' "ok"
compare "MultiLineString" '{"type":"MultiLineString","coordinates":[[[102,2],[103,3],[104,5],[106,7]]]}' "ok"
compare "Polygon" '{"type":"Polygon","coordinates":[[[-0.1,0.0],[-0.1,0.1],[0.1,0.1],[0.1,0.0],[-0.1,0.0]]]}' "ok"
compare "Polygon with a hole" '{"type":"Polygon","coordinates":[[[-0.1,0.0],[-0.1,0.3],[0.3,0.3],[0.3,0.0],[-0.1,0.0]],[-0.05,0.05],[-0.05,0.15],[0.15,0.15],[0.15,0.05],[-0.05,0.05]]}' "ok"
compare "Feature with a point" '{"type":"Feature","geometry":{"type":"Point","coordinates":[13.4,52.5]},"properties":{"name":"Berlin"},"id":"berlin"}' "ok"
compare "Feature with a line" '{"type":"Feature","geometry":{"type":"LineString","coordinates":[[13.4,52.5],[13.5,52.6]]},"properties":{}}' "ok"
compare "Feature with a null geometry" '{"type":"Feature","geometry":null,"properties":{"name":"nowhere"}}' "ok"
compare "FeatureCollection" '{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},"properties":{}},{"type":"Feature","geometry":{"type":"Point","coordinates":[3,4]},"properties":{}}]}' "ok"
compare "an array at the top level" '[{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},"properties":{}}]' "ok"
compare "a geometry object at the top level" '{"type":"Point","coordinates":[7,8]}' "ok"

# THE MUTATIONS: documents that must be REFUSED, so a decoder that half-decodes and hands back a
# shape the document did not describe is caught. A MultiPoint is refused on this device and not by the
# host, which is the measured difference the facts record.
compare "MUTATION a ring that is not closed" '{"type":"Polygon","coordinates":[[[-0.1,0.0],[-0.1,0.1],[0.1,0.1]]]}' "refused"
compare "MUTATION a ring of three positions" '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1]]]}' "refused"
compare "MUTATION a position that is not two numbers" '{"type":"Point","coordinates":["a","b"]}' "refused"
compare "MUTATION a geometry type that is not one of the seven" '{"type":"Rectangle","coordinates":[[0,0],[1,1]]}' "refused"
compare "MUTATION data that is not JSON" "{not json at all" "refused"
compare "MUTATION a MultiPoint, which this device cannot build" '{"type":"MultiPoint","coordinates":[[-105,40],[-101,41]]}' "refused"

grep -v "^ok " "$log" || true
echo "$checks checks, $failures failures"
echo "log=$log"
[ "$failures" = "0" ]
