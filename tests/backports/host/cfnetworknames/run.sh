#!/bin/sh
# run.sh - the port's seven CFNetwork names (renamed charonHost_*) against the host's own CFNetwork,
# which exports every one of them: the texts this port carries must be the texts the system has.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/CFNetwork}
harness=${CFNETWORKNAMES_HARNESS:-$here/../../device}
build=${CFNETWORKNAMES_BUILD:-$(mktemp -d)}
rm -rf "$build"
mkdir -p "$build"
renames=""
for name in kCFHTTPVersion2_0 kCFHTTPVersion3_0 kCFStreamNetworkServiceTypeCallSignaling \
            kCFStreamPropertyAllowConstrainedNetworkAccess kCFStreamPropertyAllowExpensiveNetworkAccess \
            kCFStreamPropertyConnectionIsExpensive kCFStreamPropertySocketExtendedBackgroundIdleMode; do
    renames="$renames -D$name=charonHost_$name"
done
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -fvisibility=hidden -w $renames -c "$port/CFNetworkNames.m" -o "$build/port.o"
xcrun clang -fobjc-arc -Wall -I"$harness" \
    "$here/differential.m" "$harness/check.m" "$build/port.o" \
    -framework Foundation -o "$build/differential"
"$build/differential"
