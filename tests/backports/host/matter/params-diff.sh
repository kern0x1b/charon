#!/bin/sh
# The host's Matter.framework and the port's own plain data classes, over the same driver, compared.
#
# ONE program runs on both sides - tests/backports/host/matter/params-probe.m - because it takes its class
# names, property names and alias pairs from the driver file and reads nothing at compile time, so the only
# difference between the two outputs is behaviour.
#
#   host side   xcrun clang ... -framework Matter, against /System/Library/Frameworks/Matter.framework
#   port side   the port's own objects, regenerated for THIS host with the generator's own rule applied to
#               the host's SDK as the target: tools/matter-generate.py --sdk26.2 --sdk16 <macOS SDK> declares
#               what THAT SDK does not declare, which is the same rule the shipped tree applies to 16.4. The
#               bodies are the same generator's output; only the declarations differ, and only because the
#               target SDK differs.
#
# A RED CONTROL is not optional: the comparison is run once against a copy of one port object with one line
# changed, and the run must FAIL on it. A check that has never been seen to fail is a check that examines
# nothing.
#
#   sh tests/backports/host/matter/params-diff.sh [--keep]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${MATTER_PARAMS_DIFF_BUILD:-$root/.agent-work/runs/params-diff}
sdk26=${MATTER_SDK_26_2:-$root/.agent-work/sdk262}
sdk16=${MATTER_SDK_LIBRARY:-$(cat /tmp/land/sdkpath 2>/dev/null || echo "")}
host_sdk=$(xcrun --show-sdk-path)
rm -rf "$build"
mkdir -p "$build/host" "$build/port"
# The generator reads its cluster list from the directory it writes into, so the committed one goes there
# first: a regeneration from the repository alone must not need anything from .agent-work.
cp "$root/packages/a/apple-backports/Matter/clusters-emitted.txt" "$build/port/clusters-emitted.txt"

# The driver: written by the generator, from the same buckets it emits from.
python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$build/port" \
    --contracts "$build/port-contracts" --sdk16 "$sdk16" --shared-types --params \
    --cases "$build/cases.tsv" > "$build/cases.log" 2>&1

xcrun clang -fobjc-arc -Wall -o "$build/host/probe" "$here/params-probe.m" \
    -framework Foundation -framework Matter
"$build/host/probe" "$build/cases.tsv" | grep -v $'^#' > "$build/host.tsv"

# The port side, compiled for the host out of the generator's own objects.
python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$build/port" \
    --contracts "$build/port-contracts" --sdk16 "$host_sdk" --shared-types --params \
    > "$build/port-generate.log" 2>&1
xcrun clang -fobjc-arc -O0 -I"$build/port" -o "$build/port/probe" "$here/params-probe.m" \
    "$build"/port/*.m -framework Foundation
"$build/port/probe" "$build/cases.tsv" | grep -v $'^#' > "$build/port.tsv"

# The three questions the review asked, compared. The host has no class for 5 of the 923 and raises on 6,
# and each of those is a line the port is not compared on - and counted, so a gap is a number and not a
# silence.
present=$(awk -F'\t' '$1=="present" && $4=="present"' "$build/host.tsv" | wc -l | tr -d ' ')
raised=$(awk -F'\t' '$1=="raised"' "$build/host.tsv" | wc -l | tr -d ' ')
printf 'classes the host has: %s; the host raised on: %s; absent: %s\n' "$present" "$raised" \
    "$((923 - present))"
for question in ownDescription description fresh alias; do
    awk -F'\t' -v q="$question" '$1==q' "$build/host.tsv" | sort > "$build/host.$question"
    awk -F'\t' -v q="$question" '$1==q' "$build/port.tsv" | sort > "$build/port.$question"
    missing=$(comm -23 "$build/host.$question" "$build/port.$question" | wc -l | tr -d ' ')
    printf '%s: %s of the host readings the port does not answer\n' "$question" "$missing"
done

# The RED CONTROL: one line of one port object changed, and the comparison must notice.
victim=$(ls "$build"/port/CharonMatterMTRGroupsClusterAddGroupParams.m)
mkdir -p "$build/port-mutant"
cp "$build"/port/*.m "$build/port-mutant/"
sed -i '' 's/_groupID = @0;/_groupID = @7;/' "$build/port-mutant/CharonMatterMTRGroupsClusterAddGroupParams.m"
cmp -s "$victim" "$build/port-mutant/CharonMatterMTRGroupsClusterAddGroupParams.m" && {
    echo "FAIL the red control: the mutation did not change the file" >&2; exit 1; }
xcrun clang -fobjc-arc -O0 -I"$build/port" -o "$build/port/probe-mutant" "$here/params-probe.m" \
    "$build"/port-mutant/*.m -framework Foundation
"$build/port/probe-mutant" "$build/cases.tsv" | grep -v $'^#' | awk -F'\t' '$1=="fresh"' | sort \
    > "$build/port.fresh.mutant"
changed=$(comm -12 "$build/port.fresh" "$build/port.fresh.mutant" | wc -l | tr -d ' ')
differing=$(comm -13 "$build/port.fresh" "$build/port.fresh.mutant" | wc -l | tr -d ' ')
if [ "$differing" -lt 1 ]; then
    echo "FAIL the red control: a port object with _groupID = @7 read the same as the original" >&2
    exit 1
fi
printf 'red control: %s fresh readings differ from the unmutated port, so the comparison can fail\n' "$differing"
echo "outputs under $build"
