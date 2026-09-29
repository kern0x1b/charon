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

# A second mutant, on the forward batch-normalisation's mean: the formula is gamma * (x - mean) /
# sqrt(variance + epsilon) + beta, and the mean there is the caller's. The mutant puts the computed
# mean back, which is the defect this family had, and must turn the column that differs red.
forward=$root/packages/a/apple-backports/MetalPerformanceShaders/MPSMatrixBatchNormalization12.m
fline='                double y = CharonMPSApplyNeuron(neuron.type, g * (x - mu) / sqrt(given + (double)_epsilon) + b0,'
fmutated='                double y = CharonMPSApplyNeuron(neuron.type, g * (x - m) / sqrt(given + (double)_epsilon) + b0,  // MUTATION'
work=${MUTATION_BUILD:-$root/.agent-work/runs/host/mpsmatrix-mutation}

grep -q "$line" "$kernel" || { echo "the anchor is gone from $kernel; the mutation is not a check any more"; exit 1; }
restore() { printf '%s\n' "$original" > "$kernel"; }
original=$(cat "$kernel")
foriginal=$(cat "$forward")
restore_forward() { printf '%s\n' "$foriginal" > "$forward"; }
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
# The forward's mean, the same way.
restore
fbefore=$(count)
printf '%s\n' "$fmutated" > "$forward"
fduring=$(count)
printf 'forward before   %s\n' "$fbefore"
printf 'forward mutated  %s\n' "$fduring"
restore_forward
fafter=$(count)
sbefore=$(count)
printf 'forward reverted %s\n' "$fafter"
if [ "$fbefore" = "$fduring" ] || [ "$fduring" = "$fafter" ]; then
    echo "the forward mutation did not move the count either"
    exit 1
fi
# A third mutant, on the sum's transposed clip: the release writes the intersection of the transposed
# shape with the result descriptor and leaves the rest untouched, which a -1 sentinel in the result
# shows. The mutant writes the whole shape, which is what the port did before the fix.
sumkernel=$root/packages/a/apple-backports/MetalPerformanceShaders/MPSMatrixSum11.m
sline='    NSUInteger extent = _transpose ? (_rows < _columns ? _rows : _columns) : _rows;'
smutated='    NSUInteger extent = _rows;  // MUTATION: the whole shape, not the intersection'
soriginal=$(cat "$sumkernel")
restore_sum() { printf '%s\n' "$soriginal" > "$sumkernel"; }
trap 'restore; restore_forward; restore_sum' EXIT INT TERM
grep -q "$sline" "$sumkernel" || { echo "the sum anchor is gone"; exit 1; }
printf '%s\n' "$smutated" > "$sumkernel"
sduring=$(count)
printf 'sum before   %s\n' "$sbefore"
printf 'sum mutated  %s\n' "$sduring"
restore_sum
safter=$(count)
printf 'sum reverted %s\n' "$safter"
if [ "$sbefore" = "$sduring" ] || [ "$sduring" = "$safter" ]; then
    echo "the sum mutation did not move the count either"
    exit 1
fi
echo "all three mutations move the count and all three reverts move them back: the harness can fail"
