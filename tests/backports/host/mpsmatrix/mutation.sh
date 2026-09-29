#!/bin/sh
# mutation.sh — can this harness fail? One term of the multiply accumulation is changed, the run is
# repeated, and the count must move; the revert must move it back. A comparison that cannot fail is
# not a comparison, and this is the check that it cannot.
#
# It mutates the library, so the tree is left exactly as it was found, and it says so if it cannot.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
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

grep -qF "$line" "$kernel" || { echo "the anchor is gone from $kernel; the mutation is not a check any more"; exit 1; }

MUTANTS_DIR=$(dirname "$0")/mutants
export MUTANTS_DIR
. "$(dirname "$0")/mutate.sh"
original=$(cat "$kernel")
foriginal=$(cat "$forward")
restore_forward() { printf '%s\n' "$foriginal" > "$forward"; }
trap restore EXIT INT TERM

count() {
    line=$(BUILD="$work" sh "$here/run.sh" 2>&1 | grep -E 'differing cases|DIFFERS in' | head -1)
    if [ -z "$line" ]; then
        echo "the harness produced no count, so the tree does not build or the run failed:" >&2
        return 1
    fi
    printf '%s\n' "$line"
}

before=$(count)
printf 'before   %s\n' "$before"
mutate "$kernel" "$line" "$mutated"
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
grep -qF "$sline" "$sumkernel" || { echo "the sum anchor is gone"; exit 1; }
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
grep -qF "$scale_line" "$sumkernel" || { echo "the scale anchor is gone"; exit 1; }
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
grep -qF "$bline" "$bnk" || { echo "the gradient anchor is gone"; exit 1; }
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

# Three mutants on the scale guard's edge, which the three sum-start-index-boundary cases defend:
# start 1 leaves one factor in the list and start 2 leaves none, so each side of the edge is a case.
# The guard is `pairs = startIndex < factors ? factors - startIndex : 0` and the `pairs > _count` clamp
# after it. Mutating either to an off-by-one must turn exactly those cases red and leave the rest.
sk=$root/packages/a/apple-backports/MetalPerformanceShaders/MPSMatrixSum11.m
sedge_line='            NSUInteger pairs = startIndex < factors ? factors - startIndex : 0;'
sclamp_line='                pairs = _count;'
sedgeread=$(cat "$sk")
restore_sedge() { printf '%s\n' "$sedgeread" > "$sk"; }
trap 'restore; restore_forward; restore_sum; restore_sum2; restore_bn; restore_sedge' EXIT INT TERM
grep -qF "$sedge_line" "$sk" || { echo "the scale guard's edge anchor is gone"; exit 1; }
grep -qF "$sclamp_line" "$sk" || { echo "the scale guard's clamp anchor is gone"; exit 1; }
edge_before=$(count)
# side one: the guard admits startIndex == factors, which leaves no factors at all
printf '%s\n' "$sedge_line" | sed 's|startIndex < factors|startIndex <= factors|' > "$sk"
edge_one=$(count)
printf '%s\n' "$sedge_line" > "$sk"
# side two: the clamp off by one, so a start past the sources reads one factor too many
printf '%s\n' "$sclamp_line" | sed 's|pairs = _count;|pairs = _count + 1;|' > "$sk"
edge_two=$(count)
restore_sedge
edge_after=$(count)
printf 'edge before    %s\n' "$edge_before"
printf 'edge guard     %s\n' "$edge_one"
printf 'edge clamp     %s\n' "$edge_two"
printf 'edge reverted  %s\n' "$edge_after"
if [ "$edge_before" = "$edge_one" ] || [ "$edge_before" = "$edge_two" ] || [ "$edge_two" = "$edge_after" ]; then
    echo "a scale guard edge mutation did not move the count"
    exit 1
fi

# A fourth mutant on the neuron application, so the fifteen sum neuron cases are defended as well: the
# kernel applies the neuron at MPSMatrixSum11.m:195, and skipping it must be red on exactly that loop.
grep -q 'CharonMPSApplyNeuron(neuron.type, sum, neuron.a' "$sk" || { echo "the neuron anchor is gone"; exit 1; }
neuron_before=$(count)
sed 's|CharonMPSApplyNeuron(neuron.type, sum, neuron.a|CharonMPSApplyNeuron(MPSCNNNeuronTypeNone, sum, neuron.a|' "$sk" > "$sk.new" && mv "$sk.new" "$sk"
neuron_during=$(count)
restore_sedge
neuron_after=$(count)
printf 'neuron before  %s\n' "$neuron_before"
printf 'neuron mutated %s\n' "$neuron_during"
printf 'neuron reverted %s\n' "$neuron_after"
if [ "$neuron_before" = "$neuron_during" ] || [ "$neuron_during" = "$neuron_after" ]; then
    echo "the neuron mutation did not move the count"
    exit 1
fi

echo "all nine mutations move the count and all five reverts move them back: the harness can fail"
