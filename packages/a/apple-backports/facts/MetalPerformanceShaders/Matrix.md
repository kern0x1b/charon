# The matrix and vector kernels of Metal Performance Shaders on this port

`MPSMatrix`, `MPSVector` and their descriptors and temporary forms; `MPSMatrixUnaryKernel` and
`MPSMatrixBinaryKernel`; `MPSMatrixMultiplication`, `MPSMatrixVectorMultiplication`, `MPSMatrixCopy`,
`MPSMatrixSoftMax`, `MPSMatrixLogSoftMax`, `MPSMatrixSoftMaxGradient`, `MPSMatrixLogSoftMaxGradient`,
`MPSMatrixFindTopK`, `MPSMatrixSum`, `MPSMatrixNeuron`, `MPSMatrixNeuronGradient`,
`MPSMatrixFullyConnected`, `MPSMatrixFullyConnectedGradient`, `MPSMatrixBatchNormalization` and
`MPSMatrixBatchNormalizationGradient`. The core they stand on is in [Core.md](Core.md).

Source: the headers of `MPSMatrix` and `MPSNeuralNetwork` in the SDK of iOS 16.4, which is the SDK this
package compiles against, for every signature, default and formula — including the formulas
`MPSCNNNeuronType.h` writes next to each of its cases, and the ones `MPSMatrixSum.h`,
`MPSMatrixFullyConnected.h` and `MPSMatrixBatchNormalization.h` write in their own discussions. The
behaviour was measured against the MPS of macOS 26.5 by `tests/backports/host/mpsmatrix/run.sh`, which
compiles the cases twice — once against the system's own MPS, once against this port's classes under
names of their own — and compares the two answers element by element.

**That earlier claim — "1267 cases, identical bit for bit" — was wrong and is withdrawn.** It was made
from a harness that printed the values it was given rather than the values the kernel wrote, and three
defects in the harness have since been found and fixed: the outputs were prefilled with zero, so "not
written" and "written zero" were the same thing; the hex is little-endian byte order and was read in the
wrong order, which turned 16.0 into 4.0; and a pointer print compared the case's C array with the
object's buffer, which the comparison never mixed. A fourth was mine and not the harness's: a `BUILD`
path one level short wrote the results into `tests/` while I read the worktree root's copy, which was
stale for an afternoon.

**What the harness measures now, as of the last run: 137 compared cases, 85 of them differing** — 73
where both sides wrote and the values differ, and 12 where the host writes zeros and the port does not.
Each run prints the tree it measured, so a count cannot outlive its code. The counts are in flux while
the families are worked through and this paragraph is the one to re-measure, not to trust.

## MPSMatrixSum's bias is broadcast, and the port indexes it

The header writes the operation out itself:

    A = empty matrix;
    for (i = 0; i < N; ++i)  A += alpha[i] * B[i];
    if (bias)                A += broadcast(bias);
    if (neuron)              A = neuron(A);

**`broadcast(bias)` is one value added to every element.** The port indexes the bias by the column —
`bias[column]` — which is a per-column bias and a different function. Element 0 agrees, because for
column 0 the broadcast value and the column's own value are the same element of the vector; the
columns after it cannot agree, and measured they do not:

    sum 0   host  1.25  -0.5   8.25  50.25  5.5   8
            port  1.25   1.5   4     10.25  3.5   6

The first element matching and the rest not is the signature of a per-column bias read where a
broadcast one is meant, and it is the lead for this family of fifteen. **Not yet fixed** - the
count is unchanged and this is the reading the header supports, measured, for whoever takes it next.

## The batch range, and how the release reads it

`MPSMatrixMultiplication` has two passes over the batch: one that checks every matrix holds the region
its origin names, and one that computes. Both start at the batch's **first** index, which is what
`batchStart` is - "the index of the first matrix to process" - and `CharonMPSBatch` implements the
header's rule that a `batchSize` of 0 means all of them.

**The release does not.** Measured over three matrices, right-hand side scaled so matrix *i* writes its
own index, so a written matrix is unmistakable:

| `batchStart` | `batchSize` | matrices the release writes |
| --- | --- | --- |
| 0 | 0 | none |
| 1 | 0 | none |
| 0 | 2 | 0, 1, 2 |
| 1 | 2 | 0, 1, 2 |
| 1 | 1 | 0, 1, 2 |
| 2 | 1 | 0, 1, 2 |

**Two divergences from its own header, both measured.** `batchStart` is **ignored** - every combination
writes the same three matrices - and a `batchSize` of 0 processes **none**, where the header says "0 to
process all of them".

This port follows the header: it starts at `batchStart`, and a `batchSize` of 0 processes everything
available. That is the correct reading and it is not changed to match the host, because the host's
behaviour is not a rule that generalises - it is the same answer for every input, which is what a
property that is read and discarded looks like.

## Where the arithmetic happens

`MPSMatrix` and `MPSVector` are an `MTLBuffer` and a shape. On this port an `MTLBuffer` is host memory
the CPU reads and writes directly (`facts/Metal/RenderPath.md`), so a matrix kernel is a loop over that
memory: the address of element `[matrix, row, column]` is
`buffer.contents + offset + matrix * matrixBytes + row * rowBytes + column * elementSize`, which is
the layout `MPSMatrix.h` states. The result is in the buffer when `-encodeToCommandBuffer:` returns,
which is at least as strong as the release's own contract, which is that it is there once the command
buffer completes.

The eight element data types an `MPSMatrix` may hold — `MPSDataTypeFloat32`, `Float16`, `Int8`,
`Int16`, `Int32`, `UInt8`, `UInt16`, `UInt32` — are all read and written exactly. The others
`MPSDataType` names are not matrix element types: `Invalid`, the normalized encodings and `Bool`
describe how a *texture's* values are stored, and a matrix that is given one is refused in the log
rather than stored as something of a different meaning. `Float16` is IEEE 754 binary16 converted in
software in both directions, with round to nearest even on the way in, rather than through the
compiler's `__fp16`: a half load and store is not available on every armv7 core this port targets, and a
conversion the compiler may fold is a conversion nobody measured.

## The descriptors

`+rowBytesForColumns:dataType:` and `+vectorBytesForLength:dataType:` are the recommended strides, and
the rule was measured over all eight data types and seventy column counts rather than guessed: **zero
columns have no stride, one column is one element, a floating point row is rounded up to a multiple of
sixteen bytes and an integer row to a multiple of four elements.** So one float is four bytes, two
floats are sixteen, five floats are thirty-two, one `int8` is one byte and two are four. The
`MPSMatrixDescriptor` built from rows, columns, a stride and a data type holds **one** matrix, and its
`matrixBytes` is `rows * rowBytes` — both fixed when it is made, and not worked out again when `rows`
or `rowBytes` are changed afterwards, which is what the release does too (the differential prints the
descriptor before and after a mutation and the two runs agree).

## The kernels

* **`MPSMatrixMultiplication`** is `C = alpha * op(A) * op(B) + beta * C` over the three shapes its
  initialiser names, with the left, right and result origins and the `batchStart`/`batchSize` range. The
  release requires an origin's `z` to be zero: the batch is the range, and the origin moves the window
  inside each matrix of it. The differential covers all four transposition combinations with
  `alpha = 2` and `beta = 0.5`, half precision, and a two-of-three batch.
* **`MPSMatrixVectorMultiplication`** is `y = alpha * op(A) * x + beta * y`, both orientations.
* **`MPSMatrixCopy`** moves a `copyRows` x `copyColumns` window from each source of a
  `MPSMatrixCopyDescriptor` into its destination, transposing on the way in or out as the kernel's two
  flags say, from the four offsets the descriptor holds. The per-row and per-column permute vectors
  reorder the result: an index names the source position of the destination row or column, and an index
  outside the window is refused in the log. The descriptor's own array initialiser reads its offsets
  from the `MPSVector` given, which is a packed array of `MPSMatrixOffset` from that vector's offset
  plus the byte offset the caller names.
* **`MPSMatrixSoftMax`** normalises each row, taking the exponentials of the row relative to its
  largest value so they cannot overflow; **`MPSMatrixLogSoftMax`** is the same kernel with that
  subtraction kept in logarithms. Their gradients are the formula `MPSMatrixSoftMax.h` states,
  `dL_dX_ij = Y_ij * (dL_dY_ij - sum_k(dL_dY_ik * Y_ik))`, with `Y` the forward kernel's output.
* **`MPSMatrixFindTopK`** writes the k largest values of each row, largest first, and the column each
  came from counted from `indexOffset`. The differential includes a row with its largest value twice,
  so the order a tie is decided in is compared too.
* **`MPSMatrixSum`** is the operation `MPSMatrixSum.h` writes out: the sum over the sources of
  `alpha[i] * B[i]`, with the factors from the scale vector from `startIndex`, each source read from
  where the packed `MPSMatrixOffset` array says and transposed if the kernel was made that way, then
  the bias broadcast across the rows, then the neuron. The release requires at least two matrices to
  sum.
* **`MPSMatrixNeuron`** is `y = neuron(alpha * x + bias)`, the bias indexed by the column, which is the
  channel. **`MPSMatrixNeuronGradient`** is that neuron's own derivative at the intermediate value times
  `alpha`, with the bias gradient the column sums of the incoming gradient. All fifteen neuron types
  `MPSCNNNeuronType.h` names are in the differential, each with the parameters A, B and C, and PReLU
  with a per-channel A through `-setNeuronToPReLUWithParametersA:`. The derivative of each type is the
  value its own formula differentiates to, computed in double so the ratio that decides a `softplus` or
  a `logarithm`'s parameter is not decided by a rounded one.
* **`MPSMatrixFullyConnected`** is `y = neuron(alpha * x * W + bias)`, the weight matrix
  `inputFeatureChannels` x `outputFeatureChannels`; its gradient's two encodes are `dX = alpha * dY * W^T`
  and `dW = alpha * X^T * dY` with the bias gradient the column sums of `dY`.
* **`MPSMatrixBatchNormalization`** is the formula its header gives,
  `y[i,j] = gamma[j] * (x[i,j] - mean(x[:,j])) / (variance(x[:,j]) + epsilon) + beta[j]` — the variance
  added to epsilon, not the square root of it, as the header writes it. `computeStatistics` makes the
  kernel work from the mean and variance of its input and write them back, which is what a training
  pass needs. The gradient is the usual per-channel form, and the differential prints the mean, the
  variance, the result and all three gradients for every neuron type.

`sourceRows`, `sourceColumns`, `sourceNumberOfFeatureVectors`, `sourceInputFeatureChannels` and
`sourceOutputFeatureChannels` all default to `NSUIntegerMax`, which is the header's "take the shape
from the matrix", and at encode time each is the smaller of what the caller asked for and what the
matrix holds from the origin. `MPSMatrixBatchNormalization.epsilon` defaults to the smallest positive
normal single precision value, so a variance of zero does not divide by zero in a caller who has not
chosen one.

## Refusals

Every kernel checks that each matrix holds the region its origins and shapes name, and that the data
types are element types, and refuses in the log — naming the kernel, the batch and the region — rather
than reading or writing past the end. The release asserts in the same cases. An API in this port does
not crash its caller, and a quiet wrong answer would be worse than either; the destination is left as
it was found. The initialisers the headers mark unavailable (`-init` on `MPSMatrix`, `MPSVector`,
`MPSMatrixCopy`, `MPSMatrixSum`, `MPSState`, `MPSCommandBuffer` and `MPSMatrixCopyDescriptor`,
`-initWithDevice:` on the kernels whose shape their initialiser names, and
`-initWithBuffer:descriptor:` on the temporaries) answer nil with a line in the log naming the
initialiser to use.

## What differs

`MPSMatrixNeuronGradient`'s bias gradient and several of the neuron results differ from the release's.
The neuron results are one or two units in the last place of a `float` and are the rounding work. The
bias gradient was a rule this port had wrong, and `bias-probe.m` now reads the release's answer one
element at a time.

**The rule, read from the release.** With the incoming gradient held to one element at a time and
then to a general one, the release writes, for each feature channel `j` and feature vector `i`:

```
    resultGradientForBiasVector[j]  =  sum over i of   dY[i][j] * f'( alpha * x[i][j] + bias[j] )
    resultGradientForDataMatrix[i][j] =  dY[i][j] * f'( alpha * x[i][j] + bias[j] ) * alpha
```

**The two differ by exactly the scale factor**, because `alpha` scales the input and not the bias, and
`f'` is the neuron's own derivative at the intermediate value. This port was writing the plain column
sum of the incoming gradient into the bias vector, which is that formula only when `f'` is one
everywhere — true of the identity and of nothing else.

The evidence, all of it the release's own answers (`bias-probe.m`):

* a single one in the first column, at the intermediate value `0.5 * (-2) + 0.25 = -0.75`, gives 1 for
  the identity, `a = 1.5` for ReLU below zero and for Linear, and `0.217894986` for the sigmoid, which
  is `s(1-s)` at `s = 1/(1+e^0.75)` — each exactly that neuron's derivative there;
* a general incoming gradient reproduces the formula for ReLU (`5, 5.25, 5.125, 8.0625`, which is the
  per-element derivative changing across the column), for the absolute value (`-2.5, 0.25, 5.125,
  -1.9375`, which is the sign of the intermediate), and for the identity, where it collapses back to
  the column sums.

A claim I made in the same round — that the rule "does not extrapolate" to a general incoming gradient
— was wrong, and came from reading a run whose inputs had not been read back out of their buffers. The
four general cases above are the check.

`-[MPSState resourceSize]`, and with it `MPSStateBatchResourceSize`, answer this port's own number of
bytes — what the state's description implies, or the length of a resource the caller supplied. The
release answers a number about its own heap: a state made from a 64 byte buffer is 16384 there and 64
here. `MPSState.h` says of that method that it "is subject to change between different devices and
operating systems", which is the header declining to promise a value, so this is a documented
divergence rather than a wrong answer. The differential prints both numbers side by side on every run
and compares everything else.

`MPSStateBatchIncrementReadCount` returns the **size of the batch**, not a read count. That is what the
release's own answers say — a batch of one, two and three states answers one, two and three whatever
the counts become — so it is what this port answers. The counts themselves move by the amount, stopping
at zero and saturating at the top rather than wrapping, and the differential prints them around the
call so both facts are compared.

## Not carried yet

`MPSMatrixSolveTriangular`, `MPSMatrixSolveLU`, `MPSMatrixSolveCholesky`, `MPSMatrixDecompositionLU`,
`MPSMatrixDecompositionCholesky`, `MPSMatrixRandom`, `MPSMatrixRandomPhilox`, `MPSMatrixRandomMTGP32`
and `MPSMatrixRandomDistributionDescriptor` are the linear solver and the random number generators, and
they are the next part of this library. `MPSMatrixCopyToImage` needs `MPSImage`. Nothing in this file
depends on them, and nothing above is affected by their absence.
