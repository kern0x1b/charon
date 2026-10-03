#!/bin/sh
# The host's Matter.framework and the port's own plain data classes, over the same driver, compared.
#
# ONE program runs on both sides - tests/backports/host/matter/params-probe.m - because it takes its class
# names, its member names and its alias pairs from the driver file and reads nothing at compile time, so the
# only difference between the two outputs is behaviour.
#
#   host side   xcrun clang ... -framework Matter, against /System/Library/Frameworks/Matter.framework
#   port side   the port's own objects, regenerated for THIS host with the generator's own rule applied to
#               the host's SDK as the target: --sdk26.2 --sdk16 <the host SDK> declares what THAT SDK does
#               not declare, which is the same rule the shipped tree applies to iPhoneOS16.4. The bodies are
#               the same generator's output; only the declarations differ, and only because the target does.
#
# A RED CONTROL is not optional: the comparison is run again against a copy of one port object with one
# value changed, and the run must FAIL on it. A check that has never been seen to fail examines nothing.
#
#   sh tests/backports/host/matter/params-diff.sh
#
# The SDKs come from the same places the package and relcheck take them, and the script STOPS when it cannot
# find one: a check that quietly falls back to nothing reports green without having looked at anything.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${MATTER_PARAMS_DIFF_BUILD:-$root/.agent-work/runs/params-diff}

# The library SDK: the pin the package's xmake.lua records, then the SDK store, then the machine's. The first
# one that exists wins and the script says which, because "it worked" and "it found an SDK" are different
# facts and a run has to say which one happened.
sdk16=""
for candidate in \
    "${MATTER_SDK_LIBRARY:-}" \
    "$HOME/.xmake/packages/i/iphoneos-sdk/16.4"/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk
do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        sdk16="$candidate"
        break
    fi
done
if [ -z "$sdk16" ]; then
    echo "params-diff: no iPhoneOS 16.4 SDK. Put MATTER_SDK_LIBRARY=<path> in the environment, or install" >&2
    echo "  the package's SDK pin; nothing is compared against nothing here." >&2
    exit 2
fi
sdk26="$root/.agent-work/sdk262"
if [ ! -d "$sdk26" ]; then
    echo "params-diff: no 26.2 SDK at $sdk26 - the one the generator reads the declarations from." >&2
    exit 2
fi
host_sdk=$(xcrun --show-sdk-path)
[ -d "$host_sdk/System/Library/Frameworks/Matter.framework" ] || {
    echo "params-diff: this host has no Matter.framework, so there is nothing to compare the port against." >&2
    exit 2; }
echo "params-diff: library SDK $sdk16"
echo "params-diff: host SDK    $host_sdk  (Matter.framework $(defaults read "$host_sdk/System/Library/Frameworks/Matter.framework/Resources/Info" CFBundleShortVersionString 2>/dev/null || echo unknown))"

rm -rf "$build"
mkdir -p "$build/host" "$build/port" "$build/port-mutant" "$build/objects" "$build/objects-mutant"

# The driver: written by the generator, from the same buckets it emits from.
cp "$root/packages/a/apple-backports/Matter/clusters-emitted.txt" "$build/port/clusters-emitted.txt"
python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$build/port" \
    --contracts "$build/port-contracts" --sdk16 "$sdk16" --shared-types --params \
    --cases "$build/cases.tsv" > "$build/cases.log" 2>&1
echo "params-diff: driver $(grep -c . "$build/cases.tsv") lines, $(grep -c alias "$build/cases.tsv" || true) alias pairs"

xcrun clang -fobjc-arc -Wall -o "$build/host/probe" "$here/params-probe.m" \
    -framework Foundation -framework Matter
"$build/host/probe" "$build/cases.tsv" > "$build/host.tsv"

# The port side, out of the generator's own objects for THIS host, compiled one at a time and linked once -
# 1067 sources through one clang invocation does not finish in a useful time.
# The SAME measurement file the shipped tree is generated with, and the reason is not tidiness: without it
# the generator writes no -description and no alias conversion, because it cannot know what the host does,
# and the comparison then measures the absence of the argument rather than the port. That is what the first
# run of this script did: 66 of 918 on ownDescription, which is exactly the count of classes that do NOT
# override it.
python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$build/port" \
    --contracts "$build/port-contracts" --sdk16 "$host_sdk" --shared-types --params \
    --host-measurements "$here/host-measurements.tsv" \
    > "$build/port-generate.log" 2>&1
echo "params-diff: $(grep -c 'every object compiles' "$build/port-generate.log") compile-check line(s) in the generator log"
compile() {
    into=$1; shift
    ls "$build/port"/*.m | xargs -P "${MATTER_DIFF_JOBS:-4}" -n 1 sh -c \
        'xcrun clang -fobjc-arc -O0 -I'"$build/port"' -c "$0" -o "'"$into"'/$(basename "$0" .m).o" 2>&1' \
        | { grep ' error: ' || true; }
    # `set -e` and a pipeline whose last command found nothing is a non-zero status, so the count of errors
    # is taken as text and the emptiness of it is the verdict. A check that exits on "no errors found" is a
    # check that only ever fails.
    errors=$(ls "$into" | wc -l | tr -d ' ')
    if [ "$errors" -lt "$(ls "$build/port"/*.m | wc -l | tr -d ' ')" ]; then
        echo "params-diff: only $errors objects of $(ls "$build/port"/*.m | wc -l | tr -d ' ') compiled" >&2
        return 1
    fi
    return 0
}
compile "$build/objects"
xcrun clang -o "$build/port/probe" "$build/objects"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe" "$build/cases.tsv" > "$build/port.tsv"

present=$(awk -F'\t' '$1=="present" && $4=="present"' "$build/host.tsv" | wc -l | tr -d ' ')
absent=$(awk -F'\t' '$1=="present" && $4=="absent"' "$build/host.tsv" | wc -l | tr -d ' ')
raised=$(awk -F'\t' '$1=="raised"' "$build/host.tsv" | wc -l | tr -d ' ')
printf 'params-diff: classes the host has %s, absent %s, raised %s\n' "$present" "$absent" "$raised"

status=0
for question in ownDescription description fresh alias; do
    awk -F'\t' -v q="$question" '$1==q' "$build/host.tsv" | sort > "$build/host.$question"
    awk -F'\t' -v q="$question" '$1==q' "$build/port.tsv" | sort > "$build/port.$question"
    host_n=$(wc -l < "$build/host.$question" | tr -d ' ')
    same=$(comm -12 "$build/host.$question" "$build/port.$question" | wc -l | tr -d ' ')
    printf 'params-diff: %-14s %s of the hosts %s readings the port answers identically\n' \
        "$question" "$same" "$host_n"
    [ "$same" = "$host_n" ] || status=1
done

# The RED CONTROL: one value in one port object changed, and the comparison must notice.
cp "$build/port"/*.m "$build/port-mutant/"
victim="$build/port-mutant/CharonMatterMTRGroupsClusterAddGroupParams.m"
sed -i '' 's/_groupID = @0;/_groupID = @7;/' "$victim"
cmp -s "$build/port/CharonMatterMTRGroupsClusterAddGroupParams.m" "$victim" || true
if cmp -s "$build/port/CharonMatterMTRGroupsClusterAddGroupParams.m" "$victim"; then
    echo "params-diff: FAIL the red control - the mutation did not change the file, so it would prove nothing" >&2
    exit 1
fi
compile "$build/objects-mutant"
xcrun clang -o "$build/port/probe-mutant" "$build/objects-mutant"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe-mutant" "$build/cases.tsv" > "$build/port-mutant.tsv"
awk -F'\t' '$1=="fresh" || $1=="description"' "$build/port.tsv" | sort > "$build/port.mutated-bytes"
awk -F'\t' '$1=="fresh" || $1=="description"' "$build/port-mutant.tsv" | sort > "$build/port.mutant-bytes"
moved=$(comm -13 "$build/port.mutated-bytes" "$build/port.mutant-bytes" | wc -l | tr -d ' ')
if [ "$moved" -lt 1 ]; then
    echo "params-diff: FAIL the red control - a port object with _groupID = @7 reads the same as the original" >&2
    exit 1
fi
printf 'params-diff: red control %s readings move, so this comparison can fail\n' "$moved"
echo "params-diff: outputs under $build"
exit $status
