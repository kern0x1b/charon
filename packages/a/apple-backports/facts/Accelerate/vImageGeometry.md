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


