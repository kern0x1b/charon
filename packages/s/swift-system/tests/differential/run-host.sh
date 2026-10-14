#!/bin/bash
# Host differential: Apple's System (the macOS SDK) against upstream's System built from the same patched tree as module
# SystemUnderTest, on the same generated inputs. Usage: run-host.sh <SRC> <outdir> [seed]
# <SRC> is the unpacked swift-system 1.8.1 tree with the patches of this recipe applied. The outputs must be identical.
set -u
SRC="$1"; OUT="$2"; SEED="${3:-20261014}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT/run-apple" "$OUT/run-ours"
xcrun clang -c "$SRC/Sources/CSystem/shims.c" -I "$SRC/Sources/CSystem/include" -o "$OUT/shims-host.o" || exit 1
SWIFTS=$(find "$SRC/Sources/System" -name "*.swift" -not -path "*/IORing/*" | sort)
AVAIL=(-enable-experimental-feature "AvailabilityMacro=System 0.0.1:macOS 10.10, iOS 6.1.3")
for v in 0.0.2 0.0.3 1.1.0 1.1.1 1.2.0 1.2.1 1.3.0 1.3.1 1.3.2 1.4.0 1.7.0 199; do
  AVAIL+=(-enable-experimental-feature "AvailabilityMacro=System $v:macOS 10.10, iOS 6.1.3")
done
xcrun swiftc -swift-version 5 -enable-experimental-feature Lifetimes -I "$SRC/Sources/CSystem/include" \
  -D SYSTEM_PACKAGE_DARWIN -D SYSTEM_PACKAGE -module-name SystemUnderTest \
  -emit-library -emit-module -emit-module-path "$OUT/SystemUnderTest.swiftmodule" \
  -o "$OUT/libSystemUnderTest.dylib" "$OUT/shims-host.o" "${AVAIL[@]}" $SWIFTS || exit 1
xcrun swiftc -swift-version 5 "$HERE/main.swift" -o "$OUT/apple-prog" || exit 1
xcrun swiftc -swift-version 5 -D OURS -I "$OUT" -I "$SRC/Sources/CSystem/include" -L "$OUT" -lSystemUnderTest \
  -Xlinker -rpath -Xlinker "$OUT" "$HERE/main.swift" -o "$OUT/ours-prog" || exit 1
"$OUT/apple-prog" "$OUT/run-apple" "$SEED" > "$OUT/apple.txt" 2>&1; echo "apple rc=$?"
"$OUT/ours-prog" "$OUT/run-ours" "$SEED" > "$OUT/ours.txt" 2>&1; echo "ours rc=$?"
if diff "$OUT/apple.txt" "$OUT/ours.txt" > "$OUT/diff.txt"; then echo "DIFFERENTIAL: identical, $(wc -l < "$OUT/apple.txt") lines"; else echo "DIFFERENTIAL: DIFFERENT, $(wc -l < "$OUT/diff.txt") diff lines"; exit 1; fi
