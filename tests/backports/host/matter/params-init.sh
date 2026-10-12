#!/bin/sh
# matter/params-init.sh - the designated initialiser of MTRSubscribeParams, the framework's and the port's, compared on this
# host. The questions and the oracle are in params-init.m.
#
# The port's side is the committed CharonMatterMTRSubscribeParams.m, byte for byte, compiled for the host with its class
# name aliased onto CharonPortMTRSubscribeParams, and linked with params-init.m into one program that also holds the
# framework's own MTRSubscribeParams. CharonMatterTypes.h is replaced by an empty header, as behaviour.sh does: the host's
# SDK declares everything that header would.
#
#   sh tests/backports/host/matter/params-init.sh
#   PARAMS_INIT_BUILD=<dir>   where the program and its output go (default .agent-work/runs/params-init)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${PARAMS_INIT_BUILD:-$root/.agent-work/runs/params-init}
host_sdk=$(xcrun --show-sdk-path)
[ -d "$host_sdk/System/Library/Frameworks/Matter.framework" ] || {
    echo "params-init: this host has no Matter.framework, so there is no oracle." >&2
    exit 2; }
port="$root/packages/a/apple-backports/Matter/CharonMatterMTRSubscribeParams.m"
[ -f "$port" ] || { echo "params-init: no committed $port" >&2; exit 2; }

rm -rf "$build"
mkdir -p "$build/port"
cp "$port" "$build/port/"
printf '// the host SDK declares every class this header would declare for the library SDK\n' \
    > "$build/port/CharonMatterTypes.h"
xcrun clang -target arm64-apple-macos26.0 -isysroot "$host_sdk" -fobjc-arc -O1 -g -Wall -Wno-nonnull \
    -Wno-objc-protocol-property-synthesis -Wno-incomplete-implementation \
    -DMTRSubscribeParams=CharonPortMTRSubscribeParams -I"$build/port" \
    -c "$build/port/CharonMatterMTRSubscribeParams.m" -o "$build/port.o"
xcrun clang -target arm64-apple-macos26.0 -isysroot "$host_sdk" -fobjc-arc -O1 -g -Wall \
    -Wno-deprecated-declarations "$here/params-init.m" "$build/port.o" \
    -framework Foundation -framework Matter -o "$build/params-init"
status=0
"$build/params-init" > "$build/out.txt" 2>&1 || status=$?
cat "$build/out.txt"
[ "$status" -eq 0 ] && echo "params-init: the port's initialiser answers as the framework does" \
    || echo "params-init: DIFFERENT - see the lines above"
exit "$status"
