#!/bin/sh
# matter/plants.sh - the three plants, for one generated cluster file.
#
# A differential that has never been seen to fail is a differential that examines nothing, so this makes
# it fail three ways and checks that it does. Each plant is a copy of the port's OWN generated file with
# one thing changed, and each change is proved to have changed something - cmp against the original, and
# an abort if they are the same - because a mutation that did not apply and a mutation that survived look
# identical on the way out and mean opposite things.
#
#   drop   one attribute's read, its selector and its body both, so the port has one member fewer
#   rename one selector, so the port has one the system does not
#   extra  a member the system does not have, so the port has one too many
#   control the file unchanged, through the same path, which must be green
#
# Usage: sh tests/backports/host/matter/plants.sh <generated cluster file> [cluster name]
#        BUILD=<dir>   where the copies and the builds go
set -eu
here=$(cd "$(dirname "$0")" && pwd)
differential=$here/../matterdifferential/run.sh
file=$1
cluster=${2:-MTRBaseClusterIdentify}
build=${BUILD:-${TMPDIR:-/tmp}/charon-matter-plants}
contracts=${CONTRACTS:-$here/contracts}
selector=readAttributeIdentifyTimeWithCompletion:

[ -f "$file" ] || { echo "no such generated file: $file" >&2; exit 2; }
[ -f "$differential" ] || { echo "no differential beside this script" >&2; exit 2; }
rm -rf "$build"
mkdir -p "$build/plants" "$build/src"

# 1. drop: the whole method, from its selector line to the closing brace.
sed "/${selector}/,/^}/d" "$file" > "$build/plants/drop.m"

# 2. rename: the selector, and nothing else.
sed "s/${selector}/readAttributeIdentifyTimeRenamedWithCompletion:/" "$file" > "$build/plants/rename.m"

# 3. extra: a member before the LAST @end, which is where a real one would go.
awk '
    { lines[NR] = $0 }
    END {
        last = 0
        for (i = NR; i > 0; i--) { if (lines[i] ~ /^@end/) { last = i; break } }
        for (i = 1; i <= NR; i++) {
            if (i == last) {
                print "- (void)charonExtraMember {"
                print "}"
                print ""
            }
            print lines[i]
        }
    }' "$file" > "$build/plants/extra.m"

# 4. control: the file itself, copied, so every plant runs through the same path.
cp "$file" "$build/plants/control.m"

# Each mutation has to have CHANGED the file. A mutation that did not apply is not a survivor, and a
# script that cannot tell the two apart is a script that will one day report a green run as a green plant.
aborted=0
for plant in drop rename extra; do
    if cmp -s "$build/plants/$plant.m" "$file"; then
        echo "ABORT: the $plant plant changed nothing, so it can neither pass nor fail" >&2
        aborted=1
    fi
done
# The control is the one that is SUPPOSED to be identical, and that is what makes it a control.
if ! cmp -s "$build/plants/control.m" "$file"; then
    echo "ABORT: the control differs from the original, so it is not a control" >&2
    aborted=1
fi
[ "$aborted" -eq 0 ] || exit 1
for plant in drop rename extra; do
    echo "plant $plant: $(wc -l < "$build/plants/$plant.m" | tr -d ' ') lines, differs from the original: yes"
done
echo "plant control: $(wc -l < "$build/plants/control.m" | tr -d ' ') lines, identical to the original: yes"

# The check is run once per copy, with the copy in place of the real file, and the exit status is the
# verdict. control must be 0; drop, rename and extra must not be.
failures=0
for plant in control drop rename extra; do
    mkdir -p "$build/src-$plant"
    rm -f "$build/src-$plant"/CharonMatter*.m
    cp "$build/plants/$plant.m" "$build/src-$plant/CharonMatter${cluster}.m"
    # The contract is a fixture and lives with the tests, not beside the object in the package tree.
    cp "$contracts/CharonMatter${cluster}.m.contract" "$build/src-$plant/CharonMatter${cluster}.m.contract" 2>/dev/null || {
        echo "ABORT: no contract for $cluster at $contracts" >&2
        exit 1
    }
    # The differential reads the list of clusters the generator wrote, from the source directory it is
    # given; a plant hands it a directory holding ONE cluster's object, so the plant states which.
    printf '%s\n' "$cluster" > "$build/one-cluster.txt"
    if CLUSTER_LIST="$build/one-cluster.txt" MATTER_SOURCE_DIR="$build/src-$plant" \
       BUILD="$build/run-$plant" sh "$differential" \
        > "$build/$plant.out" 2>&1; then
        status=0
    else
        status=$?
    fi
    # awk, not `grep -c ... || true`: this count is what decides whether the plant examined anything.
    checked=$(awk '/^same|^DIFFERENT/ { n++ } END { print n + 0 }' "$build/$plant.out")
    echo "plant $plant: differential exit $status, clusters it examined: $checked"
    if [ "$checked" -eq 0 ]; then
        echo "  it examined nothing, so the status above is not a verdict"
        failures=$((failures + 1))
    fi
    if [ "$plant" = control ]; then
        if [ "$status" -ne 0 ]; then
            echo "  the control went red, so the check fails on the unmutated tree and proves nothing"
            failures=$((failures + 1))
        fi
    else
        if [ "$status" -eq 0 ]; then
            echo "  the $plant plant survived, so the check examined nothing about it"
            failures=$((failures + 1))
        else
            grep -m2 -E "^member|^class" "$build/$plant.out" | sed 's/^/  /'
        fi
    fi
done
echo "plants run: 4, failures: $failures"
[ "$failures" -eq 0 ]
