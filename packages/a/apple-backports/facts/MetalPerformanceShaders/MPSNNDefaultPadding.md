# MPSNNDefaultPadding: the TensorFlow average-pooling factories

The two factories are `+paddingForTensorflowAveragePooling` (`MPSNeuralNetworkTypes.h:500`, header `ios(11.3)`) and
`+paddingForTensorflowAveragePoolingValidOnly` (`:503`, header `ios(11.3)`), in the iOS 16.4 SDK. They are placed by
the measurement, not the header:

- `+paddingForTensorflowAveragePooling` is in the 11.0 band: the release's arm64 shared cache of 11.0 carries the
  selector, so it is in `MPSNNDefaultPadding11.m`. The header's 11.3 is recorded in the registry row as the
  discrepancy it is.
- `+paddingForTensorflowAveragePoolingValidOnly` is in the 11.3 band: the 11.0 cache does not carry it, and it is in
  `MPSNNDefaultPadding113.m`. A file that carried both bands would be the mixed release `misplaced()` refuses.

The base object is `MPSNNDefaultPadding` in `MPSNNGraph11.m`, which carries `+paddingWithMethod:`,
`-paddingMethod`, `-destinationImageDescriptorForSourceImages:...` and the coding pair. Each factory here is a
subclass of that object, created through `+paddingWithMethod:`, with its own `label` and destination.

## What was measured, and where

Host: this Mac, macOS 27.0.1 (Darwin 27.0.0), arm64, an Apple M4 Pro (`MTLCreateSystemDefaultDevice` answers it). The
release's own `MPSNNDefaultPadding` runs here. The differential is `tests/backports/host/mps-cnn-descriptors/cases.m`,
run by `run.sh` for macOS; 58 of 58 checks pass, and the destination cases below are compared value for value on both
sides with the same inputs.

## Apple's answers

Both factories answer a subclass of `MPSNNDefaultPadding` (the release's class names are
`MPSNNTensorFlowPoolingPadding` and `MPSNNTensorFlowPoolingPaddingValidOnly`; the port names its own classes
differently, and the test does not compare class names).

| factory | paddingMethod | label |
| --- | --- | --- |
| ...PoolingPadding... | 0x401c (Custom, SizeSame, AlignCentered, AddRemainderToBottomRight) | `AlignCentered, AddRemainderToBottomRight, SizeSame, MPSNNPaddingMethod.CustomAllowForNodeFusion (ignored without MPSNNPaddingMethodCustom)  variant: MPSNNTensorFlowPoolingPadding` |
| ...ValidOnly | 0x400d (Custom, SizeValidOnly, AlignTopLeft, AddRemainderToBottomRight) | `AlignTopLeft, AddRemainderToBottomRight, SizeValidOnly, MPSNNPaddingMethod.CustomAllowForNodeFusion (ignored without MPSNNPaddingMethodCustom)  variant: MPSNNTensorFlowPoolingPaddingValidOnly` |

Both answer the same object on every call. The two are not equal to each other (identity), and the two are different
objects with different methods.

**The destination.** For a source image, a suggested descriptor, and a kernel (an `MPSCNNPoolingAverage` with window
and stride), Apple's object:

- returns the suggested descriptor itself (the same object), with its size unchanged;
- sets the kernel's `edgeMode` to `MPSImageEdgeModeClamp` (1), from 0 (measured for every case below);
- does not change the kernel's `offset` (0,0 before and after, for every case).

Cases measured (source, suggested, window, stride): 3x3/3x3/2/2, 3x3/2x2/2/2, 5x5/5x5/3/1, 5x5/4x4/3/1, 7x7/3x3/3/2;
the same five on the valid-only factory.

## What the port carries

The port's factories answer those objects: the method above, the label above, the same object on every call, and the
same destination for the same inputs: the suggested object returned, the edge mode set to Clamp, the offset untouched.
The test compares each of these with Apple's object, case for case.

The sizing is not computed by these objects. The release does not compute it either, for these policies: it returns the
suggested descriptor that the graph prepared. A caller that passes a different suggested size gets that size back, from
both sides.

## Not measured

- The edge mode of a kernel without an `edgeMode` property. The port sends the message only to a kernel that has it;
  what Apple does for such a kernel was not run.
- Either object inside a running `MPSNNGraph`. The graph is not run by this test.
- `-inverse`, which the header gives `ios(11.3)` and which neither factory's object answers (`respondsToSelector:`
  is NO on Apple's object). The port does not implement it, and the registry row for `-[MPSNNPadding inverse]` is
  separate.
- Apple's archive keys for these objects. The port's objects are not round-tripped by this test.

## Found in the existing base, not changed here

`MPSNNDefaultPadding`'s `+paddingWithMethod:` in `MPSNNGraph11.m` answers a `label` of nil, where Apple's object answers
a string (measured: `AlignCentered, AddRemainderToTopLeft, SizeSame, ` for `SizeSame`). The test does not compare
`+paddingWithMethod:`, and the base file is outside this change.
