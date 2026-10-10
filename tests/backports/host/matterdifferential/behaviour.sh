#!/bin/sh
# matterdifferential/behaviour.sh - what the port's Matter clusters DO when there is nothing to reach, against
# the system's own classes, on this host. The questions and the oracle are in behaviour.m.
#
# One cluster at a time, generated with the committed tree's flags (the SDK 26.2 declarations, the library's own
# iPhoneOS 16.4 as the SDK it builds against, --params and the host measurements). The one flag left out is
# --generic-clusters, which adds the 143 MTRCluster* classes this run does not compile. Each cluster's object,
# and the queue header it may import, is then required to be the committed file byte for byte, so what is
# compiled here is the committed object and not a lookalike; a flag that changed one of them fails the run. It is
# compiled for the host with the class name aliased onto CharonPort<Name> and linked with behaviour.m into one
# program that also holds the system's class. CharonMatterTypes.h is replaced by an empty header: it declares
# what the library's SDK lacks, and the host's SDK lacks none of it. The second run is the same program built
# with -fsanitize=thread: the thread storm is only a check if it can SEE an unguarded table, and "did not
# crash" is not that.
#
#   sh tests/backports/host/matterdifferential/behaviour.sh
#   CLUSTERS="MTRBaseClusterIdentify:IdentifyTime"   cluster:attribute[:superclass,...], space separated
#                                                    a deprecated alias is asked together with the port class
#                                                    it aliases (MTRBaseClusterTestCluster:Boolean:MTRBaseClusterUnitTesting),
#                                                    because its superclass is the port's and not the system's
#   BUILD=<dir>                                       where the programs and their output go
#
# The SDKs are found the way params-diff.sh finds them, and the script STOPS when one is missing.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${BUILD:-$root/.agent-work/runs/matter-behaviour}
clusters=${CLUSTERS:-"MTRBaseClusterIdentify:IdentifyTime MTRBaseClusterOnOff:OnTime MTRBaseClusterLevelControl:OnLevel MTRBaseClusterTestCluster:Boolean:MTRBaseClusterUnitTesting MTRBaseClusterUnitTesting:Boolean"}

sdk26=""
for candidate in "${MATTER_SDK_262:-}" "$root/.agent-work/sdk-26.2/iPhoneOS26.2.sdk" "$root/.agent-work/sdk262"; do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        sdk26=$(cd "$candidate" && pwd)
        break
    fi
done
if [ -z "$sdk26" ]; then
    echo "behaviour: no iPhoneOS 26.2 SDK. Put MATTER_SDK_262=<path> in the environment." >&2
    exit 2
fi
sdk16=""
for candidate in "${MATTER_SDK_LIBRARY:-}" \
    "$HOME/.xmake/packages/i/iphoneos-sdk/16.4"/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk
do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        sdk16=$candidate
        break
    fi
done
if [ -z "$sdk16" ]; then
    echo "behaviour: no iPhoneOS 16.4 SDK. Put MATTER_SDK_LIBRARY=<path> in the environment." >&2
    exit 2
fi
host_sdk=$(xcrun --show-sdk-path)
[ -d "$host_sdk/System/Library/Frameworks/Matter.framework" ] || {
    echo "behaviour: this host has no Matter.framework, so there is no oracle." >&2
    exit 2; }

rm -rf "$build"
mkdir -p "$build"
status=0
for pair in $clusters; do
    cluster=${pair%%:*}
    rest=${pair#*:}
    attribute=${rest%%:*}
    supers=""
    [ "$rest" = "$attribute" ] || supers=$(echo "${rest#*:}" | tr ',' ' ')
    work="$build/$cluster"
    mkdir -p "$work/port"
    echo "$cluster" > "$work/classes.txt"
    for each in $supers; do echo "$each" >> "$work/classes.txt"; done
    aliases="-D$cluster=CharonPort$cluster"
    for each in $supers; do aliases="$aliases -D$each=CharonPort$each"; done
    # The generator's status is read: a run that fails (its compile check against the library's SDK and triple, or
    # any other check it makes) has written objects this comparison must not stand on.
    if ! python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$work/port" --contracts "$work/contracts" \
        --sdk16 "$sdk16" --shared-types --params --host-measurements "$here/../matter/host-measurements.tsv" \
        --classes-from "$work/classes.txt" > "$work/generate.log" 2>&1; then
        echo "behaviour: the generator failed for $cluster; its log says why: $work/generate.log" >&2
        tail -5 "$work/generate.log" >&2
        exit 2
    fi
    for each in $cluster $supers; do
        source="$work/port/CharonMatter$each.m"
        [ -f "$source" ] || { echo "behaviour: the generator wrote no $source" >&2; tail -5 "$work/generate.log" >&2; exit 2; }
        if ! cmp -s "$source" "$root/packages/a/apple-backports/Matter/CharonMatter$each.m"; then
            echo "behaviour: DIFFERENT - the generator no longer writes the committed $each; regenerate the tree" >&2
            exit 1
        fi
    done
    # The queue header holds one block per superclass the generator was asked for, and a run asks for fewer than the
    # tree does (the full tree's header also has the two Basic aliases' superclasses). So each block this run wrote
    # must be the committed block, byte for byte, and a block it did not write is not compared.
    if [ -f "$work/port/CharonMatterQueueStorage.h" ]; then
        for each in $supers; do
            want=$(sed -n "/^@interface $each () {/,/^@end/p" "$work/port/CharonMatterQueueStorage.h")
            have=$(sed -n "/^@interface $each () {/,/^@end/p" "$root/packages/a/apple-backports/Matter/CharonMatterQueueStorage.h")
            if [ -z "$want" ] || [ "$want" != "$have" ]; then
                echo "behaviour: DIFFERENT - the queue header's block for $each is not the committed one" >&2
                exit 1
            fi
        done
    fi
    printf '// the host SDK declares every class this header would declare for the library SDK\n' \
        > "$work/port/CharonMatterTypes.h"
    for mode in plain tsan; do
        flags=""
        [ "$mode" = tsan ] && flags="-fsanitize=thread"
        objects=""
        for each in $cluster $supers; do
            # shellcheck disable=SC2086
            xcrun clang -target arm64-apple-macos26.0 -isysroot "$host_sdk" -fobjc-arc -O1 -g -Wall -Wno-nonnull \
                -Wno-objc-protocol-property-synthesis -Wno-incomplete-implementation $flags \
                $aliases -I"$work/port" -c "$work/port/CharonMatter$each.m" -o "$work/port-$each-$mode.o"
            objects="$objects $work/port-$each-$mode.o"
        done
        # shellcheck disable=SC2086
        xcrun clang -target arm64-apple-macos26.0 -isysroot "$host_sdk" -fobjc-arc -O1 -g -Wall $flags \
            "$here/behaviour.m" $objects -framework Foundation -framework Matter -framework Security \
            -o "$work/behaviour-$mode"
        extra=""
        [ "$mode" = tsan ] && extra="stress"
        echo "== $cluster / $attribute ($mode)"
        if "$work/behaviour-$mode" "$cluster" "$attribute" $extra > "$work/$mode.out" 2> "$work/$mode.err"; then
            result=0
        else
            result=1
        fi
        cat "$work/$mode.out"
        races=$(awk '/WARNING: ThreadSanitizer/ { n++ } END { print n + 0 }' "$work/$mode.err")
        if [ "$mode" = tsan ]; then
            echo "thread sanitizer reports: $races"
            [ "$races" -eq 0 ] || result=1
            [ "$races" -eq 0 ] || grep -m1 -A6 "WARNING: ThreadSanitizer" "$work/$mode.err" | sed 's/^/    /'
        fi
        [ "$result" -eq 0 ] || status=1
    done
done
[ "$status" -eq 0 ] && echo "behaviour: the port answers as the system does, on every cluster asked" \
    || echo "behaviour: DIFFERENT - see the lines above"
exit "$status"
