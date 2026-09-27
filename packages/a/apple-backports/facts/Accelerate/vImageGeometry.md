# The geometry of vImage: what the family is, and what has to be measured first

The surface is **87 functions** in the corpus, and it is one engine behind them: every one of them is "for each
pixel of the destination, find the source position it comes from and sample there". The 87 differ in the
mapping, the resampling, the edging and the pixel type - and the family's first job is to settle all four,
because a guess about any of them is a wrong answer on every pixel rather than on one.

This page records what has been established and what has not. Nothing here is a plan; the code is not
written yet and this is the state a session starts from.

## The inventory, measured from the header and the corpus

`Geometry.h` declares 121 functions; the corpus asks for 70 of them, the other 51 being in the armv7 cache of
6.1.3 already. `Transform.h` adds three more the corpus asks for: `vImageGetPerspectiveWarp`,
`vImageGetResamplingFilterExtent` and `vImageCopyBuffer`. The 87 fall into five release bands, and one file per
band is what `tools/release-split.lua` wants:

| introduced | rows | what is in it |
| --- | --- | --- |
| 7.0 | 25 | `vImageScale_ARGB16U`, `vImageRotate_ARGB16U/ARGB16S`, `vImageRotate90_ARGB16U/ARGB16S`, `vImageHorizontalShear_ARGB16U/ARGB16S`, `vImageVerticalShear_ARGB16U/ARGB16S`, `vImageAffineWarp_ARGB16U/ARGB16S`, `vImageAffineWarpD_ARGB16U/ARGB16S`, `vImageAffineWarpCG_ARGB16U/ARGB16S` |
| 8.0 | 7 | the `Planar16U` and `Planar16S` shears and scales |
| 10.0 | 9 | the `CbCr16U` and `CbCr16S` shears and scales, and `CbCr8` |
| 15.0 | 21 | the half-precision shapes: `Planar16F`, `CbCr16F`, `ARGB16F` across scale, rotate, rotate90, shear, reflect, affine warp |
| 16.0 | 25 | the same plus `XRGB2101010W` and the `vImageInterpolationNearest` / `vImageInterpolationLinear` / `vImageUseFP16Accumulator` behaviour |

Twelve pixel types are involved: `ARGB16U` and `ARGB16S` (four channels, 16-bit), `Planar16U` and `Planar16S`
(one channel), `Planar16F`, `CbCr16F` and `ARGB16F` (half precision), `CbCr16U`, `CbCr16S` and `CbCr8` (two
channels), and `XRGB2101010W` (one 32-bit word, X:R:G:B ten bits each). Half precision needs a conversion
both ways, `XRGB2101010W` needs its own unpack and repack, and the two signed types need a clamp to
`int16_t` - none of which exists in the package yet.

## The three things that have to be measured before the engine can be written

**1. The resampling filter the shears take is an object, and it is a corpus row of its own.** The
`ResamplingFilter` parameter of all 24 shears is `void *`; `vImage_Types.h` says it "is created with
`vImageNewResamplingFilter` or `vImageNewResamplingFilterForFunctionUsingBuffer`" and holds "precalculated
filter coefficients". The corpus asks for `vImageNewResamplingFilterForFunctionUsingBuffer` and for
`vImageGetResamplingFilterExtent`, and both are in this family's scope. So the shears cannot be written
before the filter is: their whole resampling behaviour is a function of the filter the caller hands them,
and **a NULL filter crashes the host** (measured: `probe-map.m` dies with SIGSEGV on the first shear call
with `filter = 0`). What has to be settled is the layout the port gives its own filter - it is opaque, so
the port's - and what the default filter is when a caller makes one with a kernel of its own.

**2. The edging mode is not optional, and the header says the results are undefined without it.** Every
geometry function documents "Acceptable flags are `kvImageEdgeExtend`, `kvImageBackgroundColorFill`,
`kvImageDoNotTile`, `kvImageNoFlags`" and, for the shears, "Only one of `kvImageEdgeExtend` or
`kvImageBackgroundColorFill` may be used. If none is used then the edging mode is undefined and the results
may be unpredictable." Measured the hard way: `probe-map.m` calling `vImageScale_ARGB16U` with
`kvImageNoFlags` and a distinct value in every source pixel **also dies with SIGSEGV**. The engine therefore
has to answer for `kvImageEdgeExtend` and `kvImageBackgroundColorFill` and refuse, or define, the rest -
and which it does has to be the system's, measured.

**3. The coordinate convention of each mapping, which the header does not write out.** For the affine and
projective warps the transform is given and the inverse has to be built; for scale, rotate, shear, rotate90
and the two reflects vImage builds the mapping itself and does not publish it. The probe is written and
compiled - `probe-map.m` in this file's run directory, a 5x5 `ARGB16U` source with a distinct value in every
pixel, one call per operation, nearest interpolation, dumping the destination grid - and it is what settles
each of them. It does not run yet, because the flags and the filter are the two things above. The five
shapes it has to answer for, and the questions each raises:

| operation | the question |
| --- | --- |
| `vImageScale_*` | does a destination pixel's centre map to `(dx + 0.5) * srcWidth / destWidth - 0.5`, and which way round |
| `vImageRotate_ARGB16U` | the rotation is about which point, and is the angle clockwise or anticlockwise |
| `vImageRotate90_*` | which of the four `rotationConstant` values is which quarter turn, and is the destination transposed or rotated |
| `vImageHorizontalReflect_*` / `vImageVerticalReflect_*` | which axis each mirrors - the header's own names are the first thing to check against the system |
| `vImageAffineWarp*_*` | the matrix is applied forwards or inverted, and the CG variant's row-vector convention |

`vImageGetPerspectiveWarp` is the one mapping whose input is explicit - four source points to four
destination points, filling the ten coefficients of `vImage_PerpsectiveTransform` - and the header publishes
neither the solve nor the layout, so it is measured by feeding it point sets whose answer is known.

## What is not written

No geometry function is implemented. What exists is this page, `probe-map.m`, and the infrastructure the
family will share: the layout table and the per-pixel reference implementations in
`tests/backports/host/ypcbcr8` are the pattern to follow for a family differential, and `CharonYpCbCr.h` is
the pattern for a shared arithmetic header across several object files of one family.
