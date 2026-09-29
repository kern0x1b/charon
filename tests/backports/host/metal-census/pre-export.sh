#!/bin/sh
# pre-export.sh - the two checks the 6.1.3 gate found that neither a compile nor a review could see.
#
#     sh tests/backports/host/metal-census/pre-export.sh
#
# Run from packages/a/apple-backports. It compiles every .m of Metal/ and MetalKit/ with the
# library's own flags, then on the resulting OBJECTS runs the two checks below. A compile cannot
# catch either of them, and both cost a merge.
#
# 1. NO UNRESOLVED _Charon* SYMBOL. A `static` that is DECLARED in one .m and DEFINED in another is
#    a link error, not a compile error: each file compiles alone, and the 6.1.3 link fails on
#    undefined _CharonAttributesFromFunction. So every undefined _Charon* symbol of every object is
#    resolved against the DEFINED symbols of the whole library directory, and one that no object
#    defines is a failure with its name.
#
# 2. ONE OBJECT, ONE RELEASE. release-split walks the real cache ladder and fails an object that
#    carries symbols first exported in two different releases, because such an object is placed in
#    neither band. A file that mixes 9.0 and 10.0.1 compiles, links, and passes every test, and the
#    gate stops on it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
work=${WORK:-$root/.agent-work/runs/metal-census/pre-export}
SDK=""
for candidate in "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk; do
    if [ -f "$candidate/SDKSettings.json" ]; then SDK="$candidate"; break; fi
done
[ -n "$SDK" ] || { echo "FAIL: no iOS 16.4 SDK; set it in the script" >&2; exit 1; }
rm -rf "$work"
mkdir -p "$work/Metal" "$work/MetalKit"

# THE COMPILE, on clang's own exit status, and a count line.
count=0
bad=0
for dir in Metal MetalKit; do
    for source in "$dir"/*.m; do
        count=$((count + 1))
        if ! xcrun clang -target armv7-apple-ios6.1.3 -isysroot "$SDK" -fobjc-arc -Os -g0 -Wall \
             -Wno-unguarded-availability-new -Wno-unguarded-availability \
             -Werror=objc-missing-property-synthesis -c "$source" -o "$work/${source%.m}.o" \
             > "$work/$(basename "${source%.m}").build" 2>&1; then
            bad=$((bad + 1))
            echo "FAIL does not compile: $source" >&2
            sed 's/^/    /' "$work/$(basename "${source%.m}").build" | head -6 >&2
        fi
    done
done
echo "$count files, 0 errors"
[ "$bad" -eq 0 ] || { echo "pre-export: $bad file(s) do not compile" >&2; exit 1; }

# 1. every undefined _Charon* resolved against every DEFINED symbol of this library
defined=$(xcrun nm -g "$work"/Metal/*.o "$work"/MetalKit/*.o 2>/dev/null | awk '$2 != "U" {print $3}' | sort -u)
unresolved=0
for object in "$work"/Metal/*.o "$work"/MetalKit/*.o; do
    for symbol in $(xcrun nm -g "$object" 2>/dev/null | awk '$1 == "U" || $2 == "U" {print $NF}' \
                           | grep "^_Charon" | sort -u); do
        if ! printf '%s\n' "$defined" | grep -qx "$symbol"; then
            unresolved=$((unresolved + 1))
            echo "FAIL $(basename "$object") needs $symbol and no object of this library defines it" >&2
        fi
    done
done
[ "$unresolved" -eq 0 ] || { echo "pre-export: $unresolved unresolved _Charon* symbol(s)" >&2; exit 1; }
echo "no unresolved _Charon* symbol in $(ls "$work"/Metal/*.o "$work"/MetalKit/*.o | wc -l | tr -d ' ') object(s)"

# 2. release-split on the same objects: one release each
split=$root/.agent-work/runs/metal-census/pre-export-split.txt
( cd "$root" && xmake l tools/release-split.lua "$work" "$split" "$SDK" ) > "$work/split.log" 2>&1 || true
mixed=$(sed 's/\x1b\[[0-9;]*m//g' "$work/split.log" | grep -E "^error: release-split" || true)
if [ -n "$mixed" ]; then
    echo "$mixed" >&2
    echo "pre-export: an object carries two releases' API" >&2
    exit 1
fi
echo "release-split: every object holds one release's API"
echo "pre-export: OK"
