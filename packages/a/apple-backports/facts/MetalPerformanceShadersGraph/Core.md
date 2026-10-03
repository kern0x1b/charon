# The graph framework on this port: the builder side and the arithmetic family

`MPSGraphObject`, `MPSGraphType`, `MPSGraphShapedType`, `MPSGraphDevice`, `MPSGraphTensor`,
`MPSGraphOperation`, `MPSGraphTensorData`, `MPSGraph`, `MPSGraphExecutable`,
`MPSGraphExecutionDescriptor` and `MPSGraphExecutableExecutionDescriptor`, and the arithmetic family of
`MPSGraph`'s factory methods.

Source: the headers of `MetalPerformanceShadersGraph` in the SDK of iOS 16.4, which is the SDK this
package compiles against, for every signature; the 26.2 headers under
`charon/.agent-work/sdk-26.2/` for what 16.4 does not declare. The behaviour is measured against the
system's own MPSGraph by `tests/backports/host/mpsgraph/run.sh`.

## The model, and why it is a walk rather than a compiler

A graph is a description of work, and a tensor is a description of a result. Running a graph therefore
means walking the operations **in the order they were added** and asking each to fill its outputs from
its inputs and from the feeds: an operation can only read what an earlier one wrote, and the order they
were added is the order that guarantees it. A tensor's value is found by looking it up — a placeholder's
comes from the feeds, any other one's from the operation that produced it.

`MPSGraphExecutable` is then the graph itself. The release compiles a graph into device code and holds
the results on the device; this port holds them in the host memory behind an `MTLBuffer`, so there is
nothing to compile ahead of time and the executable is the graph plus the targets the compile named.
That is not a shortcut around the graph, it is the same graph with the storage the device already has.

## Where the arithmetic happens, and in what precision

Over the host memory behind an `MTLBuffer`, on the CPU, exactly as the matrix kernels in
`../MetalPerformanceShaders` do (`facts/MetalPerformanceShaders/Matrix.md`). The data type of the
operands decides the arithmetic, as it does there, through the same `CharonMPSStore` and `CharonMPSLoad`:
`CharonMPSGraph.h` **includes** `CharonMPS.h` rather than restating it, so an `MPSDataType` means one
thing in both families rather than two.

A result tensor's storage is a buffer of its own, made when the operation runs, so a run never writes
into a buffer the caller fed it.

## Four names the build's SDK does not declare

The iPhoneOS 16.4 SDK predates four names of the 26.2 surface:

* **`MPSGraphObject`** arrived in iOS 17, and every class of that surface descends from it there,
  while 16.4 has them descending from `NSObject`. It is declared in `CharonMPSGraph.h` and implemented
  here, so a graph's objects have the root the 26.2 headers give them.
* `MPSGraphFFTDescriptor`, `MPSGraphImToColOpDescriptor` and
  `MPSGraphExecutableSerializationDescriptor` are in the 26.2 surface and not in the 16.4 headers.

The declarations are guarded on a host SDK that already has them — where redeclaring would be a
duplicate, and where the host's own classes are what a comparison must be against.

**Four registered names that no header the build compiles against declares** is a rule R4 item: the
lift's sets have to be re-measured in the same push as these land.

## The measuring, and where it stands

`tests/backports/host/mpsgraph/` compiles the same cases twice — once against the system's own
MPSGraph, once against these classes with the MPSGraph names mapped to `Charon` names and their
selectors prefixed — and compares the bytes of a buffer the case owns.

**Both execution routes work on this host**, measured directly:

* compiling with a shaped-type feed and running through
  `-[MPSGraphExecutable runWithMTLCommandQueue:inputsArray:resultsArray:executionDescriptor:]` over a
  result buffer the caller owns answers `[11 22 33 44]` for two 2x2 placeholders and one addition. This
  is the route the differential uses, because it is the only one where the answer lands somewhere the
  case can read: `MPSGraphTensorData` has no accessor for its bytes in either the 16.4 or the 26.2 SDK.
* `-[MPSGraph runWithFeeds:targetTensors:targetOperations:]` answers too, and is one call.

**What the differential found, in order.** All of these were bugs, and the first two were mine in the
harness rather than in the library:

* **A `memmove` on a null destination.** The interpreter made a result's storage from an empty `NSData`,
  which is a zero-length buffer whose `contents` is null. A result now takes a buffer of the shape's
  own size, made and zeroed when the tensor data is made.
* **The inputs paired with the feed tensors in the wrong order.** `-[MPSGraphExecutable
  runWithMTLCommandQueue:...]` took the feed tensors from the dictionary's key order, which is
  arbitrary, so the second operand reached the first tensor and every non-commutative operation read
  its arguments backwards: subtraction answered `9, 18, 27…` where the release answers `-9, -18,
  -27…`. The pairings are now in the graph's placeholder order, which is the order the caller passed
  the inputs in.
* **The harness overwrote its own inputs.** It remembered each *feed's* buffer as well as the result's,
  and read every remembered buffer back into the array it came from, so after the first case each input
  array held the previous case's output and both sides agreed on the wrong numbers. Only the result
  buffer is read back now.
* **A square root of a negative, three times.** I read the chain case — where the product is positive even
  where the sum is not, so no negative ever reaches the root — as the release's root answering a
  magnitude, and changed it to `fabs`. Measured over a feed of `(1, 2, 3, 4, -1, -2, -3, -4)`, the
  release answers `1, 1.41421, 1.73205, 2` and then four NaNs. It is a NaN, it is one again, and
  `MPSGraphOperationKindSqrt` now takes `sqrt(a)`: over the sixteen classes below the whole row is
  byte-identical to the release's, element for element.
* **A branch that decided a division, a reciprocal, a square root and a logarithm by itself.** Each of the
  four had a case for the values the arithmetic is undefined at — `b == 0.0`, `a == 0.0`, `a < 0.0`,
  `a <= 0.0` — and each of the first two chose its infinity from the sign of the dividend alone, so it had
  one answer where the arithmetic has two: `-1 / -0.0` is `+inf` and the division branch had only `-inf`
  for it, and a reciprocal of `-0.0` is `-inf` where the reciprocal branch had only `+inf`. The measured
  columns `reciprocal` and `divide` carry both zeroes, `ff800000` and `7f800000`, which is what the case
  file feeds now. IEEE division answers every one of them, so the four cases are the arithmetic itself.
* **A denormal, and a NaN of its own.** `CharonMPSGraphAsZero` and `CharonMPSGraphOwnNaN` are what a result
  leaves the release's arithmetic as, and they are in `CharonMPSGraphApply` rather than in the store,
  because `CharonMPSStore` is shared with the matrix and image families and because two kinds keep both: the
  measured table below has `abs` and `identity` returning `0x00000001` and `0x7f800001` unchanged.

**Where it stands, measured on macOS 27.0 build 26A428 (M4 Pro, Metal 4):
`tests/backports/host/mpsgraph/run.sh` ends `port: same as the system, case for case and bit for bit` and
`checks=15 failures=0` over `compared: 15 cases`.** Every case is byte-identical to the release's, and the
case file feeds all sixteen classes of the table below to each of them rather than the eight values that
first showed a difference. The planted build beside it is the control: `red control: the planted build
differs from the release in 13 of 15 cases`, which is every line of the run that is a case - the other two
are the graph device's type and a shaped type's data type, neither of which is a stored element.

What the release answers for each class, float32, one row per input and one column per unary operation.
Every cell is the four bytes it wrote:

| input | bits | sqrt | rsqrt | square | reciprocal | log | abs | sign |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| +1 | `3f800000` | `3f800000` | `3f800000` | `3f800000` | `3f800000` | `00000000` | `3f800000` | `3f800000` |
| -1 | `bf800000` | `7fc00000` | `7fc00000` | `3f800000` | `bf800000` | `7fc00000` | `3f800000` | `bf800000` |
| -0.0 | `80000000` | `80000000` | `ff800000` | `00000000` | `ff800000` | `ff800000` | `00000000` | `00000000` |
| 0.0 | `00000000` | `00000000` | `7f800000` | `00000000` | `7f800000` | `ff800000` | `00000000` | `00000000` |
| +inf | `7f800000` | `7f800000` | `00000000` | `7f800000` | `00000000` | `7f800000` | `7f800000` | `3f800000` |
| -inf | `ff800000` | `7fc00000` | `7fc00000` | `7f800000` | `80000000` | `7fc00000` | `7f800000` | `bf800000` |
| qNaN | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `00000000` |
| -qNaN | `ffc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `00000000` |
| denormal 0x00000001 | `00000001` | `00000000` | `7f800000` | `00000000` | `7f800000` | `ff800000` | `00000001` | `00000000` |
| denormal 0x007fffff | `007fffff` | `00000000` | `7f800000` | `00000000` | `7f800000` | `ff800000` | `007fffff` | `00000000` |
| -denormal 0x80000001 | `80000001` | `80000000` | `ff800000` | `00000000` | `ff800000` | `ff800000` | `00000001` | `00000000` |
| smallest normal 0x00800000 | `00800000` | `20000000` | `5f000000` | `00000000` | `7e800000` | `c2aeac50` | `00800000` | `3f800000` |
| 0x00ffffff | `00ffffff` | `203504f3` | `5eb504f4` | `00000000` | `7e000001` | `c2ad496b` | `00ffffff` | `3f800000` |
| 1e-20 | `0e8d1e59` | `27066639` | `57f3cf8f` | `00000000` | `706833b2` | `c287a965` | `0e8d1e59` | `3f800000` |
| 0x3f7fffff | `3f7fffff` | `3f7fffff` | `3f800000` | `3f7ffffe` | `3f800001` | `b3800000` | `3f7fffff` | `3f800000` |
| qNaN payload 0x7f800001 | `7f800001` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7fc00000` | `7f800001` | `00000000` |

Four things in it are worth naming, because each one is a rule rather than a value:

* **A denormal is read as a zero of the same sign and never answered.** `sqrt` of `0x00000001` is
  `00000000` and of `0x80000001` is `80000000`; `sign` of `0x00000001` is `00000000`; `reciprocal` of
  `0x00000001` is `7f800000`. The result is flushed as well as the operand, which is a different rule and
  shows in one row: `square` of `0x00800000` is `00000000`, because the square of the smallest normal is a
  denormal, while `square` of `0x3f7fffff` is `3f7ffffe`, which is neither.
* **A NaN a kind computes is the arithmetic's own.** Every computing column answers `7fc00000` for
  `ffc00000` and for the payload-carrying `7f800001` — the sign and the payload are both gone — and the
  two copying columns are the two that keep them: `abs` of `7f800001` is `7f800001`, and `identity` of
  `7f800001` is `7f800001` too.
* **A negative zero is a negative zero.** `sqrt` of `80000000` is `80000000`, where a `fabs` before the
  root could not have answered it.
* **`log` of a zero is `-inf` and `sign` of a NaN is `0`.** Both are in the table and neither needs a case
  of its own, which is the point of taking them out.

**A half is a different arithmetic, and this host cannot be its oracle.** Measured over the same sixteen
classes in `MPSDataTypeFloat16`, the release answers the square root of a half `-1.0` with `0000` — a zero
where IEEE and every float32 column above answer a NaN — the square root of a half `NaN` with `7c00`, an
infinity, the logarithm of a half `0.0` with `f98c`, which is `-45440` rather than `-inf`, and the sign of a
half `NaN` with `3c00`. An identity operation that answers an infinity for a NaN is not a copy, so these
are a different implementation underneath rather than the same arithmetic in a narrower type. **Owed, and
not attempted here**: the port's half path computes in double and stores through `CharonMPSFloatToHalf`, so
it answers what the table above calls precise, and matching this host's half kernels means implementing
them rather than adjusting a threshold. `CharonMPSGraphAsZero` is therefore a float32 answer, and a half
denormal keeps its value here for the same reason.

Two of the case file's cases are not counted as agreeing:

* **A constant** cannot be asked for at all on this host. `-[MPSGraph constantWithShape:dataType:values:name:]`
  aborts the process, so it is asked for **last**, after everything the host does answer, and the run
  stops there on the host side. An earlier version of the case file had it in the middle of the unary
  family, where it took seven cases down with it - and because the harness compared the shorter of the
  two runs, those seven counted as agreeing.
* **A placeholder's `dataType`** is the other one that is not comparable, for the reason below.

The harness now **fails on a length mismatch** rather than truncating to the shorter side, and names the
case each side last reached, so an abort in either run cannot be read as agreement.

One thing the harness did teach, and which is written into the case file: **reading a shaped type's
equality, or a placeholder's `dataType`, takes the release down** — it calls
`-[MPSGraphTensor tensorDataType]`, a selector its own `MPSGraphTensor` does not declare. So those
answers are not comparable on this host and the case file does not ask for them.

## The arithmetic family, and the rest

Addition, subtraction, multiplication, division, and the unary operations negation, square,
reciprocal, square root, reverse square root, exponential, logarithm, absolute and sign. Each is a kind
in `CharonMPSGraphOperationKind` and a case in the interpreter, so a family lands by adding a kind and a
function rather than by touching every other operation.

Not written: reductions, matmul, convolution, pooling, normalization, activation, shape operations,
control flow, random, optimizers, and the rest of the surface. Each is a family of the same shape, and
each wants the differential to run a graph end to end first.

## The R4 names this band adds, in full

The SDK this package compiles against, the iPhoneOS 16.4 one, declares none of these: they are the
private surface the two families use to share their own state, and each is a registered implemented name
that no header the build sees declares. **27 of them**, read out of the compiled objects with
`nm -g --defined-only`, not from the sources, so a declaration and a definition are not confused:

* `-[MPSGraph charon_mps_addOperationOfKind]` — MPSGraph14.m
* `-[MPSState charon_mps_appendBuffer]` — MPSState11.m
* `-[MPSState charon_mps_appendResource]` — MPSState11.m
* `-[MPSState charon_mps_appendTexture]` — MPSState11.m
* `-[MPSGraph charon_mps_arithmetic]` — MPSGraph14.m
* `-[MPSMatrixRandom charon_mps_batchOver]` — MPSMatrixRandom13.m
* `-[MPSMatrixRandom charon_mps_configureWithDataType]` — MPSMatrixRandom13.m, MPSMatrixRandomMTGP3213.m, MPSMatrixRandomPhilox13.m
* `-[MPSMatrixCopy charon_mps_destinationAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSCNNConvolutionDescriptor charon_mps_fold]` — MPSCNNConvolutionDescriptor10.m
* `-[MPSCNNBatchNormalization charon_mps_foldFromDataSource]` — MPSCNNBatchNormalization12.m
* `-[MPSCNNConvolutionWeightsAndBiasesState charon_mps_listOfBufferSizes]` — MPSCNNConvolutionWeightsAndBiasesState11.m
* `-[MPSMatrixCopy charon_mps_offsetsAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSGraph charon_mps_operation]` — MPSGraph14.m
* `-[MPSGraph charon_mps_runOperation]` — MPSGraph14.m, MPSGraphInterpreter14.m
* `-[MPSMatrixLogSoftMax charon_mps_setLogarithmic]` — MPSMatrixLogSoftMax12.m, MPSMatrixSoftMax12.m
* `-[MPSCNNPooling charon_mps_setMaximum]` — MPSCNNPooling10.m
* `-[MPSCNNConvolutionDescriptor charon_mps_setNeuronParameterC]` — MPSCNNConvolutionDescriptor10.m
* `-[MPSGraph charon_mps_setOutputTensors]` — MPSGraph14.m, MPSGraphOperation14.m
* `-[MPSGraph charon_mps_setParameters]` — MPSGraph14.m, MPSGraphOperation14.m
* `-[MPSCNNKernel charon_mps_setWindowWidth]` — MPSCNNKernel10.m, MPSCNNPooling10.m
* `-[MPSMatrixCopy charon_mps_sourceAtIndex]` — MPSMatrixCopy11.m, MPSMatrixCopyDescriptor11.m
* `-[MPSState charon_mps_temporaryWithBlock]` — MPSState11.m
* `-[MPSMatrixCopyDescriptor charon_mps_withCount]` — MPSMatrixCopyDescriptor11.m
* `-[MPSTemporaryMatrix charon_mps_withReadCount]` — MPSTemporaryMatrix11.m, MPSTemporaryVector12.m
* `-[MPSMatrixRandom charon_mps_wordAtIndex]` — MPSMatrixRandom13.m
* `-[MPSCNNPooling charon_mps_zeroPadSizeX]` — MPSCNNPooling10.m
* `-[MPSCNNPooling charon_mps_zeroPadSizeY]` — MPSCNNPooling10.m

The graph's are the interpreter's — its kinds, its per-operation wiring, its element accessors — and the
matrix and CNN families' are the window, the fold, the state and the copy descriptor's. None of them is
called by an application. Each needs the lift's sets re-measured in the same push as the ones that land
with them, and the list is regenerated from the objects whenever the family changes.
