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

## The five `rotate90` functions: written, and green

`Accelerate/vImageGeometry7.m` and `Accelerate/vImageGeometry15.m` carry the five functions the corpus asks
for - `vImageRotate90_ARGB16U` and `vImageRotate90_ARGB16S` at 7.0, and `vImageRotate90_ARGB16F`,
`vImageRotate90_CbCr16F` and `vImageRotate90_Planar16F` at 15.0 - over the mapping table above, and
`tests/backports/host/rotate90` holds them against the host's own over **twelve shapes and both destination
shapes for each**. The run is **656 checks, 0 failures**, and every sample of every one of them is equal:
a quarter turn is a copy, so there is no rounding to allow.

Four things the differential found on the way there, each measured and each in the source now:

- **The axis.** A quarter turn's mapping mixes the two axes - for constant 1 the destination's column becomes
  the source's *row* - and the coordinate has to be built in the source's own (row, column) and range-tested
  there. Built in (x, y) and tested against the width, it is wrong whenever the two extents differ. 208 to 132.
- **The flags.** There is no flag check. Every one of the thirty-two bits, passed on its own to
  `vImageRotate90_ARGB16U`, comes back `kvImageNoError` from the system, `0x40000000` and
  `kvImageGetTempBufferSize` among them; the header lists four and the system refuses none, so per
  COORDINATION section 5 the port refuses none either. 132 to 60.
- **The mismatched destination is the turned picture placed at an offset**, with whatever falls outside the
  frame the backColor - not centred in the sense of "the middle", but at `(destination - turned) / 2`. 60 to 0
  once the half is rounded the right way.
- **The half rounds UP.** Neither C's truncation toward zero nor a floor is the rule. A 2x3 source into a 2x3
  destination under constant 1 is a turned picture three wide by two tall in a two-by-three frame, and the
  system puts it at offset (0, 1) - half a pixel *down*. A 6x5 into a 6x5 under constant 1 is a turned 5x6 in
  a six-by-five frame and the system puts it at (1, 0) - half a pixel *across*. Both are
  `(destination - turned) / 2` rounded to the nearer integer with a half going up. The twenty mismatched
  shapes are what fix the direction: truncating fails every shape whose two extents differ by an odd number
  and passes every one whose difference is even, which is the signature of exactly this half.

`kvImageEdgeExtend` agrees with the port on all twelve shapes: it is the header's own "the edge pixels of
the source are extended", and the turned picture is pulled back inside the frame rather than back-coloured.

So the family is five functions, one loop and a table, and a check that says so.

## The resampling filter, and what the shears need from it

`ResamplingFilter` is a `void *` and opaque, and `vImage_Types.h` says it "holds precalculated filter
coefficients for a resampling filter, such as a Lanczos or Gaussian resampling filter". So the port's filter
object is its own layout, and what it has to hold is a **scale** and the kernel that scale implies - there
is nothing else a caller can put in one, since the only two constructors take a scale (or a scale and a
function of the caller's) and nothing reads the bytes.

**What `vImageNewResamplingFilter(scale, flags)` answers, measured over thirteen scales from 0.25 to 2.0:**
a filter is made for every positive scale, and `vImageGetResamplingFilterExtent` on it is

| scale | 0.25 | 0.5 | 0.75 | 1.0 | 1.25 | 1.5 | 1.75 | 2.0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| extent | 12 | 6 | 4 | 3 | 3 | 3 | 3 | 3 |

so the kernel's support is **at least three pixels at every scale**, it grows as the scale shrinks, and it
stops growing at three from a scale of one upwards. That is a real, publishable measurement and it is what
the port's `vImageGetResamplingFilterExtent` has to answer.

**What the shears do with one**, over a 5x5 `ARGB16U` source with a distinct value in every pixel and a
backColor of zero:

- a filter of scale 1.0 with `xTranslate` 0 and `shearSlope` 0 is an **exact copy**, so a unit-scale filter is
  a kernel that does not move anything;
- `xTranslate` of 1 shifts the source **one column left** and leaves the vacated column as the backColor, so
  the shear is **destination to source** like the affine, and a positive translate pulls the source left;
- `shearSlope` of 1 answers **interpolated** values - 5, 7, 17, 10, 23, 12, 28, 15, 34, 31, 37, none of which
  is a source value - so a shear resamples linearly, and a filter of scale 2.0 or 0.5 with no slope at all
  resamples too;
- `vImageVerticalShear_ARGB16U` behaves the same way with the axes the other way round.

**So the shears need the kernel's coefficients, and that is the next measurement.** They are not published:
the header says the filter holds "precalculated filter coefficients" and nothing about what they are, and
they are a function of both the scale and the fractional part of the mapped position. Reading them off is
straightforward now that the convention is known - the shear is destination to source, a unit-scale filter
with no slope is an exact copy, and the interpolated answers above are the kernel's weights showing through.
For a shear of slope 0 the mapped position is exactly a source pixel, so a filter of scale *s* and a
destination of a different width puts the kernel's weights on the table directly, and sweeping the scale in
steps of 1/N and the translate through a whole pixel gives the whole kernel at that scale. From the extent
table the kernel is at least three taps wide, so the sweep has to read three at a time.

Until that is measured the port cannot answer a shear that rescales or shears, and a port that answered one
with the header's "faithfully rounded" arithmetic and a guessed kernel would be wrong on every pixel of every
shear - the same trap the ten-bit Y'CbCr path was. What the port *can* answer today, and has measured, is
the exact-copy case: a unit-scale filter with no slope and no translate, which is what the twenty-four
`rotate90`-style measurements reduce to.

## The kernel sweep: the weights are measured, and they are not a normalised Lanczos

One source row, one pixel at a time set to full scale and every other pixel zero, so the destination *is*
that pixel's weight; the pixel's position, the filter's scale and the shear's `xTranslate` swept. The whole
table is in `.agent-work/runs/geo/kernel-weights.txt`, and the probe that builds it is
`probe-kernel.m`.

At **scale 1.0**, where the reported extent is 3, and a shear of slope zero:

| xTranslate | the non-zero weights, in tap order |
| --- | --- |
| 0.00 | `1.0000` |
| 0.25 | `0.0301  0.2710  0.8927` |
| 0.50 | `0.0244  0.6114` |
| 0.75 | `0.0074  0.2710  0.8927` |
| 1.00 | `1.0000` |

**These do not sum to one and they are not symmetric, so they are not `sinc(x)*sinc(x/a)` normalised per
phase**, which is what a Lanczos3 fit would have to produce: at u = 0.5 a normalised Lanczos3 is symmetric
about the sample, and the measured pair is 0.0244 against 0.6114. They sum to 1.1938, 0.6358, 1.2012 and
1.0000. So either the shear contributes something of its own beyond the kernel - and it does have a
`shearSlope` and a per-axis scale, either of which could - or the kernel is not Lanczos.

That is a real finding and it is checkable rather than arguable, because the whole point of sweeping with a
**slope of zero** was to make the mapped position land exactly on a source pixel, so the weights would be the
kernel's alone. They are not, so the sweep has not separated the kernel from the shear yet. The next
measurement is the one that does: **hold the filter's scale at 1 and vary only `xTranslate` in steps of 1/64
rather than 1/4**, so the phase curve is dense enough to fit and a second sine is distinguishable from a
first; and **sweep `shearSlope` as well**, since a slope of zero and a slope of one with the same translate
differ by the shear's own contribution alone.

The two published facts fit what has been measured and no more: the default kernel is Lanczos3 and Lanczos5
under `kvImageHighQualityResampling`, and the support is scaled by 1/scale when downsampling. The extents are
exactly that - 12, 6, 4, 3 for scales 0.25, 0.5, 0.75, 1.0, and constant at 3 from a scale of one upwards -
so the support and the two constructors are settled and publishable. The coefficient curve is not, and until
it is, a port that answered a rescaling shear would be guessing.

## The kernel on a float shear: the clipping explanation confirmed

The `ARGB16U` sweep was clipped and that is why its weights neither summed to one nor stayed symmetric:
`ARGB16U` is **unsigned**, so every negative lobe of the kernel clamped to zero and the rest saturated.
Redone on `vImageHorizontalShear_PlanarF` - a float channel, nothing to clamp - with a background of 0.5 and
a delta of 1.0, so a negative weight shows as a value *below* 0.5, the answers are completely different:

| xTranslate | the `ARGB16U` weights, clipped | the `PlanarF` weights |
| --- | --- | --- |
| 0.125 | - | `0.97265  0.12065  -0.03060  0.00184` |
| 0.250 | - | `0.27101  -0.06800  0.00738` |
| 0.500 | `0.0244  0.6114` | `0.61141  -0.13587  0.02446` |

They are **symmetric about the sample, carry the negative lobes, and sum to exactly 1.000000** - which is
what a normalised interpolation kernel is and is what the integer sweep could not show. So the clipping
diagnosis is right, and the integer types' weights in the first table are the float kernel's weights after
clamping and saturating, not the kernel.

Two runs give the sum and each weight without assuming normalisation: every pixel at the background `B`
gives `dest0 = B * sum(w)`, and one pixel at `D` with the rest at `B` gives
`dest_p = B * sum(w) + (D - B) * w_p`, so `w_p = (dest_p - dest0) / (D - B)`. Both are in
`probe-kernelf.m`, and the raw answers are in `kernel-float.txt`.

**The identification is Lanczos3, and the numbers settle it.** Pairing each measured weight with its
*distance* from the mapped position rather than with a tap index, and comparing against
`sinc(x)*sinc(x/3)`:

| phase | measured | unnormalised Lanczos3 | ratio |
| --- | --- | --- | --- |
| 0.125 | `0.97265  0.12065  -0.03060  0.00184` | `0.97171  0.12053  -0.03057  0.00184` | 1.0009 |
| 0.250 | `0.27101  -0.06800  0.00738` | `0.27019  -0.06779  0.00736` | 1.0030 |
| 0.500 | `0.61141  -0.13587  0.02446` | `0.60793  -0.13509  0.02432` | 1.0057 |

The values track `sinc(x)*sinc(x/3)` at the right distances to within a third of a per cent at every phase,
with the sign pattern and the lobes right, so the kernel is Lanczos3 and `a = 3`. `a = 5` does not fit: its
lobes at these distances are -0.0335, +0.0811 and -0.1822 at phase 0.5, where the measurement is +0.6114,
-0.1359 and +0.0245, so the support of five is not what is being used and the high-quality kernel is a
different object, selected by `kvImageHighQualityResampling`.

**One residual is not yet closed, and it is in the normalisation.** Every measured weight is a little larger
than the unnormalised lobe and by an amount that grows with the phase - 1.0009 at 0.125, 1.0030 at 0.250,
1.0057 at 0.500 - so it is a per-phase factor and not one constant, and the sweep's own sum of the weights
came out at exactly 1.000000. Both cannot be true of the same weights, and the resolution is almost certainly
that a tap outside the swept range carries a small weight: the sweep covered `extent * 2 + 2` taps and the
support is three, so the largest weight at phases 0.125 and 0.250 fell at tap 8 and was never measured - which
is the same off-by-one the earlier printout showed. Sweeping a few taps further would close it.

So the kernel is **specified** rather than guessed: a scale, `a = 3` by default and `a = 5` under
`kvImageHighQualityResampling`, a support of `a / min(1, scale)` - which is what the extent table measures,
12, 6, 4, 3 and constant at 3 above a scale of one - and the weights `sinc(x)*sinc(x/a)` at the tap
distances, normalised per phase. The float sweep is what shows the lobes; the extent table is what shows the
support rule; and the third digit of the phase table is the residual.

So the family has what it needs to write the filter object and the twenty-four shears: the scale and `a` and
the support rule and the per-phase normalised weights, each with a measurement behind it.



## The filter is a caller-allocated buffer, and that is what unblocks the shears

I was about to record the shears as blocked on "the filter object belongs to the release and its layout is
unpublished", and the header says otherwise. `Geometry.h` on
`vImageNewResamplingFilterForFunctionUsingBuffer`:

> This function writes the kernel values into a preallocated kernel buffer that you provide. This function
> writes the kernel values into a preallocated kernel buffer that you provide. The kernel buffer should be at
> least the size of the kernel data, which is given by `vImageGetResamplingKernelSize`.

and on the other two:

> `vImageNewResamplingFilter` and `vImageDestroyResamplingFilter` are **merely convenience functions** to
> make the common case of the default resampling filter into a heap allocated buffer easier for you.

So a `ResamplingFilter` is **not an opaque object the port has to invent a peer for**. It is a buffer **the
caller allocates**, whose size `vImageGetResamplingFilterSize` reports, and which the release's own
constructor - `vImageNewResamplingFilterForFunctionUsingBuffer`, at **iOS 5.0**, so present in 6.1.3 - fills
with the kernel's values by evaluating a caller-supplied `y = f(x)`. The kernel function's own signature is
published: `void (*)(const float *xArray, float *yArray, unsigned long count, void *userData)`.

That changes the shears from blocked to measurable. A caller's filter is a buffer of kernel values the
release wrote, and what the port needs to read it is **the arrangement of those values in the buffer** -
which is a host measurement, not a reverse-engineering project: construct a filter of a known scale on the
host, dump the buffer, and the arrangement is the pattern in the bytes. `vImageGetResamplingFilterSize(scale,
flags)` gives the length to expect, so the measurement is self-checking: the bytes that vary with the scale
are the kernel, and the ones that do not are the header.

It also means the kernel the port evaluates and the kernel the release evaluated are the *same function* -
whatever `sinc(x)*sinc(x/3)` is doing, the release evaluated it and wrote the result down - so the port does
not have to reproduce the release's arithmetic to agree with it. It has to read the numbers the release
wrote. That is a much smaller and more robust thing to get right, and it is why the residual in the phase
table stops mattering: the port can take the weights from the filter rather than compute them.

So the shears' engine is: take the filter's buffer, read its scale and its per-phase weights, and resample
with them; and the one measurement left is the buffer's arrangement. The twenty-four functions the corpus
wants for the four shear spellings and the eleven pixel types, and the one `vImageGetResamplingFilterExtent`
that has to read the same buffer, all follow from it.

## The shear's mapping, read off a PlanarF grid - and the half pixel

A horizontal shear has **no cross-axis term**: every destination row reads the *same* source row, and the row
index only shifts the x offset. That is the correction, and it is right - what I had written multiplied the
slope into a row index, which is not a shear at all.

A source carrying `row * 1000 + column` in each value, so a destination pixel's answer names the source row
and column it read, over an 8x4 with a scale-1 filter and `kvImageBackgroundColorFill`:

| case | the destination row 0 reads |
| --- | --- |
| slope 0, translate 0 | `--  0,1  0,2  0,3  0,4  0,5  0,6  0,7` |
| slope 0, translate 1 | `--  --  0,1  0,2  0,3  0,4  0,5  0,6` |
| slope 0, translate -1 | `0,1  0,2  0,3  0,4  0,5  0,6  0,7  --` |

So **a positive translate pulls the source left**, `sx = dx - xTranslate`, the same direction the affine's
`tx` pulls left and the opposite of the reading a caller might expect from the name.

**The half pixel is NOT there, and the last commit's claim about it was an artefact of this probe.** With the
`+ 1` in the value - so that no source value is zero and a genuine read of source column 0 cannot be mistaken
for the backColor - a slope of 0 and a translate of 0 reads

    dy=0   0,0  0,1  0,2  0,3  0,4  0,5  0,6  0,7
    dy=1   1,0  1,1  1,2  1,3  1,4  1,5  1,6  1,7

with **no backColor anywhere**, so the mapped position of `dx = 0` is the source's first column and not half a
pixel to its left. The `--` this probe printed at that pixel before was the source value 0 being read and
scored as background. `sx = dx - xTranslate`, `sy = dy`, and the suggested form's `+ 1/2 ... - 1/2` is not what
the system does - which is worth having measured, because the form is a plausible thing to have implemented
and it would be wrong on every pixel of every shear.

**The slope term is not read off, and the reason is a flaw in this probe, not in the system.** The probe
writes a source value of `0` for row 0 column 0 and prints anything at or below 0.6 as `--`, so a genuine
read of source column 0 is indistinguishable from the backColor. Every row above is a case where the values
involved are large enough to be unambiguous, and the slope rows are full of 0s and near-0s and are therefore
**not trustworthy as they stand**. One rerun with the value `row * 1000 + column + 1`, so no source value is
zero, reads the slope term off: with slope 1 the destination column's source column is offset by a whole
column per row, and the sign and the half pixel follow from the same three cases the table above is read
with.

The vertical shear is the transpose of that, on the same evidence.

## The shears: written, and the differential is red on the edge

Thirty-six functions over four bands - 8 at 7.0, 4 at 8.0, 6 at 10.0, 18 at 15.0 - and
`tests/backports/host/shear` holds the engine against the host's own
`vImageHorizontalShear_PlanarF` and `vImageVerticalShear_PlanarF` over four filter scales, six translates and
both edging modes. PlanarF is the vehicle and not a delivered function: it is in 6.1.3 already and the corpus
does not carry it, so what is compared is the port's engine over a float channel against the system's.

**Red, and the failures are one case.** They are all the **first sample of a row where the kernel overhangs
the left edge**, and all of them differ by exactly the gap between the backColor and the source value - 2.25
on a channel whose range is −2 to +2 with a backColor of 0.25 - which is the signature of the port writing
the backColor where the system writes a source pixel.

An earlier version of the loop discarded the whole sample the moment any tap fell outside the source. That
is wrong, and the system says so: at an integer mapped position the out-of-range lobes of a Lanczos kernel
are *exactly zero*, so the destination's first column is the source's first column. The loop now skips an
out-of-range tap and keeps the inside ones, and takes the backColor only when **no** tap is inside. That is
the correct rule and it is what the header's "the edge pixels of the source are extended" describes for
`kvImageEdgeExtend`, where the tap is pulled back to the edge pixel instead of dropped.

The remaining failures are the same case in a different guise, and the loop as committed still gets it wrong
for at least the destination-wider-than-source and downscale cases. One defect, named: the interaction of
`first = base - extent` with a destination that is wider than the source, where the kernel runs off the
**right** edge and the sample is taken from taps that are all inside but sum to less than one - and the
system renormalises over the inside taps where this port does not. That is the measurement the next run
settles: a source narrower than the destination, and the weights of the surviving taps divided by their sum.

**The 36 registry entries are NOT in the delivery.** While the differential is red, `status: implemented`
would be the fake the brief forbids, so `ios7-15-shear.json` is removed: the functions are in the tree as the
engine the remaining work is one rewrite deep, and nothing claims them. They come back with their entries when
the differential is green.

**The tap walk is now the diagonal one** - `(x + k, dy + shearSlope * k)` - and the slope is no longer
refused. That is the rewrite the characterisation called for, and it is why the run's remaining failures
moved from whole-sample differences to fractional ones concentrated at the bottom rows, where the diagonal
runs off the picture and the two answers disagree about which taps to drop. The next thing to settle is that
edge: the system at a steep slope and a destination near the last row blends the *last* row repeatedly where
this port drops the taps that fall past it.

## The slope term is a DIAGONAL resample, and that is the whole of it

A source ramped on **both** axes - every value is `row * 1000 + column + 1` - so every whole-pixel answer
names the `(row, column)` it read. Over a 9x6 picture into 9x6, a scale-1 filter and
`kvImageBackgroundColorFill`:

- **every whole-pixel answer reads the source row that equals the destination row.** At a slope of 1, of 2, of
  0.5 and of -1, the row named is `dy` in every case where the answer is a whole pixel. So the
  "cross-axis term" is not in the mapping - your correction was right about that, and the cross-row values
  are the *kernel* reaching across rows, not the mapping moving.
- **the column the whole-pixel answers name is irregular in the row.** At a slope of 1 the offsets read 5, 3,
  3, 2, 1, 0 down the six rows; at a slope of 2 they are larger and the top rows are entirely backColor; at
  0.5 they are 1, 1, 1, 1, 1, 1 with a blend at the left. A constant step per row would be 1, 2, 3, 4, 5 and
  it is not that.
- **between the whole-pixel answers the values are blends of two rows** - an answer near 500 is half of a
  row-1 value and half of a row-0 value, one near 300 of a row-2 and a row-3. So the kernel reads along a
  **diagonal**: a tap one step along the shear is one column across *and* `shearSlope` rows down, so at a
  slope of 1 the taps of one destination pixel land in three different rows and the sample is a blend of all
  of them.

That is the characterisation, and it is a different engine from the one committed: a shear is a one-
dimensional resample **along the direction of the shear**, with the taps at
`(x + k, dy + shearSlope * k)` rather than along a row. The slope-0 case the port ships is that engine with
the slope zero, where the taps stay in the row - which is why it is exact there and why the whole-pixel answers
at a non-zero slope are irregular: the port's row-taps are not the system's diagonal taps.

So the three items are: the left edge and the renormalisation over the surviving taps, both one-dimensional and
both in the committed loop, and the slope, which needs the tap walk to become `(x + k, dy + slope * k)`. The
first two are arithmetic in what is committed; the third is the loop's tap geometry.

## The bottom edge: the system reads past the picture, and that is the blocker

Every source **row** carrying one constant, `row * 1000 + 1`, so an answer reads back as
`1000 * (the weighted mean row the taps landed on) + 1`, and with the weights summing to one the mean row
names exactly which rows the kernel read. A 9x6 picture, a scale-1 filter, `kvImageBackgroundColorFill`, at a
slope of 1, the mean source row at each destination column:

    dy=0   --  --  -- -0.000  -- -0.000  0.000 -0.000 -0.000
    dy=1   --  --  0.024  --  0.500  1.111  0.976  1.000  1.000
    dy=2   --  0.048  --  1.000  2.223  1.951  2.000  2.000  2.000
    dy=3   0.073  --  1.500  3.334  2.927  3.000  3.000  3.000  3.000
    dy=4   --  2.000  4.446  3.902  4.000  4.000  4.000  4.000  3.902
    dy=5   2.500  5.557  4.878  5.000  5.000  5.000  5.000  4.878  5.557

The last row is the answer. Its mean row is **5.557** at two columns and **4.878** at two more - and a mean row
*greater* than 5 cannot come from rows 0 to 5, whatever the weights are, because the largest value in the
source is 5001. `0.557` is `(1 - 0.443) * 6 + 0.443 * 5`, so a tap read **row 6**, which does not exist. The
same holds at a slope of 2, where `dy=5` reads a mean of 5.000 at every column but the top rows are entirely
backColor, and at a slope of -1 the mirror at the top.

So the system does **not** drop, clamp or back-colour a diagonal tap that leaves the picture along the shear: it
reads it. That answers the three-way question, and it is a blocker rather than a rule, because the tap's address
is outside the caller's `vImage_Buffer`. A port that reproduced the answers would have to read past the buffer
the caller handed it - which is a wild read dressed as a conversion, and the one thing this family has refused
four times now. The three candidates are therefore all wrong, and the fourth possibility - that the system
reads past because the caller's buffer happened to have more behind it - is not something a port may rely on.

**What follows.** The shears are right where the diagonal stays inside the picture, which is most of a shear and
all of every slope-0 case the port ships. At the edge they are not, and the honest answer there is to refuse the
call rather than to read past the caller's buffer - which is a narrower refusal than the one the last two
commits carried, because it is only the picture's last few rows or columns at a non-zero slope. The
`kvImageBackgroundColorFill` mode is where it shows, because that is the mode whose name promises the edge is
filled rather than read.

So: the 36 functions stay **out** of the registry, and what is left is one decision - refuse the edge, or
reproduce a wild read - and a coordinator's ruling on which. Everything upstream of it is measured and written.

## The guard page settles what the system is doing, and the documented edging does not fit

**The proof, first.** The picture's last row placed flush against a `PROT_NONE` guard page - two pages mapped,
the second protected, the six rows of a 9x6 picture ending exactly at the boundary - and the system's own
`vImageHorizontalShear_PlanarF` run at the edge, under `SIGSEGV`/`SIGBUS` handlers that catch a read:

    slope 0  no fault, the largest value written is 5001
    slope 1  no fault, the largest value written is 5558
    slope 2  no fault, the largest value written is 5001
    slope 3  no fault, the largest value written is 5558

**No fault at any slope**, so the system reads nothing outside the allocation: it is not an out-of-bounds
read, and my harness was not under-allocating. And it writes **5558** where the largest value in a six-row
source is 5001 - a value **no convex combination of the source can produce**, so the weights it uses at the
edge do not sum to one.

What does produce it is **clamping the out-of-picture tap to the edge row and not renormalising over the
survivors**, so the edge row is counted twice. And that is the header's own `kvImageEdgeExtend` - the ruling's
step 2, implemented.

**And it does not fit, which is the result worth having.** With the clamp applied at both edges, the
*diagonal* cases match the system's fingerprint and the *in-row* cases break: at a translate of 1 the first
column now differs by 3.83, and a translate of -1 by 3.83 again, where the system plainly drops the
out-of-range taps - at a whole-pixel phase their Lanczos lobes are exactly zero, so the destination's first
column **is** the source's first column, and the port's earlier measurement said so over an 8x4 grid. The run
goes to a worst difference of 3.8 on cases that were exact before the change.

So the two edges are **not the same rule**: along the row the system drops the out-of-range taps, and along
the shear direction it clamps them without renormalising. The header documents one of those behaviours and
names one flag for it, and the system does the other thing as well. That is the state:

- the shears are exact for slope 0, in the whole picture, and that is the path the port ships;
- the diagonal edge is characterised down to the fingerprint that distinguishes clamping from dropping, and
  the port implements dropping, which is what the in-row edge measures;
- the 36 registry entries stay **out**, because the diagonal edge is not yet matched.

What is left is to find which taps the system clamps and which it drops - the two rules cannot both be right
and one measurement separates them: a picture where the *last* row is a ramp and the *first* column is a
constant, so the row edge and the column edge have different values and a single destination pixel's answer
says which was treated how.

## Both edges CLAMP: the two-edge grid derives the rule

A source whose **interior** is a known ramp in both axes, whose **first column** carries `9000 + row*1000`
and whose **last row** carries `50000 + column` - both wildly unlike their neighbours, so a destination
pixel near one edge and far from the other says which rule was applied to it. Measured over slopes 0 to 3 and
translates of +0.5 and −0.5, and the answer is the same at every slope:

- **a left-edge destination pixel reads column 0's own value.** At a slope of 0 and a translate of 0.5, row 0
  column 0 answers **5491.0**, and the measured half-pixel weights predict `0.61141 * 9000 + 0.02446 * 101 =
  5501.5` - the edge element read at both the centre and the clamped neighbour. At a slope of 1 the same pixel
  answers **9000.0** exactly, column 0's value.
- **a bottom-edge destination pixel reads the last row's own value**, and the answer **overshoots the source
  maximum**: at a slope of 0, row 5 column 8 answers **55579.2** where that row is `50008`. No convex
  combination of a source topping out at 50008 produces it; the edge row read at both the centre and the
  clamped neighbour does.

**So both edges clamp, and neither drops.** It is one rule, not two: a tap outside the picture lands on the
edge element with its weight intact, and the weights are **not** renormalised over the survivors - which is
the header's own `kvImageEdgeExtend`, and the only rule consistent with the guard-page result that the system
reads nothing outside the caller's buffer.

**What is left, and it is one question.** A clamp-everywhere run breaks the **in-row** cases at a translate of
+1 and -1 by about 3.8, where the system plainly does something else: the *centre* tap is outside the picture
there, and a clamped centre is not the same as a clamped flank. The question the grid still has to answer is
whether a tap whose **own position** is outside the picture is clamped like any other, or dropped while only
the ones past it are clamped. One case separates them: a destination pixel whose centre is half a pixel left
of the source, where clamping the centre reads column 0 with the full centre weight and dropping it does not.

## The centre: DROPPED, and the position is not clamped either

A destination pixel whose centre sits half a pixel **left** of the source - a translate of -0.5 with a scale-1
filter, the same two-edge source, and both candidates compared against the measured value:

| case | measured | clamped centre | dropped centre |
| --- | --- | --- | --- |
| slope 0, translate −0.5, row 0 | 5553.2 | 9000.0 | 220.1 |
| slope 1, translate −0.5, row 0 | −1.0 (the backColor) | 9000.0 | 220.1 |
| slope 0, translate −1, row 0 | **101.0** | 9000.0 | 220.1 |

**Neither, and the third row says why.** At a translate of −1 the destination's first column answers
**101.0**, which is `value_at(0, 1)` — the source's *second* column. So the mapping is

    sx = dx - xTranslate

with **no clamping of the position**: `dx = 0` and a translate of −1 name the source's column 1, not column 0.
And a tap outside the picture is **dropped**, not clamped — at a translate of +0.5 the first column answers
5491.0, which is one weight of 0.61141 times column 0's 9000 with nothing added, where a clamped neighbour
would have added its 0.02446 of the same 9000 and given 5723.

So the rule along the row is the one this port already implements: `sx = dx - xTranslate`, out-of-picture taps
dropped, and `kvImageBackgroundColorFill` back-colouring a sample whose whole kernel is outside - which is
what a slope of 1 and a translate of −0.5 answers at row 0, the backColor.

**So the clamp-everywhere run was wrong on both edges, and the two-edge grid's "clamped" reading was
over-interpreted**: a left-edge destination pixel reading column 0's value is what *dropping* produces at a
whole-pixel phase too, because the out-of-range lobes are exactly zero there and the surviving centre tap is
column 0. The grid separated the two at a *half*-pixel phase - where the system gave 5491, one weight of
column 0 and nothing else - and that is the line that settles it.

**What the 5558 still is.** The bottom-edge overshoot is real and still unexplained by any rule here: at a
slope of 0, row 5 column 8 answers 55579.2 where that row is 50008, and the guard page says the value came
from inside the allocation. With the row's taps now known to be *dropped*, the remaining candidate is that the
diagonal walk at a slope of 1 re-reads the last row more than the tap count implies - the overshoot's
signature, a value above the source maximum, is a row counted twice. The one case that separates "the last
row's taps are read once" from "the last row is repeated to fill the walk" is a slope of 1 with a **tall**
source, where the walk never runs out: if the answer is the exact source value at a whole-pixel phase, the walk
is read once, and if it is anything else the last row is repeated.

## The tall source rules out "the walk is filled by repeating the last row" - and the two edges are two rules

A slope of 1 over sources **tall enough that the diagonal walk never runs out of rows inside the kernel** -
9x12 and 9x20, the same two-edge source, whole-pixel answers counted by matching them against a value the
source actually holds:

    9x12  slope 1  translate 0    3 whole-pixel answers, 2 above the source's maximum, 103 other
    9x12  slope 0  translate 0  108 whole-pixel answers, 0 above the source's maximum,   0 other
    9x20  slope 1  translate 0    6 whole-pixel answers, 2 above the source's maximum, 172 other
    9x20  slope 1  translate 0.5 36 whole-pixel answers, 0 above the source's maximum, 144 other
    9x6   slope 1  translate 0    2 whole-pixel answers, 2 above the source's maximum,  50 other

**A tall source still has the two overshooting answers**, so the walk is not being filled by repeating the
last row, and the cause is not running out of rows. The overshooting cells are all in the *last row*, whose
values are the 50000s: at 9x6 the row is `dy=5  ... 33560.3 53670.0 49122.1 50003.5 50004.5 50005.5 48783.4
55579.2`, and 55579.2 is 0.61141 of 50008 plus 0.5 of 50008 - **the last row read twice, with total weight
1.111**, which is a clamped tap whose weight was not renormalised away.

So the two edges really are two rules, and which is which is settled by the half-pixel cases rather than the
whole-pixel ones:

- **along the row**, where the diagonal does not move, an out-of-picture tap is **DROPPED** - a translate of
  +0.5's first column answers 5491.0, one weight of column 0 and nothing else, and a translate of -1's first
  column answers 101.0, which is the source's *second* column, so the position is `dx - xTranslate` with no
  clamping of its own.
- **along the shear**, where the taps step down a row each, a tap past the last row is **CLAMPED to it with
  its weight intact and no renormalisation** - the 5558 and 55579.2 fingerprints, which no convex combination
  of the source produces and which the guard page shows came from inside the caller's allocation.

**That is what the port has to implement, and it does not yet.** The committed engine drops at both edges, so
its bottom-edge cells differ from the system's by exactly the overshoot, and its in-row cells are already
right - which is the shape the coordinator described: differences only in the bottom-edge cells at a non-zero
slope, and a bug anywhere else.

The port's `CharonShearRun` needs one change: when a tap's **row** is outside the picture, clamp it to the
edge row and keep its weight; when its **column** is outside, drop it as now. That is a two-line difference
in the tap loop and it is the whole of the remaining work on this family.

## The two-rule change is in, and the failures are NOT the bottom edge

`CharonShearRun`'s tap loop now drops a tap whose **column** is outside and clamps a tap whose **row** is
outside, with its weight intact. The shear differential over 212 cases:

    212 checks, 101 failures, the widest sample difference 3.96584 of a 0..1 channel

and the failures are **in the in-row cases at a whole-pixel translate**, not at the bottom edge:

    translate 0   34 failures      translate -0.5   2
    translate 1   34 failures      translate 0.5    2
    translate -1  29 failures      translate 2.5    0

with the differences at **row 0 and row 1 of every case** and a magnitude of 2 to 3.8 on a channel whose
range is -2 to +2 - which is the whole channel, not a rounding. So the position and tap handling at a
non-zero translate is wrong, the same place it was before this change, and the bottom edge is now *cleaner*
rather than being the only thing left.

**Concretely, what the two disagree about.** At a translate of +1 the system answers the **backColor** for the
first two destination columns, while the port answers source pixels there: the port puts the mapped position
at `dx - xTranslate`, finds the taps for columns 1 and 2 inside the picture and uses them, and the system
treats a sample whose kernel reaches left of the picture as wholly outside. At a translate of +0.5, by
contrast, the system answered 5491.0 - one weight of column 0 and nothing else - so it does not wholly
back-colour there. Those two cannot both come from one rule, and the half-pixel case that separates them is
the same `dx - xTranslate` the port already has.

So the remaining difference is the **in-row** position rule at a whole-pixel translate, not the shear
direction and not the bottom edge, and it is a bug in the committed engine rather than a divergence to pin.

## The constant-source table: the in-row rule is the BACKCOLOR, not a drop

A source constant at 1.0, a backColor of -1, a scale-1 filter, slope 0, over a nine-wide picture - so the
answer reads the applied weight sum directly, `2w - 1`, and no reasoning about the kernel is needed:

| translate | dx=0 | dx=6 | dx=7 | dx=8 |
| --- | --- | --- | --- | --- |
| -2.0 | 1.000 | 1.000 | **-1.000** | **-1.000** |
| -1.5 | 0.951 | 0.951 | **-0.000** | **-1.223** |
| -1.0 | 1.000 | 1.000 | 1.000 | **-1.000** |
| -0.5 | **1.223** | 1.000 | 0.951 | 1.223 |
| 0.0 | 1.000 | 1.000 | 1.000 | 1.000 |

`-0.000` and `1.223` are **weights**, not dropped taps: a substituted backColor with a negative Lanczos
lobe and one with a positive overshoot. So an out-of-picture tap is **replaced by the backColor, keeping its
weight** - which is `kvImageBackgroundColorFill` read literally, and is not a drop at all. At a whole-pixel
phase the out-of-range lobes are exactly zero, so dropping and substituting are indistinguishable there, and
that is why a whole-pixel grid read as "dropped" and misled this twice.

Implemented, and the differential is still red:

    212 checks, 100 failures, the widest sample difference 5.8997e+35 of a 0..1 channel
    FAIL vShear 9x5 into 9x5 translate 0 scale 1 flags 0x4: row 1 sample 5 differs by 2

**And the remaining failure is the IDENTITY** - slope 0, a translate of 0, a scale of 1, where the
destination must be a byte-for-byte copy of the source and no resampling happens at all. A difference of 2 on
a channel whose range is -2 to +2 is the whole channel, so the engine is wrong where it has nothing to
resample. That is a bug in the committed tap loop and not a divergence to pin, and it is the next thing to
find. The 36 registry entries stay **out**.
