#!/bin/sh
# run.sh - the host differential of the Swift NWInterface (packages/s/swift-runtime/files/Network/NWInterface.swift).
#
# Two halves over the same questions - the interfaces of the first path, their name, index, type, debugDescription, and
# equality with themselves and each other:
#
#   the host half is interfaces-apple.swift against Apple's own NWPathMonitor and NWInterface, from the macOS SDK;
#
#   the port half builds NWInterface.swift and enumerate-helper.swift as the Network module, the way the runtime's recipe
#   builds its overlays (-import-underlying-module, so the C calls are visible), and runs interfaces-port.swift against it.
#   enumerate-helper.swift is test-only: it reads the interfaces through the C monitor, because NWInterface's initialiser
#   is internal, and it is built into the test's module and nothing that ships.
#
# The two outputs are compared with diff. Nothing here runs python. The compiler is the host's, unless SWIFTC is set.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
files=${NETWORK_SWIFT_FILES:-$root/packages/s/swift-runtime/files/Network}
build=${NETWORK_SWIFT_BUILD:-$root/.agent-work/runs/host-network-swift}
swiftc=${SWIFTC:-swiftc}
target=${NETWORK_SWIFT_TARGET:-$(uname -m)-apple-macos26.0}
rm -rf "$build"
mkdir -p "$build/ours"

"$swiftc" -target "$target" -O -o "$build/apple" "$here/interfaces-apple.swift" 2> "$build/apple.err" || {
    echo "FAIL interfaces-apple.swift does not build against Apple's Network:"; grep "error:" "$build/apple.err" | head -6; exit 1; }

"$swiftc" -target "$target" -O -wmo -parse-as-library -module-name Network -Xfrontend -import-underlying-module \
    -emit-module -emit-module-path "$build/ours/Network.swiftmodule" \
    "$files/NWInterface.swift" "$here/enumerate-helper.swift" 2> "$build/ours.err" || {
    echo "FAIL emitting the Network module:"; grep "error:" "$build/ours.err" | head -6; exit 1; }
"$swiftc" -target "$target" -O -wmo -parse-as-library -module-name Network -Xfrontend -import-underlying-module \
    -emit-object -o "$build/ours/Network.o" \
    "$files/NWInterface.swift" "$here/enumerate-helper.swift" 2>> "$build/ours.err" || {
    echo "FAIL building the Network module:"; grep "error:" "$build/ours.err" | head -6; exit 1; }
"$swiftc" -target "$target" -O -I "$build/ours" -o "$build/ours/interfaces" "$build/ours/Network.o" \
    "$here/interfaces-port.swift" 2> "$build/port.err" || {
    echo "FAIL interfaces-port.swift does not build against this tree's NWInterface:"; grep "error:" "$build/port.err" | head -6; exit 1; }

"$build/apple" > "$build/apple.txt" 2>&1 || { echo "FAIL the host binary"; head -5 "$build/apple.txt"; exit 1; }
"$build/ours/interfaces" > "$build/ours.txt" 2>&1 || { echo "FAIL the port binary"; tail -5 "$build/ours.txt"; exit 1; }

echo "apple lines: $(wc -l < "$build/apple.txt"), ours lines: $(wc -l < "$build/ours.txt")"
if diff "$build/apple.txt" "$build/ours.txt"; then
    echo "NWInterface differential: identical"
else
    echo "NWInterface differential: DIFFER"
    exit 1
fi
