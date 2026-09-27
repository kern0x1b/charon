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

## What the probe has measured

`probe-map.m` now runs. The first version of it segfaulted on every function that takes a `backColor`,
because a `Pixel_ARGB_16U` parameter is an array and `0` for one decays to a **NULL pointer**, which the host
dereferences; and on the ones that need an edging mode, because the header is right that the results are
"unpredictable" without one. With a real black pixel and `kvImageBackgroundColorFill` the whole probe runs.
Over a 5x5 `ARGB16U` source whose every pixel carries a distinct value, with nearest-neighbour sampling
where that is available:

| call | the destination grid | what it says |
| --- | --- | --- |
| `vImageScale_ARGB16U` at equal sizes | the source, in order | a pixel maps to itself, and the scale factor is `src.width / dest.width` |
| `vImageHorizontalReflect_ARGB16U` | each row reversed | **mirrors left to right** |
| `vImageVerticalReflect_ARGB16U` | the rows in reverse order | **mirrors top to bottom** |
| `vImageRotate_ARGB16U` at 0 | the source, in order | the identity at 0 |
| `vImageRotate_ARGB16U` at pi/2 | interpolated, not nearest | the default interpolation is **linear**; `kvImageInterpolationNearest` is 0 and so cannot be the default, which is `kvImageInterpolationLinear` at 1 |
| `vImageAffineWarp_ARGB16U` with `{1,0,0,1,0,0}` | the source, in order | the struct is `{a, b, c, d, tx, ty}` and **its identity is `{1,0,0,1,0,0}`** - `{1,0,0,0,1,0}` is singular and answers the backColor everywhere |
| the same with `{1,0,0,1,2,0}` | the source moved two columns **left** | the matrix maps **destination to source**: `sx = a*dx + c*dy + tx`, so a positive `tx` pulls the source left |
| the same with `{0,1,-1,0,0,0}` | the backColor everywhere | a non-singular matrix that answers the backColor for all twenty-five pixels, which pins the system's convention and not the header's |
| `vImageAffineWarpD_ARGB16U` with the identity | the source, in order | the double-precision struct has the same six fields and the same identity |
| `vImageAffineWarpCG_ARGB16U` with a translation of 2 | the source moved two columns left | the CG variant agrees with the vImage one on a translation, and on the `{0,1,-1,0,0,0}` case |
| `vImageGetPerspectiveWarp` + `vImagePerspectiveWarp_ARGB16U`, four corners moved +2 in x | the source moved two columns left | the generator and the warp compose to the same destination-to-source mapping the affine case gives |
| `vImageRotate90_ARGB16U` with `rotationConstant` 0 | the source, in order | |
| with 1 | the source **transposed** - row 0 is the source's last column | 1 is a quarter turn |
| with 2 | `src(N-1-r, N-1-c)` | a half turn |
| with 3 | the same as 2 on a square | the four constants cannot be told apart on a square picture, so the mapping needs a non-square one before it can be written down |

**And the two that are still open.** The `rotationConstant` values need a picture that is not square - on a
5x5 the 90 and 270 degree cases give the same grid, so which of them is which is unmeasured. And the
`{0,1,-1,0,0,0}` case says the system's affine convention is not the one the header's field names suggest,
because a matrix of determinant 1 answers the backColor for every pixel of the destination; the port cannot
reproduce that from the header and has to be told the convention by a further measurement.

## What is not written

No geometry function is implemented. What exists is this page, `probe-map.m`, and the infrastructure the
family will share: the layout table and the per-pixel reference implementations in
`tests/backports/host/ypcbcr8` are the pattern to follow for a family differential, and `CharonYpCbCr.h` is
the pattern for a shared arithmetic header across several object files of one family.
