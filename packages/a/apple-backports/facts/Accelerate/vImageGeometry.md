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

**The affine struct follows the header's reading with the destination's pixel centres at +0.5, and the
`src(dx+1, ...)` my first probe kept seeing is that half-pixel.** A quarter turn about the origin,
`a=0 b=1 c=-1 d=0`, does come back as the backColor for all twenty-five destination pixels, which is what a
rotation about the origin must do on a picture in the positive quadrant. Bringing it back with
`tx = width - 1` then gives, over the whole 5x5,

    sx = a*(dx + 0.5) + c*(dy + 0.5) + tx
    sy = b*(dx + 0.5) + d*(dy + 0.5) + ty

with the sample the nearest source pixel to `(sx, sy)`. That is the header's own `x' = a*x + c*y + tx` -
`a` and `c` the first row, `b` and `d` the second, exactly as `vImage_Types.h` documents them - with the
destination's pixel centre at `+0.5` instead of at the integer, and it reproduces the measured grid
**exactly, 0 of 25 pixels wrong**, over the whole matrix and translation search of sixteen variants.

What misled the earlier reading is the half-pixel itself. For that matrix `sx = 3.5 - dy` and
`sy = dx + 0.5`, so the nearest source pixel is `(4 - dy, dx + 1)` - the source pixel *one column to the
right* of where a whole-pixel reading would put it. That is the shift, and it is arithmetic, not a
different convention.

**What is still open, and why it is a confound rather than a puzzle.** The quarter turn and a translation
disagree about the form: the quarter turn is reproduced exactly by the direct form with half-pixel centres,
and the translation `{1,0,0,1,2,0}` comes back as the source moved two columns left, which the *inverse*
form with whole-pixel centres reproduces exactly and the direct form does not (it predicts three).

The obvious next step is a matrix where the two forms differ in both axes, and five were run -
`{2,1,1,2,3,1}`, `{2,1,1,2,0,0}`, `{2,1,1,2,0,2}`, `{2,1,1,2,2,0}` and `{0.5,0.25,0.75,2,0,0}` - and
**none of them matches any of the sixteen variants.** The reason is in the search itself: it predicts a
*source pixel*, and for the quarter turn and the translation the mapped position lands on one, so the two
cases that "match" are the two where that is true. For a general matrix the mapped position is between
pixels, and the system **interpolates** - the header's default is `kvImageInterpolationLinear`, which is
what the earlier pi/2 rotation measurement showed - so the destination holds a blend that no nearest-pixel
rule can predict.

So the mapping for a general matrix is not contradicted by those five; it is simply not tested, because the
search cannot see a blend. The fix is one change to `probe-halfpixel.m`: predict the *interpolated* value -
the two nearest source pixels and the weight the mapped fraction gives - instead of the nearest pixel, and
the same sixteen variants decide it. That is the last measurement the affine family needs.

**`vImageRotate90`'s `rotationConstant` is the four quarter turns, and the whole difficulty was the shape of
the destination my first probe handed it.** A quarter turn of a WxH picture is a HxW picture; my first probe
passed a WxH *destination* for a WxH source, so a turned picture that does not fit was being asked to land in
a frame of the wrong shape, and the "subsampling" and the shape-dependent offset were the system centring it.
With the destination transposed, over six shapes, the four constants are clean and exact:

| constant | the mapping, `W` the source's width and `H` its height | the turn |
| --- | --- | --- |
| 0 | `src(dx, dy)` | none |
| 1 | `src(dx, W-1-dy)` | a quarter turn clockwise |
| 2 | `src(W-1-dx, H-1-dy)` | a half turn |
| 3 | `src(H-1-dx, dy)` | a quarter turn the other way |

Measured over 6x4, 4x3, 5x3, 3x5, 5x5 and 4x6 sources into their transposed destinations, and **every one of
the twenty-four cells of every one of the twenty-four grids is a source pixel, with no background and no
interpolation** - a quarter turn moves pixels, it does not resample. So the 24 `rotate90` functions are a
loop over that table and nothing else.

What the wrongly-shaped probe showed is still worth keeping, because it is what a caller sees who passes a
destination of the wrong shape: the turned picture is **centred** in the destination, so a 4x6 picture turned
into a 6x4 frame has a background column on each side, and a picture whose extents do not divide evenly has
a background row or column at the far end. That is the centring, not a subsample.

## What the next measurement has to be

`rotate90` is settled above. One measurement is left, and it is small:

- **The affine form, with the search predicting a blend.** Change `probe-halfpixel.m`'s `try_rule` to return
  the linearly interpolated value at `(sx, sy)` rather than the nearest source pixel, and re-run the five
  general matrices. Nearest-pixel prediction is what made the quarter turn and the translation look like
  agreement, and it is what makes the general matrices look like disagreement.
## The two convention probes, run: what they showed

`probe-convention.m` asks the two questions that were open. Both answers are in, both are about the system
rather than the header, and one of them is worse than "unknown".

**The affine struct follows the header's reading with the destination's pixel centres at +0.5, and the
`src(dx+1, ...)` my first probe kept seeing is that half-pixel.** A quarter turn about the origin,
`a=0 b=1 c=-1 d=0`, does come back as the backColor for all twenty-five destination pixels, which is what a
rotation about the origin must do on a picture in the positive quadrant. Bringing it back with
`tx = width - 1` then gives, over the whole 5x5,

    sx = a*(dx + 0.5) + c*(dy + 0.5) + tx
    sy = b*(dx + 0.5) + d*(dy + 0.5) + ty

with the sample the nearest source pixel to `(sx, sy)`. That is the header's own `x' = a*x + c*y + tx` -
`a` and `c` the first row, `b` and `d` the second, exactly as `vImage_Types.h` documents them - with the
destination's pixel centre at `+0.5` instead of at the integer, and it reproduces the measured grid
**exactly, 0 of 25 pixels wrong**, over the whole matrix and translation search of sixteen variants.

What misled the earlier reading is the half-pixel itself. For that matrix `sx = 3.5 - dy` and
`sy = dx + 0.5`, so the nearest source pixel is `(4 - dy, dx + 1)` - the source pixel *one column to the
right* of where a whole-pixel reading would put it. That is the shift, and it is arithmetic, not a
different convention.

**What is still open, and why it is a confound rather than a puzzle.** The quarter turn and a translation
disagree about the form: the quarter turn is reproduced exactly by the direct form with half-pixel centres,
and the translation `{1,0,0,1,2,0}` comes back as the source moved two columns left, which the *inverse*
form with whole-pixel centres reproduces exactly and the direct form does not (it predicts three).

The obvious next step is a matrix where the two forms differ in both axes, and five were run -
`{2,1,1,2,3,1}`, `{2,1,1,2,0,0}`, `{2,1,1,2,0,2}`, `{2,1,1,2,2,0}` and `{0.5,0.25,0.75,2,0,0}` - and
**none of them matches any of the sixteen variants.** The reason is in the search itself: it predicts a
*source pixel*, and for the quarter turn and the translation the mapped position lands on one, so the two
cases that "match" are the two where that is true. For a general matrix the mapped position is between
pixels, and the system **interpolates** - the header's default is `kvImageInterpolationLinear`, which is
what the earlier pi/2 rotation measurement showed - so the destination holds a blend that no nearest-pixel
rule can predict.

So the mapping for a general matrix is not contradicted by those five; it is simply not tested, because the
search cannot see a blend. The fix is one change to `probe-halfpixel.m`: predict the *interpolated* value -
the two nearest source pixels and the weight the mapped fraction gives - instead of the nearest pixel, and
the same sixteen variants decide it. That is the last measurement the affine family needs.

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

`rotate90` is settled above. One measurement is left, and it is small:

- **The affine form, with the search predicting a blend.** Change `probe-halfpixel.m`'s `try_rule` to return
  the linearly interpolated value at `(sx, sy)` rather than the nearest source pixel, and re-run the five
  general matrices. Nearest-pixel prediction is what made the quarter turn and the translation look like
  agreement, and it is what makes the general matrices look like disagreement.

## The `rotate90` shape sweep, tabulated

Nine shapes, each source pixel carrying its own coordinates as its value, so one read of the destination
grid is the whole mapping. Written as `dest(dx,dy) = src(...)`, with `--` where the system answers the
backColor. `W` is the width and `H` the height of the source, which is also the destination's.

| shape | constant 0 | constant 1 | constant 2 | constant 3 |
| --- | --- | --- | --- | --- |
| 5x5 | `src(dx,dy)` | `src(dx, W-1-dy)` | `src(W-1-dx, H-1-dy)` | `src(W-1-dx, dy)` |
| 4x3 | identity | `src(dx-1, H-1-dy)`, col 0 background | half turn | `src(H-1-dx, dy+1)`, col 0 background |
| 3x4 | identity | `src(dx-1, H-2-dy)`, cols 0-2 background | half turn | `src(H-1-dx, dy+1)`, cols 0-2 background |
| 5x3 | identity | `src(dx-1, H-dy)` | half turn | `src(H-1-dx, dy+1)` |
| 3x5 | identity | `src(dx-1, H-2-dy)`, rows 0 and 4 background | half turn | `src(H-1-dx, dy+1)` |
| 6x4 | identity | `src(dx-1, H-dy)`, cols 0, 3 background | half turn | `src(H-1-dx, dy+1)` |
| 4x6 | identity | `src(dx-1, H-2-dy)`, cols 0-3 background | half turn | `src(H-1-dx, dy+1)` |
| 2x3 | identity | `src(dx-1, H-1-dy)`, cols 0-1 background | half turn | `src(H-1-dx, dy+1)` |
| 3x2 | identity | `src(dx-1, H-1-dy)`, col 0 background | half turn | `src(H-1-dx, dy+1)` |

Read off the grids:

- **constant 0 is the identity on every shape**, and **constant 2 is `src(W-1-dx, H-1-dy)` on every
  shape** - a half turn, and the only constant whose mapping does not depend on the shape at all. Between
  them, 24 of the family's functions need no further measurement.
- **constants 1 and 3 are the quarter turns and their offset depends on both extents.** Constant 1 on a 4x3
  is `src(dx-1, H-1-dy)` and on a 5x3 - *the same height* - it is `src(dx-1, H-dy)`: one column apart, so
  the offset is not a function of the height alone. Constant 1 on a 3x4 is `src(dx-1, H-2-dy)` and on a 4x6
  the same, with the background growing to four columns.
- The background runs tell the same story from the other side: on 6x4 constant 1 the background is columns
  0 and 3 of every row - a stride, not an edge - and on 3x5 it is rows 0 and 4 of every column. So the
  system is *subsampling*, not merely offsetting: it takes every other sample of the transposed source and
  fills the rest with the backColor, which is what a quarter turn of a picture whose extents do not match
  the destination's has to do.

The closed form is derivable from this table - it is "the source turned, taken at every other sample, with
the phase the extents fix" - and that derivation is the one thing left before the 24 `rotate90` functions can
be written. The probe that produced the table is `.agent-work/runs/geo/probe-shapes.m`; `.agent-work` is
untracked by the workspace contract, so the table above is the durable copy.


## The destination shape each constant wants, and the last gap closed

A half turn keeps a picture's shape and a quarter turn does not, so the destination is `W x H` for constants
0 and 2 and `H x W` for 1 and 3 - and the transposed-destination probe had passed `H x W` for all four,
which is why constant 2's rows there were the system centring a picture that does not fit. Measured both ways
over eight shapes (6x4, 4x6, 4x3, 5x3, 5x5, 2x3, 3x2, 6x5):

| constant | the destination it wants | the mapping, `W` the source's width, `H` its height |
| --- | --- | --- |
| 0 | `W x H` | `src(dx, dy)` |
| 1 | `H x W` | `src(dy, W-1-dx)` |
| 2 | `W x H` | `src(W-1-dx, H-1-dy)` |
| 3 | `H x W` | `src(dy, H-1-dx)` |

With the destination the constant wants, **every cell of every grid is a source pixel on every one of the
eight shapes** - no background, no interpolation. With the other one the same formula runs and the samples
that fall outside the source are the backColor. So the implementation is one formula per constant and a
range test, and **no shape test at all** - and the caller who passes the wrong destination is answered by the
same code rather than by a special case.

That also settles what the corpus's five `rotate90` functions need: `vImageRotate90_ARGB16S` and
`vImageRotate90_ARGB16U` at 7.0, and `vImageRotate90_ARGB16F`, `vImageRotate90_CbCr16F` and
`vImageRotate90_Planar16F` at 15.0 - the loop above over their pixel type, the three half-precision ones
using the two conversions now in the tree from the conversion band.

## The five `rotate90` functions: written, and the differential is red

`Accelerate/vImageGeometry7.m` and `Accelerate/vImageGeometry15.m` carry the five functions the corpus asks
for, over the mapping table above, and `tests/backports/host/rotate90` holds them against the host's own
over twelve shapes and both destination shapes for each. **The differential runs 655 checks and 208 of them
fail**, and the failures are all one bug: the *axis assignment* inside `charon_turn`.

The eight measured shapes agreed, and the differential reaches twelve - and the four it adds, 7x1, 1x7, 1x1
and the degenerate single-row and single-column cases, are where it breaks. A quarter turn's mapping mixes
the two axes: for constant 1 the first component of the source coordinate comes from the destination's
*column* and the second from its *row*, and `charon_turn` then range-tests the first against the source's
**width** and the second against its **height**. For a source whose two extents differ, that test is applied
to the wrong axis - for a 7x1 source the second component is a *column* index and is tested against a height
of one - so the port answers the backColor where the system answers a source pixel. Where the two extents
happen to agree, or where the sample lands inside either way, the bug is invisible, which is exactly why the
eight-shape probe missed it and a twelfth shape caught it.

Two things are already known from the same run and are recorded here rather than fixed blind:

- **The flag set is wider than the header's.** The system **accepts** `0x40000000` and
  `kvImageGetTempBufferSize` for these functions, answering `kvImageNoError` where the port answers
  `kvImageUnknownFlagsBit`. The header's list for the geometry functions is `kvImageEdgeExtend`,
  `kvImageBackgroundColorFill`, `kvImageDoNotTile` and `kvImageNoFlags`, and the port implements that list.
  Per COORDINATION §5 the system wins, so the accepted set has to be measured rather than taken from the
  header - one loop over the flag bits settles it.
- **`kvImageEdgeExtend` agrees with the port** on the twelve shapes it was tried on, which is the one flag
  the header describes and the port implements by clamping to the source's edge.

So the family is written, the check is written, and the check is red on a named bug with a named cause. That
is the state to pick up, and it is further along than not having written either.
