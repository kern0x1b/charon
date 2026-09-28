#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
usage="usage: run.sh [--mutants]"
mutants=no
if [ "${1:-}" = --mutants ]; then
    mutants=yes
    shift
fi
[ $# -eq 0 ] || { echo "$usage" >&2; exit 2; }
FOUNDATION=${FOUNDATION:-$here/../../../../packages/a/apple-backports/Foundation}
BUILD=${BUILD:-${TMPDIR:-/tmp}/charon-bundlerequest-host}
sources=${SOURCES:-$(cat "$here/sources.txt")}
# SAN=1 adds AddressSanitizer, which names the file, the line and the access where lldb only gives a
# frame; it is a debugging build of this test, not a mode the house runner needs.
sanitize=""
if [ "${SAN:-}" = 1 ]; then
    sanitize="-fsanitize=address -fno-omit-frame-pointer -g"
fi
quiet="-Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unguarded-availability -Wno-incomplete-implementation -Wno-objc-protocol-method-implementation -Wno-nullability-completeness -Wno-objc-designated-initializers -Wno-nonnull"

if [ $mutants = yes ]; then
    missed=0
    tab=$(printf '\t')
    mutant=$BUILD-mutant
    while IFS="$tab" read -r name file change; do
        rm -rf "$mutant"
        mkdir -p "$mutant/Foundation"
        cp -R "$FOUNDATION"/ "$mutant/Foundation/"
        perl -0pi -e "$change" "$mutant/Foundation/$file"
        if cmp -s "$FOUNDATION/$file" "$mutant/Foundation/$file"; then
            echo "STALE $name: the change no longer applies"
            missed=1
            continue
        fi
        if FOUNDATION="$mutant/Foundation" BUILD="$mutant/build" sh "$here/run.sh" > "$mutant.log" 2>&1; then
            echo "MISSED $name"
            missed=1
        elif grep -q ' error: ' "$mutant.log"; then
            echo "BROKEN $name: the mutant does not compile"
            missed=1
        elif grep -q '^FAIL ' "$mutant.log"; then
            echo "caught $name: $(grep '^FAIL ' "$mutant.log" | head -1 | cut -c6- | cut -d: -f1)"
        else
            echo "caught $name: the port crashed"
        fi
    done < "$here/mutants/bundlerequest.txt"
    rm -rf "$mutant" "$mutant.log"
    exit $missed
fi

rm -rf "$BUILD/plain" "$BUILD/renamed"
mkdir -p "$BUILD/plain" "$BUILD/renamed"
for source in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet $sanitize -I"$FOUNDATION" -c "$FOUNDATION/$source" -o "$BUILD/plain/$source.o"
done
# The class and the two keys are the port's API and the host's are the real ones, so the port's are
# renamed. The category on NSBundle is not: NSBundle is the release's own class and both the host's
# additions and the port's attach to it, which is what lets the test ask each of them.
renames="-DNSBundleResourceRequest=CharonHostNSBundleResourceRequest"
for name in NSBundleResourceRequestLoadingPriorityUrgent NSBundleResourceRequestLowDiskSpaceNotification; do
    renames="$renames -D$name=CharonHost$name"
done
echo "renamed:$renames"
for source in $sources; do
    xcrun clang -fobjc-arc -fvisibility=hidden $quiet $sanitize $renames -I"$FOUNDATION" -c "$FOUNDATION/$source" -o "$BUILD/renamed/$source.o"
done
xcrun clang -fobjc-arc $quiet $sanitize "$here/differential.m" "$BUILD"/renamed/*.o -framework Foundation -o "$BUILD/differential"
"$BUILD/differential"
