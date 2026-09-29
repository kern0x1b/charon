#!/bin/sh
# mutation.sh — can this harness fail? One term of the multiply accumulation is changed, the run is
# repeated, and the count must move; the revert must move it back. A comparison that cannot fail is
# not a comparison, and this is the check that it cannot.
#
# It mutates the library, so the tree is left exactly as it was found, and it says so if it cannot.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../../.." && pwd)
kernel=$root/packages/a/apple-backports/MetalPerformanceShaders/MPSMatrixMultiplication10.m
line='                    sum += a * c;'
mutated='                    sum += a * c + 0.125;  // MUTATION'
work=${MUTATION_BUILD:-$root/.agent-work/runs/host/mpsmatrix-mutation}

grep -q "$line" "$kernel" || { echo "the anchor is gone from $kernel; the mutation is not a check any more"; exit 1; }
restore() { printf '%s\n' "$original" > "$kernel"; }
original=$(cat "$kernel")
trap restore EXIT INT TERM

count() {
    BUILD="$work" sh "$here/run.sh" 2>&1 | grep -E 'differing cases|DIFFERS in' | head -1
}

before=$(count)
printf 'before   %s\n' "$before"
printf '%s\n' "$mutated" > "$kernel"
during=$(count)
printf 'mutated  %s\n' "$during"
restore
after=$(count)
printf 'reverted %s\n' "$after"

if [ "$before" = "$during" ] || [ "$during" = "$after" ]; then
    echo "the mutation did not move the count; the harness is not measuring the library"
    exit 1
fi
echo "the mutation moves the count and the revert moves it back: the harness can fail"
