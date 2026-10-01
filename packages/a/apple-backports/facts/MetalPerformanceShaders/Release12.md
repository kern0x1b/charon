# The iOS 12 object of MetalPerformanceShaders

What this band carried, and what it measured and what it did not. Written on 2026-10-01, on branch
`band-SLICE-MetalPerformanceShaders-absent_MetalPerformanceShaders-12`, from `origin/main`
`580d7e435`.

## The slice and how it splits by MEASUREMENT, not by the row's `introduced`

The slice is 47 rows of `registry/MetalPerformanceShaders/absent_MetalPerformanceShaders.json`, and the
slice header calls the whole of it "release 12". The release a name can be PLACED in is not the
release the SDK dates it: `modules/apple/backports.lua:2298` reads it with
`dyld.first_releases(ladder(opt.architecture), ...)` over the HELD ladder, and the held set is dense
to 12.0 and then has no 13.0, 14.0 or 15.0.

`python3 tools/cache-index/first-rung.py` on all 47 names:

| rung | rows |
| --- | --- |
| 12.0 | 20 class rows, and the one method row's selector is not usable (below) |
| 16.0 | 26 class rows, every one of which the SDK dates 12.1 |

So one file cannot hold the slice. A 12.0-ladder name and a 16.0-ladder name in one object is
`misplaced()`'s refusal at `backports.lua:2426-2440` ("an object carries API that arrived in one
release, so split it") and `release-split.lua`'s `MIXED-RELEASES` independently. The 26 therefore
belong to the 16.0 object and this band wrote none of them; each of those rows now says so.

The 47 rows split, measured by the superclass chain in the SDK headers against the classes this
package already implements:

| outcome | rows |
| --- | --- |
| `implemented` | 8 |
| `absent`, superclass not carried by the port | 33 |
| `absent`, superclass carried, this band did not reach it | 6 |

## The superclass check, and why a missing ancestor is not a formality

A class whose superclass the library does not carry cannot be defined at all. The runtime fails to
create the class, the failure takes the WHOLE dylib with it, and one row's missing ancestor becomes
every row's load error. That is why 33 rows are `absent` and not `implemented` with a partial body:
there is no version of "implement it anyway" that is better than not writing it.

The chains, resolved from the 16.4 headers' own `@interface` lines and then checked against every
`@implementation` in `packages/a/apple-backports` on `580d7e435`:

| row | missing ancestor | whose row it is |
| --- | --- | --- |
| the 22 `MPSNNReduction*Node`, `MPSNNUnaryReductionNode`, `MPSNNReshapeNode`, `MPSNNPadNode`, `MPSNNComparisonNode` | `MPSNNFilterNode` | 11.0, this registry file, the release-11 object |
| `MPSNNReshapeGradientNode`, `MPSNNReductionSpatialMeanGradientNode`, `MPSNNPadGradientNode` | `MPSNNGradientFilterNode` -> `MPSNNFilterNode` | 11.0, same |
| `MPSNNReduceFeatureChannelsArgumentMin`, `...Max` | `MPSNNReduceUnary` | 11.3, this file |
| `MPSNNCompare` | `MPSCNNArithmetic` -> `MPSCNNBinaryKernel` | 11.0, this file |
| `MPSNNReshapeGradient`, `MPSNNPadGradient` | `MPSCNNGradientKernel` -> `MPSCNNBinaryKernel` | 11.0, this file |
| `MPSTriangleAccelerationStructure`, `MPSAccelerationStructure`, `MPSAccelerationStructureGroup`, `MPSInstanceAccelerationStructure`, `MPSRayIntersector` | `MPSPolygonAccelerationStructure` | 13.0, this file, the release-13 object |

The ray-intersection family is five rows and one block: `MPSTriangleAccelerationStructure` is the
only way to get geometry into an acceleration structure on this surface, so a structure with no
geometry and an intersector with nothing to trace would be four exported symbols no caller can
reach. The family is therefore carried or not at all, and this band carried none of it.

`MPSCNNYOLOLoss`, `MPSCNNYOLOLossDescriptor`, `MPSCNNNormalizationMeanAndVarianceState`,
`MPSRNNMatrixTrainingLayer`, `MPSRNNMatrixTrainingState`, `MPSNNPad` are the six rows whose
superclass the port DOES carry. They are `absent` because this band did not write them, and each row
says exactly that in its own words rather than claiming a blocker that does not exist.

## What was implemented

Two files, both release 12.0 by the measurement above, both built only from names the 16.4 headers
declare at `ios(12.0)`:

- `MPSNNOptimizers12.m` - `MPSNNOptimizerDescriptor`, `MPSNNOptimizer`,
  `MPSNNOptimizerStochasticGradientDescent`, `MPSNNOptimizerRMSProp`, `MPSNNOptimizerAdam`. The three
  update formulas are transcribed from `MPSNNOptimizers.h` line for line (`:250-268`, `:430-432`,
  `:436-438`), the gradient preprocessing is the header's own order at `:61-66` with the L1 and L2
  regularization gradients at `:33-41`, and every default is the number in the property's own doc.
- `MPSNNResize12.m` - `MPSNNResizeBilinear` and `MPSNNCropAndResizeBilinear`. The two sampling
  conventions are `alignCorners`'s own two sentences, and the regions are read as the header declares
  them: a `const MPSRegion *` of `{ MPSOrigin; MPSSize; }` doubles, normalised.
- `MPSMatrixCopyToImage12.m` - `MPSMatrixCopyToImage`, with the placement decided by `dataLayout` as
  `MPSImageCopy.h` declares the two layouts.

### What was NOT measured, stated plainly

**No build, no test program, no gate and no device ran in this band.** The shared `~/.xmake` store
was under repair and this band was forbidden to touch it, so nothing here has been compiled, linked
or compared with a result. Every rule above is transcribed from a header; not one number in it is a
measurement of Apple's code or of this port's. `tools/release-split.lua` was likewise not run: it
requires a folder of already-compiled `*.o` (`release-split.lua:150-151`, and its own header says so),
so its verdict is unknown to this band and has to be produced by whoever compiles next.

### Two things the first draft of these files got wrong, and the header that caught them

Both were caught by reading the SDK headers rather than by running anything, and both would have been
silently wrong:

- `MPSNNCropAndResizeBilinear`'s regions were first written as an `NSArray` of `NSValue`-held
  `CGRect`. `MPSNNResize.h:110` declares them as `@property (readonly, nonatomic, nonnull) const
  MPSRegion *regions` - a pointer to a C array of structs with double components
  (`MPSCoreTypes.h:321-338`, `:355-359`), normalised, not pixel rectangles in objects.
- `MPSNNResizeBilinear` and `MPSNNCropAndResizeBilinear` were first written against
  `MPSUnaryImageKernel`. `MPSNNResize.h:30` and `:99` derive both from `MPSCNNKernel`, and mark
  `-initWithDevice:` `NS_UNAVAILABLE` on each.

### A third, found by hand rather than by a header

The bilinear blend was first written as two successive blends - along x, then along y - which is what
a separable implementation does and is NOT what a single bilinear sample is. The intermediate
`at_y`-blended corners do not exist at the half-pixel position the second pass needs. It is one blend
of the four corners of the destination pixel's cell, weighted along both axes at once, and the code
says so where it is written.

## The selector row, and the rulebook's trap about selectors

`-[MPSCNNConvolutionDataSource copyWithZone:device:]` is `absent`, and the evidence is deliberately
NOT `first-rung.py`. That tool answers `9.0` for the bare selector, which is `NSObject`'s own
`copyWithZone:` and says nothing about this owner. What the row rests on instead is that no object in
`packages/a/apple-backports` defines `MPSCNNConvolutionDataSource` at all - a grep finds only this
registry file's own rows for it - so there is no `@implementation` that could carry the method.

## The rows this band deliberately did not touch

`MPSRNNDescriptor`, `MPSRNNRecurrentMatrixState`, `MPSCNNLoss`, `MPSCNNLossDescriptor`,
`MPSNNReduceUnary`, `MPSCNNBinaryKernel`, `MPSCNNArithmetic`, `MPSCNNGradientKernel`,
`MPSNNFilterNode`, `MPSNNGradientFilterNode` and `MPSPolygonAccelerationStructure` are named in the
rows above as the missing ancestors. Every one of them is a row in this same file or in
`registry/MetalPerformanceShaders/`, and NONE of them is one of the 47 rows this slice was given, so
none of them was edited. This band read them and wrote about them; it did not move their status.