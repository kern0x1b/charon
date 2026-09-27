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

## The two convention probes, run: what they showed

`probe-convention.m` asks the two questions that were open. Both answers are in, both are about the system
rather than the header, and one of them is worse than "unknown".

**The affine struct's field-to-matrix correspondence is still not settled, and the `tx = width - 1` case rules
out the reading the header suggests.** The header's `vImage_AffineTransform` documents `a` and `b` as "the top
left and top middle cell" and `c` and `d` as "the middle left and middle right cell", which is CG's
`x' = a*x + c*y + tx`. A quarter turn about the origin - `a=0 b=1 c=-1 d=0` - does come back as the backColor
for every one of the twenty-five destination pixels, which is what a rotation about the origin must do on a
picture in the positive quadrant: **measured, and it agrees.** Bringing it back with `tx = width - 1` does put
real pixels in the destination, so the translation is read - but the grid it produces is
`src(dx + 1, height - 1 - dy)`, a *reflection in y with a shift of one in x*, not the quarter turn the matrix
names. A second case, `a=0 b=1 c=1 d=0`, determinant -1, comes back as `src(width-1-dx, height-1-dy)`, a
*point* reflection, which is not the reflection the matrix names either. And a general invertible matrix,
`{1, 2, 3, 4, 0, 0}`, comes back with values in the tens of thousands, so the coefficients are being used at a
much larger scale than a 5x5 picture admits.

So the translation is read, the matrix's *effect* on the mapping is not the header's, and the three cases do
not reconcile with one convention of the six fields. A port cannot write these 24 functions from the header,
and guessing a convention would be wrong on every pixel of every one of them - worse than not writing them,
because it would look finished.

**`vImageRotate90_ARGB16U`'s `rotationConstant` is not a fixed mapping: it depends on the picture's shape.**
Over a 5x5 the four constants gave the identity, a transpose, a half turn, and a half turn again. Over a 4x3 -
the non-square case that tells 90 from 270 degrees apart - they give:

| constant | the destination grid over the 4x3 source `10 11 12 13 / 14 15 16 17 / 18 19 20 21` | the mapping |
| --- | --- | --- |
| 0 | the source | `src(dx, dy)` |
| 1 | background, `13 17 21 / 12 16 20 / 11 15 19` | `src(dx - 1, height - 1 - dy)` |
| 2 | `21 20 19 18 / 17 16 15 14 / 13 12 11 10` | `src(width-1-dx, height-1-dy)` |
| 3 | background, `18 14 10 / 19 15 11 / 20 16 12` | `src(height-1-dx, dy + 1)` |

The 90 and 270 degree cases are now told apart - 1 and 3 - and both are *reflections with a one-pixel
offset*, where a quarter turn is a transpose with a flip. On the 5x5 the same constant 1 gave
`src(dx, width-1-dy)` with **no** offset and the whole first column real; here it gives a one-pixel offset and
the whole first column background. **The same constant maps differently for a 5x5 and a 4x3**, so the mapping
is a function of both dimensions and not of the constant alone, and the 5x5 reading - the only one a small
probe gives - is misleading about every other shape.

That is worth more than the six functions it costs: twenty-four `rotate90` functions written on the
square-only reading would be wrong on every non-square picture, which is most pictures.

## What the next measurement has to be

Both remaining questions are about *where the turned or warped image is placed*, and both are answerable:

1. **`rotate90` at several shapes.** The same four constants over 4x3, 3x4, 5x3, 3x5, 6x4 and 4x6, and the
   offset read off each. The rule will be "the destination holds the source turned, placed so that the turned
   picture's origin is at <rule>", and the shapes give the rule. What is already excluded: any rule that
   depends on the constant alone.
2. **The affine struct's convention.** The same matrix `{0,1,-1,0,tx,ty}` over several `tx` and `ty` on a
   picture with distinct values, and the destination-to-source pairs read off directly - one probe producing a
   table of `(tx, ty) -> (sx, sy)` from which the field order follows. `probe-convention.m` already prints
   everything needed for that; it needs more cases, not new code.
## The two convention probes, run: what they showed

`probe-convention.m` asks the two questions that were open. Both answers are in, both are about the system
rather than the header, and one of them is worse than "unknown".

**The affine struct's field-to-matrix correspondence is still not settled, and the `tx = width - 1` case rules
out the reading the header suggests.** The header's `vImage_AffineTransform` documents `a` and `b` as "the top
left and top middle cell" and `c` and `d` as "the middle left and middle right cell", which is CG's
`x' = a*x + c*y + tx`. A quarter turn about the origin - `a=0 b=1 c=-1 d=0` - does come back as the backColor
for every one of the twenty-five destination pixels, which is what a rotation about the origin must do on a
picture in the positive quadrant: **measured, and it agrees.** Bringing it back with `tx = width - 1` does put
real pixels in the destination, so the translation is read - but the grid it produces is
`src(dx + 1, height - 1 - dy)`, a *reflection in y with a shift of one in x*, not the quarter turn the matrix
names. A second case, `a=0 b=1 c=1 d=0`, determinant -1, comes back as `src(width-1-dx, height-1-dy)`, a
*point* reflection, which is not the reflection the matrix names either. And a general invertible matrix,
`{1, 2, 3, 4, 0, 0}`, comes back with values in the tens of thousands, so the coefficients are being used at a
much larger scale than a 5x5 picture admits.

So the translation is read, the matrix's *effect* on the mapping is not the header's, and the three cases do
not reconcile with one convention of the six fields. A port cannot write these 24 functions from the header,
and guessing a convention would be wrong on every pixel of every one of them - worse than not writing them,
because it would look finished.

**`vImageRotate90_ARGB16U`'s `rotationConstant` is not a fixed mapping: it depends on the picture's shape.**
Over a 5x5 the four constants gave the identity, a transpose, a half turn, and a half turn again. Over a 4x3 -
the non-square case that tells 90 from 270 degrees apart - they give:

| constant | the destination grid over the 4x3 source `10 11 12 13 / 14 15 16 17 / 18 19 20 21` | the mapping |
| --- | --- | --- |
| 0 | the source | `src(dx, dy)` |
| 1 | background, `13 17 21 / 12 16 20 / 11 15 19` | `src(dx - 1, height - 1 - dy)` |
| 2 | `21 20 19 18 / 17 16 15 14 / 13 12 11 10` | `src(width-1-dx, height-1-dy)` |
| 3 | background, `18 14 10 / 19 15 11 / 20 16 12` | `src(height-1-dx, dy + 1)` |

The 90 and 270 degree cases are now told apart - 1 and 3 - and both are *reflections with a one-pixel
offset*, where a quarter turn is a transpose with a flip. On the 5x5 the same constant 1 gave
`src(dx, width-1-dy)` with **no** offset and the whole first column real; here it gives a one-pixel offset and
the whole first column background. **The same constant maps differently for a 5x5 and a 4x3**, so the mapping
is a function of both dimensions and not of the constant alone, and the 5x5 reading - the only one a small
probe gives - is misleading about every other shape.

That is worth more than the six functions it costs: twenty-four `rotate90` functions written on the
square-only reading would be wrong on every non-square picture, which is most pictures.

## What the next measurement has to be

Both remaining questions are about *where the turned or warped image is placed*, and both are answerable:

1. **`rotate90` at several shapes.** The same four constants over 4x3, 3x4, 5x3, 3x5, 6x4 and 4x6, and the
   offset read off each. The rule will be "the destination holds the source turned, placed so that the turned
   picture's origin is at <rule>", and the shapes give the rule. What is already excluded: any rule that
   depends on the constant alone.
2. **The affine struct's convention.** The same matrix `{0,1,-1,0,tx,ty}` over several `tx` and `ty` on a
   picture with distinct values, and the destination-to-source pairs read off directly - one probe producing a
   table of `(tx, ty) -> (sx, sy)` from which the field order follows. `probe-convention.m` already prints
   everything needed for that; it needs more cases, not new code.
