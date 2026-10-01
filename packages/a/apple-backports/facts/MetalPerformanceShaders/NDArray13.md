# The NDArray substrate of iOS 13, and the three kernels that stand on it

`MPSNDArray`, `MPSNDArrayDescriptor`, `MPSTemporaryNDArray` and the allocator, then the
`MPSNDArrayMultiaryBase` family and the kernels that carry real arithmetic: `MPSNDArrayGather` and
its gradient, `MPSNDArrayStridedSlice` and its gradient, and `MPSNDArrayMatrixMultiplication`. The
source is the headers of the SDK of iOS 16.4 - `MPSCore/MPSNDArray.h`, `MPSNDArray/MPSNDArrayKernel.h`,
`MPSNDArray/MPSNDArrayGather.h`, `MPSNDArray/MPSNDArrayStridedSlice.h`,
`MPSNDArray/MPSNDArrayMatrixMultiplication.h` and `MPSNDArray/MPSNDArrayGradientState.h`.

## What was measured, and against what

`tests/backports/host/mpsndarray/run.sh` builds the same case file twice and compares the two runs
line by line: once against the system's own MetalPerformanceShaders, once against this port's classes
renamed out of the way. **31 lines compared, 0 mismatches**, and both planted builds are caught.

The reason a release-side oracle is possible here at all is that an `MPSNDArray` is storage, not a
kernel. This is the one part of MPS the release's own framework answers on this host - and it is worth
being exact about the boundary, because the image and matrix families in this package cannot make the
claim: `tests/backports/host/mpsimage9/run.sh` records that this host's AGX family does not implement
`computeCommandEncoderWithDispatchType:`, and the release's own `MPSImage` kernels die encoding with
`-[AGXG16XFamilyCommandBuffer mtlnext computeCommandEncoderWithDispatchType:]: unrecognized selector`.
The three kernels here are NOT covered by that oracle and their rows say so.

**Two cases the release cannot answer on this host**, and this is measured rather than assumed. Its own
`-exportDataWithCommandBuffer:toBuffer:destinationDataType:offset:rowStrides:`, and its
`MPSAliasingStrategyShallNotAlias` copy path, both die with

    -[AGXG16XFamilyCommandBuffer_mtlnext retainedReferences]: unrecognized selector

raised inside `MPSCore`'s `MPSNewBufferForTexture` on its way to `MPSDecrementReadCount`. So the same
AGX-family limitation the image family records is reached here through a STORAGE path rather than a
compute one. Those two cases live in `export-cases.m`, which runs against the port alone, states its
own expectations and is labelled as such; no number from it measures Apple's code.

## Four things the release's own answers settled, each of which was wrong here first

Every one of these was implemented the way the headers read, and the differential caught it. They are
written down because a reader who trusts the header's prose over the release's behaviour will make
the same four mistakes.

**The storage is packed; the 16-byte row is an allocation size, not an address.** The class
discussion recommends a row "at least a multiple of 16 bytes", and `-resourceSize` of a `[2,3,4,5]`
float32 array answers 960 - 16 bytes a row over `3*4*5` rows. It is tempting to read that as the
element at `(1,2,3,4)` living at `1 + 2*4 + 3*12 + 4*48`. It does not: cases 5, 6, 7 and 8 each name
the values and only the packed reading answers all four. A `[2,3]` array written `1..6` and read
back gives `1 3 5 2 4 6` transposed, which is `d0 + 2*d1` and not `d0 + 4*d1`.

**`-lengthOfDimension:` on a DESCRIPTOR reads through the permutation; on an ARRAY it does not.** A
`[2,3]` descriptor transposed on dimensions 0 and 1 - the header's own worked example at
`MPSCore/MPSNDArray.h:70-74` - answers `-lengthOfDimension:0` with **3** (case 4). A transposed VIEW
of a `[2,3]` array answers **2** (case 7), and a view of a `[3,4,2]` array sliced on dimension 1
answers **3, 4, 2** (case 6) - the whole shape, with the slice not narrowing it. The header permits
that second one: "The dimension length is at least as large as the existing slice length"
(`MPSCore/MPSNDArray.h:235-237`). So the array keeps its whole shape beside its view descriptor, and a
walk that bounded itself by `-lengthOfDimension:` would run off the end of every slice.

**A slice changes the packed walk and not the shape.** Case 6's view reads twelve elements - the
slice's own values in the slice's own order, `7 8 9 10 11 12` then `19 20 21 22 23 24` - out of a view
whose shape says twenty-four. The twelve past the slice are zero, which is why `-readBytes:` here
clears the caller's buffer before gathering rather than leaving whatever was in it.

**A nil `strideBytes` array means PACKED, which is a different number from the storage stride.** The
header says the strides are "calculated for you assuming that the data is packed without additional
space in between elements, rows, etc" (`MPSCore/MPSNDArray.h:389-392`). So a non-nil array is the
caller's own byte stride per dimension, and a nil one is the packed form; the two sides of a copy are
separate walks and neither is derived from the other.

## The plant, and why this object's is not the family-wide one

The matrix family's control is `CHARON_PLANT` in `CharonMPS.h`, which perturbs what `CharonMPSStore`
writes. **It cannot reach this object, and that is measured.** This file copies BYTES and never calls
the store - the release's own accessors copy bytes too, "Copy bytes from MPSNDArray into buffer" and
"Copy bytes from a buffer into the MPSNDArray" (`MPSCore/MPSNDArray.h:383` and `:397`) - so a plant on
the store path produces a byte-identical binary and a green run the harness did not earn. The control
here is `CHARON_NDARRAY_PLANT`, which perturbs the copy itself.

Two things about it were found by the harness refusing to go green, and both are worth recording:

- The values are printed as **raw bytes**, not as `%.6g`. A planted build that shifts one bit of one
  element's exponent is invisible at six significant figures - `1.0f` and `1.0000002f` print the same -
  and the first version of this harness reported `PLANT 1 SURVIVED` for exactly that reason.
- The plant **adds**, it does not exclusive-or. The macro is on both the write and the read, so an
  exclusive-or applied twice over one element - once storing it into the array, once gathering it out
  - cancels, and the planted build printed exactly the unplanted bytes. The harness caught that as a
  second `PLANT SURVIVED`, which is the control working.

## What a view is, and what it costs

`MPSCore/MPSNDArray.h`'s class discussion is the source: a slice and a transpose are usually DEFERRED,
"the slice is performed first and the result of the slice is transposed", and two arrays that share a
common ancestor alias. So a view here is the parent's buffer, an offset and a permutation of the
parent's strides - no copy, and `-parent` answers the array it views.

`MPSAliasingStrategyShallNotAlias` is "Always make a copy" (`MPSCoreTypes.h:329`), and it is honoured
rather than ignored: a view that ignored it would answer a request the header defines with something
that aliases. It is a port-only case, in `export-cases.m`, because the release cannot reach it on this
host.

## What is NOT claimed

The three kernels' encode paths are not measured against the release. They encode into a command
buffer this host cannot commit, which is the same limitation the image family records, so each of
their rows says that the numbers on it are the port's own against a plain C reference written from the
header's own wording and in the same process, and that no number on those rows measures Apple's code.
