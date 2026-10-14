#!/bin/bash
# Builds upstream's System module, its C shim, and the apple-compat calls 6.1.3 lacks, for armv7 iOS 6.1.3, the way
# rules/swift builds a port's Swift: objects with -c against the runtime's own resource dir, linked with the port's
# linker into libswiftSystem.dylib. Usage: build-armv7.sh <outdir>. Every input is an environment variable:
#   SRC          the swift-system 1.8.1 tree with this recipe's patches applied
#   APPLE_COMPAT packages/a/apple-compat of this tree
#   SWIFTC       charon@swift's swiftc (6.4.0)     CLANG  the port's clang (llvm)
#   RES          the resource dir of charon@swift-runtime's install (lib/swift)
#   LD64         charon@ld64's arm-apple-darwin11-ld
#   SDK          the iPhoneOS 16.4 SDK (the armv7 lift's)
set -u
for v in SRC APPLE_COMPAT SWIFTC CLANG RES LD64 SDK; do
  eval "val=\${$v:-}"; [ -n "$val" ] || { echo "build-armv7.sh: $v is not set" >&2; exit 2; }
done
OUT="$1"; mkdir -p "$OUT"
TARGET=armv7-apple-ios6.1.3
CF=(-target $TARGET -isysroot "$SDK" -miphoneos-version-min=6.1.3 -I "$APPLE_COMPAT/include" -I "$SRC/Sources/CSystem/include")

# The calls 6.1.3 lacks come from apple-compat (fstatat, unlinkat, fdopendir, through F_GETPATH), and the mach port guards
# are weak references: the 6.1.3 export list has no wrapper for them, so the wrappers answer KERN_NOT_SUPPORTED there.
for f in openat unlinkat fdopendir fstatat; do
  "$CLANG" "${CF[@]}" -c "$APPLE_COMPAT/src/$f.c" -o "$OUT/compat-$f.o" || { echo "BUILD: compat $f failed"; exit 1; }
done
for f in shims csystem_port; do
  "$CLANG" "${CF[@]}" -c "$SRC/Sources/CSystem/$f.c" -o "$OUT/$f.o" || { echo "BUILD: clang $f failed"; exit 1; }
done

# Availability: upstream's Package.swift asks for iOS 8.0 and up. Its own declarations (FilePath, Errno, CInterop) are used
# unannotated inside the module, so at a 6.1.3 target that is a compile error (measured: 13 SystemString.swift errors, and
# more); every release therefore maps to iOS 6.1.3, and the libSystem import check is what says which calls 6.1.3 lacks.
AVAIL=(-enable-experimental-feature "AvailabilityMacro=System 0.0.1:macOS 10.10, iOS 6.1.3")
for v in 0.0.2 0.0.3 1.1.0 1.1.1 1.2.0 1.2.1 1.3.0 1.3.1 1.3.2 1.4.0 1.7.0 199; do
  AVAIL+=(-enable-experimental-feature "AvailabilityMacro=System $v:macOS 10.10, iOS 6.1.3")
done

SWIFTS=$(find "$SRC/Sources/System" -name "*.swift" -not -path "*/IORing/*" | sort)
"$SWIFTC" -target $TARGET -sdk "$SDK" -resource-dir "$RES" -module-name System -swift-version 6 \
  -enable-experimental-feature Lifetimes -I "$SRC/Sources/CSystem/include" -I "$APPLE_COMPAT/include" \
  -D SYSTEM_PACKAGE_DARWIN -D SYSTEM_PACKAGE -Xfrontend -bundled-swift-runtime -runtime-compatibility-version none \
  -Xfrontend -disable-autolinking-runtime-compatibility-concurrency -disable-autolinking-runtime-compatibility-dynamic-replacements \
  -wmo -parse-as-library "${AVAIL[@]}" -c $SWIFTS -o "$OUT/System.o" || { echo "BUILD: swift objects failed"; exit 1; }

"$CLANG" -target $TARGET -isysroot "$SDK" -miphoneos-version-min=6.1.3 -dynamiclib -fuse-ld="$LD64" \
  -install_name @rpath/libswiftSystem.dylib -o "$OUT/libswiftSystem.dylib" "$OUT/System.o" "$OUT"/compat-*.o "$OUT/shims.o" "$OUT/csystem_port.o" \
  -L "$RES/iphoneos" -lswiftCore -lswiftDarwin -lswiftObjectiveC -lswiftDispatch -lswift_Concurrency \
  || { echo "BUILD: link failed"; exit 1; }
echo "BUILD: ok $OUT/libswiftSystem.dylib"
