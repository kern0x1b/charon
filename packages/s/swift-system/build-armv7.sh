#!/bin/bash
# Builds upstream's System module (and its C shim CSystem) for armv7 iOS 6.1.3 with the port's Swift toolchain.
# Usage: build-armv7.sh <outdir>. Every input is an environment variable; nothing is looked up on the machine:
#   SRC      the unpacked swift-system 1.8.1 tree with the patches of this recipe applied
#   SWIFTC   charon@swift's swiftc (6.4.0)        CLANG   a clang for the C shim (the port's llvm)
#   RES      the resource dir of charon@swift-runtime's install (lib/swift)
#   LAYOUTS  the legacy layout file for armv7 (the toolchain's share/swift-source/stdlib/toolchain/legacy_layouts/iphoneos)
#   LD64     charon@ld64's arm-apple-darwin11-ld      SDK  iPhoneOS 16.4 SDK (the armv7 lift's)
set -u
for v in SRC SWIFTC CLANG RES LAYOUTS LD64 SDK; do
  eval "val=\${$v:-}"; [ -n "$val" ] || { echo "build-armv7.sh: $v is not set" >&2; exit 2; }
done
OUT="$1"; mkdir -p "$OUT"
TARGET=armv7-apple-ios6.1.3

# The legacy layout file is read from the resource dir; the runtime install does not carry it, so an overlay of
# symlinks holds it beside the runtime's own files (the runtime package is not changed).
overlay="$OUT/resource"
rm -rf "$overlay"; mkdir -p "$overlay/iphoneos"
for e in "$RES"/*; do [ "$(basename "$e")" = iphoneos ] || ln -s "$e" "$overlay/"; done
for e in "$RES"/iphoneos/*; do ln -s "$e" "$overlay/iphoneos/"; done
cp "$LAYOUTS" "$overlay/iphoneos/layouts-armv7.yaml"

# Availability: upstream's Package.swift maps each release to the platforms it names. The port builds for 6.1.3, so every
# System release maps to iOS 6.1.3; the calls the 6.1.3 libSystem lacks are then measured by the import check, not hidden here.
SRC_AVAIL="macOS 10.10, iOS 6.1.3"
AVAIL=(-enable-experimental-feature "AvailabilityMacro=System 0.0.1:$SRC_AVAIL")
for v in 0.0.2 0.0.3 1.1.0 1.1.1 1.2.0 1.2.1 1.3.0 1.3.1 1.3.2 1.4.0 1.7.0 199; do
  AVAIL+=(-enable-experimental-feature "AvailabilityMacro=System $v:$SRC_AVAIL")
done

"$CLANG" -target $TARGET -isysroot "$SDK" -c "$SRC/Sources/CSystem/shims.c" -I "$SRC/Sources/CSystem/include" -o "$OUT/shims.o" \
  || { echo "BUILD: clang failed"; exit 1; }
SWIFTS=$(find "$SRC/Sources/System" -name "*.swift" -not -path "*/IORing/*" | sort)
# Swift 5 language mode: upstream's Package.swift asks for 6, where SDK 16.4's mach_task_self_ (a plain extern var) is
# refused as not concurrency-safe (MachPort.swift, 7 sites). A mode change, not a source change; see the report.
# The runtime flags are charon@swift-runtime's (no Swift compatibility packs, bundled runtime).
"$SWIFTC" -target $TARGET -sdk "$SDK" -resource-dir "$overlay" -module-name System -swift-version 5 \
  -enable-experimental-feature Lifetimes -I "$SRC/Sources/CSystem/include" \
  -D SYSTEM_PACKAGE_DARWIN -D SYSTEM_PACKAGE -Xfrontend -disable-availability-checking \
  -Xfrontend -bundled-swift-runtime -runtime-compatibility-version none \
  -disable-autolinking-runtime-compatibility-dynamic-replacements -Xfrontend -disable-autolinking-runtime-compatibility-concurrency \
  -use-ld="$LD64" -emit-library -emit-module -emit-module-path "$OUT/System.swiftmodule" \
  -o "$OUT/libswiftSystem.dylib" "$OUT/shims.o" "${AVAIL[@]}" $SWIFTS || { echo "BUILD: swiftc failed"; exit 1; }
echo "BUILD: ok $OUT"
