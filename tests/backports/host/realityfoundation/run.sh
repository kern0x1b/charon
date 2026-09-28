#!/bin/sh
# run.sh — the RealityFoundation/RealityKit overlays, compiled the way packages/s/swift-runtime
# builds them: two modules, RealityFoundation first, then RealityKit on top of it, then the harness
# linked against both.
#
# Two modules, not one. The one-unit build (every source of both modules in one invocation) is what
# this host test used to do, and it is not what the package does, and the difference is not
# cosmetic: in the one-unit build Accessibility.swift's component does not satisfy `Component`
# ("subscript 'subscript(_:)' requires that 'Entity.AccessibilityComponent' conform to 'Component'",
# 6 errors), while the same file in the two-module build the package performs compiles with none.
# Under Apple's swiftlang driver the one-unit build refuses outright as well - "module
# 'RealityFoundation' is an implementation detail of 'RealityKit'". The package's shape is the
# authoritative one, so this is that shape.
#
# The compiler is the Swift 6.4.0 the package builds with (charon@swift 6.4.0, swift-6.4-RELEASE),
# named rather than taken from PATH; RF_SWIFTC overrides it.
#
# What this is not: a system comparison - no release before iOS 13 carries either module and the
# 26.2 one is an interface with no implementation to run. main.swift says so at its top.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
files=${RF_OVERLAY_FILES:-$here/../../../../packages/s/swift-runtime/files}
build=${RF_BUILD:-${TMPDIR:-/tmp}/charon-realityfoundation-host}
sdk=${RF_SDK:-$(xcrun --show-sdk-path)}
target=${RF_TARGET:-$(uname -m)-apple-macos14}
swiftc=${RF_SWIFTC:-$HOME/.xmake/packages/s/swift/6.4.0/f1d0e4f9eebe477396350986a88081e5/bin/swiftc}
[ -x "$swiftc" ] || swiftc=swiftc
[ -d "$sdk" ] || sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
rm -rf "$build"
mkdir -p "$build"

sources() { # every source of both overlays, as words
    for source in "$files"/RealityFoundation/*.swift "$files"/RealityKit/*.swift; do printf '%s ' "$source"; done
}

common="-target $target -sdk $sdk -swift-version 5 -parse-as-library -O -wmo"

# RealityFoundation (xmake.lua:700)
# shellcheck disable=SC2086
"$swiftc" $common -module-name RealityFoundation -emit-module \
    -emit-module-path "$build/RealityFoundation.swiftmodule" -emit-object -o "$build/RealityFoundation.o" \
    $(for source in "$files"/RealityFoundation/*.swift; do printf '%s ' "$source"; done)

# RealityKit (xmake.lua:717)
# shellcheck disable=SC2086
"$swiftc" $common -module-name RealityKit -I "$build" -emit-module \
    -emit-module-path "$build/RealityKit.swiftmodule" -emit-object -o "$build/RealityKit.o" \
    $(for source in "$files"/RealityKit/*.swift; do printf '%s ' "$source"; done)

# the harness: top-level code in its own main.swift, so no -parse-as-library here
# shellcheck disable=SC2086
"$swiftc" -target "$target" -sdk "$sdk" -swift-version 5 -I "$build" \
    -o "$build/rf-check" "$build/RealityFoundation.o" "$build/RealityKit.o" "$here/main.swift"

"$build/rf-check" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
