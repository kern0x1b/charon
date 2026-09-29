# MPSImage

**The image and its descriptor.** `MPSImage` is a texture; `MPSImageDescriptor` is the shape of one. On
this port the texture is a real `MTLTexture` on the carried Metal classes, made through
`MTLTextureDescriptor` and read and written through the texture's own
`getBytes:bytesPerRow:fromRegion:mipmapLevel:` and `replaceRegion:mipmapLevel:withBytes:bytesPerRow:`, so
the read a kernel makes and the read a caller makes go the same way.

**What the 26.2 names in the tree.** `+[MPSImageDescriptor imageDescriptorWithChannelFormat:width:height:featureChannels:]`
and `-[MPSImage initWithDevice:imageDescriptor:]` are what `tests/backports/host/mpscnn/cnn-cases.m`
calls, and both are in the iPhoneOS 16.4 headers this package compiles against with 16.4's own
signatures, so neither is transcribed. What the release has and this build does not is a
`+defaultAllocator` and the allocator protocol behind it; `-initWithDevice:` with no descriptor names no
shape, and rather than answer 1×1×1 the port refuses and says which initialiser it implements.

**The measurement, and what it was before.** `tests/backports/host/mpscnn/run.sh` builds each of its
five cases' source and destination through this class on the port's side and through the release's on
its own, and compares the values that come back:

    cases: 5, tolerance 0.0001 absolute or relative
    closest to the tolerance, as a fraction of it:
      batch-normalization          0.00118
    differing cases: 0

The four pooling cases are bit-identical and are compared exactly; `batch-normalization` differs on one
of nine elements, 0.00118 of that case's tolerance, which is the order a normalisation accumulates in
and not a different answer.

**Before this class existed, that line was hollow.** The port had no `MPSImage`, the harness's rename
header is generated from the classes the port's objects define, and `MPSImage` was not among them — so
on the port's side the case built its images through the release's own class and the five cases compared
the release with itself. The harness printed that and nothing acted on it:

    image MPSImage                               /System/Library/.../MPSCore
    image CharonMPSImage                         (absent)

`cnn-cases.m` now asks, before each case builds anything, whether the port has every class that case
builds from, and a case that does not is named and counted as *not compared*; the comparison then fails
on the uncompared case. `run.sh` is marked with `-DCHARON_PORT_BUILD` so the question is asked on the
port's build only — the system build links the release's classes and has no port to ask about. The red
line, on the tree as it stood before this class:

    cases the harness refused to compare: 2
      system side: pooling: the port has no MPSImage, so this case reached the host's class on both sides and compared the host with itself
      system side: batch-normalization: the port has no MPSImage, so this case reached the host's class on both sides and compared the host with itself
      port side: pooling: the port has no MPSImage, so this case reached the host's class on both sides and compared the host with itself
      port side: batch-normalization: the port has no MPSImage, so this case reached the host's class on both sides and compared the host with itself
      a case that did not run is not a case that passed; this comparison is red

**That the comparison can fail.** `tests/backports/host/mpscnn/mutation.sh` mutates a copy of the
library under `.agent-work` and points the run at it with `MPS=`, so no tracked file is written. Every
anchor is resolved before the first harness run, in one python process that prints a line per site and
a count, and a stale anchor costs a second:

    anchor check: pooling-divisor        1 occurrence(s) in MPSCNNPooling10.m
    anchor check: image-zero-fill        1 occurrence(s) in MPSImage13.m
    anchor check: 2 sites compared, 0 not resolving exactly once

and the control, with one site's anchor replaced by the other's:

    anchor check: pooling-divisor        0 occurrence(s) in MPSCNNPooling10.m
    anchor check: 2 sites compared, 1 not resolving exactly once
      pooling-divisor occurs 0 times in MPSCNNPooling10.m, and a mutation needs exactly one
    the campaign is not startable: an anchor does not resolve exactly once     exit 1

The campaign, with a control on each side of the mutation:

    pooling divisor      before   cases: 5, tolerance 0.0001 absolute or relative differing cases: 0
    pooling divisor      mutated  cases: 5, tolerance 0.0001 absolute or relative differing cases: 3
    pooling divisor      reverted cases: 5, tolerance 0.0001 absolute or relative differing cases: 0

A divisor one short takes three of the five cases red and the revert takes them back, so the five green
cases above are measuring this port's arithmetic over this port's image.

**A fresh image reads as zeros.** The port zeroes a texture it made, because a texture's contents are
whatever was in it and a kernel reads them; the release zeroes a fresh image too, and a caller that
reads an image before it writes it is answered zeros. The second mutant, `image-zero-fill`, is that
line changed to leave the texture as it came.

**Not carried.** `MPSImageBatch`, `MPSImageState`, `+defaultAllocator` and the allocator protocol, the
image kernels of this family (`MPSImageArithmetic` and the four operations, the five thresholds, the nine
reductions, the statistics, the area and integral kernels, transpose, copy to matrix, median, box and the
four histograms), and the image's `writeBytes:...bytesPerColumn:bytesPerImage:` form. None of them is
carried, and none of them is described here as if it were.
