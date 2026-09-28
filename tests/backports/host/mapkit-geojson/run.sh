#!/bin/sh
# The GeoJSON decoder, against the host's own MKGeoJSONDecoder, over the RFC 7946 cases and five
# mutations. The port's own object is compiled with its class names renamed, so the two live in one
# process: Apple's own decoder answers for the unrenamed name beside the port's.
#
# The port's decoder imports <MapKit/MapKit.h> and needs no UIKit, so it compiles for the host
# as it is -- and the cases run against macOS's own MapKit, which is the same Apple's decoder.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/MapKit}
build=${MAPKIT_GEOJSON_BUILD:-${TMPDIR:-/tmp}/charon-mapkit-geojson}
rm -rf "$build"
mkdir -p "$build"
# The port's own source is compiled INTO the probe, with the two class names renamed, so there is one
# translation unit and no question of the object being linked in: Apple's own MKGeoJSONDecoder and
# MKGeoJSONFeature answer for the unrenamed names beside the port's charonHost_* ones.
#
# CHARON_HOST_PROBE: the host's own MapKit declares MKAddressFilter, which the port's own header also
# declares under Apple's name, so the port's declarations of it are skipped here and the host's used --
# the same rule the other probes follow.
xcrun clang -fobjc-arc -Wall -framework Foundation -framework MapKit -framework CoreLocation \
    -I"$port" -DCHARON_HOST_PROBE=1 \
    -DMKGeoJSONDecoder=charonHost_MKGeoJSONDecoder -DMKGeoJSONFeature=charonHost_MKGeoJSONFeature \
    "$port/MKGeoJSONDecoder.m" "$here/differential.m" -o "$build/differential"
"$build/differential" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
