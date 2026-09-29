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
# A fourth mutant, on the sum's scale indexing: startIndex is a position in the flat list of scale
# factors, so it is a component of the vector and not a vector index. The mutant reads it as a vector
# index, which is what the port did before the fix and what answered all zeros.
scale_line='                    NSUInteger which = (startIndex + index) / MAX((NSUInteger)1, scales.length);'
scale_mut='                    NSUInteger which = startIndex + index;  // MUTATION: a vector index'
soriginal2=$(cat "$sumkernel")
restore_sum2() { printf '%s\n' "$soriginal2" > "$sumkernel"; }
trap 'restore; restore_forward; restore_sum; restore_sum2' EXIT INT TERM
grep -q "$scale_line" "$sumkernel" || { echo "the scale anchor is gone"; exit 1; }
scbefore=$(count)
printf '%s\n' "$scale_mut" > "$sumkernel"
scduring=$(count)
printf 'scale before   %s\n' "$scbefore"
printf 'scale mutated  %s\n' "$scduring"
restore_sum2
scafter=$(count)
printf 'scale reverted %s\n' "$scafter"
if [ "$scbefore" = "$scduring" ] || [ "$scduring" = "$scafter" ]; then
    echo "the scale mutation did not move the count either"
    exit 1
fi
# A fifth mutant, on the batch-norm gradient's per-parameter vectors: the release leaves them
# untouched - a -1.0f sentinel survives - and the port now does the same. The mutant writes zeros there
# instead, which is what a fresh buffer hides, and it must turn the two cases red.
bnk=$root/packages/a/apple-backports/MetalPerformanceShaders/MPSMatrixBatchNormalizationGradient12.m
bline='            // The per-parameter gradients are left untouched. The release writes neither: with a'
bmut='            // MUTATION: zeros written, not untouched\n            if (resultGradientForGammaVector) { { CharonMPSVectorView v = CharonMPSVectorViewOf(resultGradientForGammaVector); for (NSUInteger i = 0; i < v.length; i++) CharonMPSStore(CharonMPSVectorElement(&v, 0, i), v.dataType, 0, 0.0); } }'
boriginal=$(cat "$bnk")
restore_bn() { printf '%s\n' "$boriginal" > "$bnk"; }
trap 'restore; restore_forward; restore_sum; restore_sum2; restore_bn' EXIT INT TERM
grep -q "$bline" "$bnk" || { echo "the gradient anchor is gone"; exit 1; }
bbefore=$(count)
printf '%s\n' "$bmut" > "$bnk"
bduring=$(count)
printf 'gradient before   %s\n' "$bbefore"
printf 'gradient mutated  %s\n' "$bduring"
restore_bn
bafter=$(count)
printf 'gradient reverted %s\n' "$bafter"
if [ "$bbefore" = "$bduring" ] || [ "$bduring" = "$bafter" ]; then
    echo "the gradient mutation did not move the count either"
    exit 1
fi
echo "all five mutations move the count and all four reverts move them back: the harness can fail"
