# Vision of iOS 11 and 12

Vision came in iOS 11.0 with a request handler that runs requests - detect rectangles, barcodes, text, faces and face landmarks, the horizon, track an object, register two
images, run a Core ML model - on an image, and observations that the requests fill. iOS 12.0 added revisions to every request and the observation of a recognized object.

Source: Vision of the arm64 shared cache of iOS 12.0 - the constants `VNErrorDomain` (`com.apple.vis`) and `VNVisionVersionNumber` (2.0) as data, the six geometry
functions as code, `-[VNRequest initWithCompletionHandler:]`, `-setRevision:` and `+defaultRevision`, the defaults of `VNDetectRectanglesRequestConfiguration`, the
setter of `VNTrackingRequest`, `+[VNFaceObservation faceObservationWithRequestRevision:boundingBox:roll:yaw:]` and `+[VNError errorWithCode:message:]` - and the host's own Vision under Mac Catalyst,
recorded by `tests/backports/host/vision/run.sh` (33 records) and held against the port on the iPad 2 by `tests/backports/device/vision.m`.

## What the port does

- The constants, the barcode symbologies of iOS 11 as strings, `VNNormalizedIdentityRect` and the six geometry functions answer what the release's do, to the last digit: a normalized point
  or rectangle scaled by the size of the image, a rectangle of an image normalized by it with an image of no width or height giving zero there, and a landmark point placed in a face box. The host
  gives the same. The error domain and the version number are those of iOS 12, and not of the host, whose Vision is newer (`com.apple.Vision`, 10.0).
- The classes of iOS 11 and 12 are all there, with the defaults of iOS 12: a rectangles request looks for one rectangle of an aspect ratio between 0.5 and 1 that is
  at least 0.2 of the image and within 30 degrees of square, a barcode request for every symbology the release knows, an object tracker at the fast level, a request in the whole image, and a new request
  takes the latest revision of its class, of which there are two for faces and for the object tracker and one for the rest. A request copies with its settings and without its results. An
  observation is made with a new identifier, a confidence of one and the revision it is given; a face observation is made only with a roll in `[-pi, pi)` and a yaw in `[-pi/2, pi/2)`, and both given, as iOS 12 does; an observation copies
  and archives (`NSSecureCoding`) with its fields, in keys of the port's own.
- A request handler takes an image as a pixel buffer, a `CGImage`, a `CIImage`, a URL or data, with an orientation and options, and keeps it. `-performRequests:error:` of it and of the sequence handler
  call the completion handler of each request once, with the error of that request, before it returns, and answer NO with the error of the first request that failed, as Vision does.
  A revision the class has not fails as `VNErrorUnsupportedRevision`, a Core ML request without a model as `VNErrorInvalidModel`, and every other request as `VNErrorNotImplemented`.
- **Core ML is in this release now, through the CoreML backport this band carries**, so the Core ML
  request is the one request Vision here really runs: `+[VNCoreMLModel modelForMLModel:error:]` holds
  a real `MLModel`, refuses a model that takes no image in any of its inputs with `VNErrorInvalidModel`
  -- the example Core ML's own documentation names -- and `VNImageRequestHandler` hands the image
  through the model and puts the answers in the request's results.

  The image is brought to the size the model's own description asks for, by the two rules Vision
  declares and Core ML's own image constructors use -- measured against Core ML's own constructor
  as the oracle, which is what this port has to match:

  **Most of the red table was the probe, not the port, and those numbers are withdrawn.** With the
  probe's control passing -- vImage asked to do nothing at all to Core ML's own bytes reads 0 of
  every case -- the port's own answers are:

  | picture to | rule | the port, against Core ML's own option for that rule |
  | --- | --- | --- |
  | 100x50 to 224x224 | scale fit | **0** of 50176 |
  | 13x7 to 8x8 | scale fit | **0** of 128 |
  | 16x16 to 16x16 | either | **0** of 256 |
  | 8x8 to 16x16 | either | **0** of 256 |
  | 4x7 to 33x9 | scale fit | **0** of 432 |

  Five rows at zero, with the geometry, the format, the row length and the kernel all unchanged
  from the runs that reported them red. **Withdrawn:** 49632 of 50176 and 50015 of 50176 for
  100x50 to 224x224, 64 of 128 for 13x7 to 8x8, 252 of 256 for 8x8 to 16x16, 338 and 347 of 432 for
  4x7 to 33x9, and "the kernel reads 50015 / 50015 / 50092" for the three CoreGraphics qualities --
  every one of those was the probe feeding vImage a source it had reconstructed rather than Core
  ML's, and none of them is a statement about the port. The `kCGInterpolationHigh` in
  CharonVisionImage.h is therefore not a measured choice either: it was put there for a
  premultiplied-alpha hypothesis that the numbers rejected, and what it does to the fit rows is
  nothing, because those rows are already 0.

  **vImage is excluded**, on the same control: on 100x50 to 224x224 scale fit it reads 23448 of
  50176 where the port reads 0, on 13x7 to 8x8 31 against 0, on 4x7 to 33x9 44 against 0, and the
  four flag sets -- no flags, Lanczos, edge extend, both -- are indistinguishable from each other on
  every scaling row. So it is neither adopted nor needed.

  **One row is still red: 100x50 to 224x224 centre crop, 50176 of 50176.** Its oracle is Core ML's
  own `CenterCrop` option, which is the framework's rule for that name -- Core ML's no-option default
  is left alone, as instructed, and it is recorded as measured: 50175 of 50176 from its own ScaleFit
  and 50035 of 50176 from its own CenterCrop, so neither offered option reproduces it. Every pixel
  differing is a placement or a scale, not a rule, and the measurements for it -- row 112 of both
  buffers side by side, the port's output shifted -3..+3 horizontally, the crop origin placed by
  floor, by round and exactly, and the port's crop rect beside the one Core ML would produce under
  `MLFeatureValueImageOptionCropRect` -- are **attempted and not yet obtained**: that probe run
  faults on the centre-crop oracle, which comes back NULL when the constructor is handed an
  explicit size and an option with no constraint behind it, and the measurement dereferences it.
  Two of those measurements are now in, and both **exclude** their hypothesis:

  - The centre-crop oracle answers, with error `null`/0 and the very options dictionary the
    working run used. The null in the previous run came from the *other* dictionary in that block --
    a `CropRect` whose value was an `NSValue` wrapping a range, where Core ML wants a rect -- which
    is what the coordinator said it was.
  - The three crop origins (exact, floor, round) all compute the **same** inset, `-112`, for this
    case, and all three read **50176 of 50176**. So the crop origin is not the difference, and with
    all three coinciding at the centre the horizontal shift sweep cannot find one either.

  What is left is the *content*: with the same scale (4.48) and the same origin, Core ML's
  centre crop of a 100x50 picture into 224x224 does not produce what a cover-and-crop produces, and
  every pixel differs. The next measurement is the two buffers' corners and rows **of the port's own
  answer** against the oracle's, which means building the probe as a port build for that block --
  the row-112 dump in the last run compared the oracle with itself, the call site passing it twice,
  so it is not evidence about the port and is not recorded as any.

  **The method is now the one the coordinator set, and the result is that the earlier zeros were an
  artefact.** One CGImage, created once from fixed bytes, is handed to Core ML's constructor
  directly and to the port through the port's own picture-to-buffer helper and its own resampler --
  no second builder, nothing reconstructed from another framework's answer. The verdict counts the
  three colour channels, because that is what a model reads: an image feature of an RGB model
  carries three, and the fourth byte of a BGRA buffer is not one of them. That byte is reported
  beside the verdict as information. The 1:1 control reads **0/0 on every row of both sizes**, so the
  method is sound.

  Colour/alpha, differing pixels, for 100x50 brought to 224x224:

  | key handed to Core ML | port CentreCrop | port ScaleFit | port at its own size | the 1:1 control |
  | --- | --- | --- | --- | --- |
  | CenterCrop (0) | 50175/1996 | 50176/1996 | 50176/45645 | **0/0** |
  | ScaleFit (1) | 50176/25088 | **25028/25088** | 30084/30088 | **0/0** |
  | ScaleFill (2) | 50176/0 | 50172/0 | 50171/45176 | **0/0** |
  | no option | 50176/0 | 50172/0 | 50171/45176 | **0/0** |

  and for 13x7 brought to 8x8:

  | key handed to Core ML | port CentreCrop | port ScaleFit | port at its own size | the 1:1 control |
  | --- | --- | --- | --- | --- |
  | CenterCrop (0) | 64/22 | 64/22 | 99/57 | **0/0** |
  | ScaleFit (1) | 64/32 | **48/32** | 90/59 | **0/0** |
  | ScaleFill (2) | 64/0 | 64/0 | 99/43 | **0/0** |
  | no option | 64/0 | 64/0 | 99/43 | **0/0** |

  **No cell is 0 except the control.** The best is the port's ScaleFit against Core ML's own
  `ScaleFit`, at 25028 of 50176 and 48 of 128 -- a partial agreement, not agreement. So the
  condition under which the earlier five rows were called zero -- "if ScaleFit and 1:1 read 0 on
  colour, they are genuinely right" -- is **not** met, and those five rows are withdrawn for the
  second time and now with the method that finds it. The Core ML no-option default is confirmed to
  be `ScaleFill`, exactly (its no-option row is its `ScaleFill` row, pixel for pixel).

  **Magnitudes, not counts, and then the uniform case, which rules colour management out.** 25028
  colour-differing pixels is the picture's own interior (224x112 = 25088), so the bars agree and the
  scaled picture differs. The histogram of max |dB|,|dG|,|dR| per pixel over that region, in the
  buckets 0, 1, 2, 3-7 and >=8, for every candidate fed from the same single source:

  | candidate | 0 | 1 | 2 | 3-7 | >=8 | max abs |
  | --- | --- | --- | --- | --- | --- | --- |
  | the port, Core Graphics | 60 | 339 | 457 | 4933 | 19299 | **55** |
  | vImage, no flags | 4 | 115 | 164 | 1970 | 22835 | 68 |
  | vImage, Lanczos | 6 | 48 | 90 | 1311 | 23633 | 88 |
  | vImage, edge extend | 4 | 115 | 164 | 1970 | 22835 | 68 |
  | vImage, Lanczos + edge | 6 | 48 | 90 | 1311 | 23633 | 88 |

  None is in the 0 bucket and the port is the closest of them. **Core Image's
  `CILanczosScaleTransform` is still unmeasured** -- the filter was handed a `CIVector` under
  `kCIInputAspectRatioKey`, where it wants a number, and raised. The coordinator's condition for
  chasing that was a residual left by the colour test, and there is none.

  **The uniform case rules colour management out.** A single colour -- (200,100,50) -- over 100x50
  brought to 224x224 under `ScaleFit`, read at the middle of the picture on both sides:

  ```
  coreML   B=32 G=64 R=c8 A=ff
  the port B=32 G=64 R=c8 A=ff     identical, to the byte
  ```

  and at the middle of the bars they differ only in the fourth byte -- 00 against ff -- which a model
  does not read. **Core ML's buffer carries no colour space at all**, and the port's context and the
  picture's are both plain RGB models, so there is nothing on either side to convert. So the smooth
  difference over a gradient is not colour, and since geometry and a kernel cannot change a uniform
  image and the uniform case agrees, it is not the geometry either.

  **The impulse, and three of its four cases were confounded -- withdrawn.** An impulse is the right
  way to read a kernel, and reading it settled the *placement* instead: with a picture black except
  one white column, the output row of `16x8` brought to `64x8` under `ScaleFit` is

  ```
  impulse at source column 4:  ... 255 at output column 28 ...
  impulse at source column 3:  ... 255 at output column 27 ...
  4x down, 64x8 -> 16x8, impulse at source 20: row 0 all zero, row 4 has 137 at column 5
  ```

  The scale is `min(64/16, 8/8)` = **1**: a wide, short picture brought to a wide, short target is
  never scaled horizontally, because the height caps the scale. So the picture is *placed* -- output
  column = bar 24 + source column, at 255, unfiltered -- and those three cases measure placement, not
  a kernel. They are withdrawn as kernel evidence. Two facts survive them: where nothing is scaled
  the picture is point-sampled with no filter at all, and the one case that really did scale (the 4x
  down) answers **137** for a 255 impulse, so there *is* filtering on a downscale.

  And a placement datum out of the same rows: `16x8` brought to `32x8` puts source column 5 at
  output **14**, where bar + 5 is 13 -- Core ML's horizontal inset there is one more than
  `(W - w) / 2`, which the centre-crop row may share and the fit rows do not.

  **The kernel, read off the aspect-matched cases.** With the target's aspect matching the picture's,
  `ScaleFit` scales it, and the output row *is* the impulse response. The red channel, as numbers:

  * **4x up, a white column at source 4** (`16x8` -> `64x32`) -- eight symmetric taps, centred
    between output columns 17 and 18:

    ```
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 32 96 159 223 | 223 159 96 32 0 0 ...
    ```

    The weights are `32 96 159 223 223 159 96 32`, they sum to **exactly 1020 = 4 x 255**, the scale,
    and the two central taps are equal. An even-symmetric response whose two central taps are equal
    puts the kernel's centre **between** two destination pixels, and the centre sits at 17.5 for a
    source column of 4 and a scale of 4: that is the **half-pixel convention**, `dst = (x + 0.5) * s -
    0.5`, not align-corners. **Eight taps** is neither bilinear (two) nor bicubic (four), and the
    weights' shape -- rising, a flat pair at the top, falling -- is the signature of a wider kernel
    than bicubic, which with a 4x support is what a **Lanczos-style** filter gives on the way up.

  * **4x up, a white row at source 2** -- the same eight taps down the other axis, so the kernel is
    **separable**: one set of weights horizontally, the same vertically.

  * **4x down, a white column at source 20** (`64x32` -> `16x8`) -- a **single** output pixel, `137`,
    with no spread at all. So the downscale is a **point sample through the same filter**, not an
    area average: it is not `255 / 16` and it is not `255`, and nothing of the neighbours reaches
    it.

  * **1.5x, a white column at source 4** (`16x8` -> `24x12`) -- `43 212 128`, and at source 5
    `128 212 43`. The response is **asymmetric**, which is where the convention shows at a
    non-integer scale: the same weights, sampled at a fractional position, put their mass to one
    side. It is also the shape that a half-pixel convention gives and an align-corners one does
    not.

  **The coordinator's reading of those numbers is right, and it checks out against the arithmetic:**
  the kernel is **separable bilinear with half-pixel centres and no antialiasing on a downscale**,
  and what reads as eight taps at 4x is a two-source-pixel tent mirrored about the centre between
  two destination pixels.

  * **4x up.** A tent two source pixels wide covers eight destination pixels, and half-pixel centres
    give the weights 0.125, 0.375, 0.625, 0.875 -- which times 255 is 32, 96, 159, 223, exactly the
    row, mirrored by the symmetric half of the tent.
  * **1.5x.** `src = (x + 0.5) / 1.5 - 0.5` gives 3.167, 3.833 and 4.5 for x = 5, 6, 7, and the
    weights `1 - |src - 4|` are 0.167, 0.833, 0.5 -- 43, 212, 128, again exactly the row.
  * **4x down.** Bilinear with no prefilter point-samples, which is the "no spread" the row shows.
    The printed 137 is one row of a two-dimensional sample and the exact factor for it is the one
    number in this account that has not been computed here; it is a bilinear sample at the
    half-pixel position with both axes, and the 4x-up and 1.5x rows are what identify the kernel.

  So the parameters, as measured and as derived: **separable bilinear, the sample centre at
  `(x + 0.5) * s - 0.5` (half-pixel, not align-corners), no area averaging when the scale is below
  one**, and the rounding of the sample position to be read from the gradient -- round-half-up or
  truncation are not yet separated by a measurement.

  **The kernel is written, measured, and one bit of rounding from the table.** In
  `.agent-work/runs/crop-probe/kernel.c`, linked beside the port's own geometry into
  `kernel-probe.m` with the same single source and the same picture Core ML is given.

  The first measurement was catastrophic -- 24834 of the region's 25088 at eight or more, maximum
  255 -- and **unchanged by clamping the sample position**, which is what ruled out the edge and said
  the error was the mapping. It was: the sample position was `(insetY + y + 0.5) * s - 0.5`, adding
  the destination inset into the *source* coordinate as well as the store address, which offset every
  row by 56 * 50/112 = 25 source rows. With the inset out of the sample position:

  | variant | 0 | 1 | 2 | 3-7 | >=8 | max abs |
  | --- | --- | --- | --- | --- | --- | --- |
  | round half up, position and store | 5640 | 2229 | 524 | 1190 | 15505 | 171 |
  | **truncate, position and store** | 3307 | 21781 | 0 | 0 | **0** | **1** |

  So the kernel is structurally right: **every pixel is now within one**, where the CoreGraphics
  draw it would replace had 19299 at eight or more and a maximum of 55, and the round-half-up
  position is what produces the 171. The last bit is the remaining 21781 pixels being off by
  **exactly one**, which is the store's rounding: the position wants truncation and the value has
  not been separated from it yet. Splitting that seam -- truncate the position, round the value --
  is one measurement from the 0 bucket.

  **Integrated, and every scale-fit row now reads 0.** The kernel is in the library as
  `Vision/CharonVisionBilinear.c` with a two-line declaration in `CharonVisionImage.h`, and the
  header changes by one call: the CoreGraphics draw becomes the kernel call, with the rect the two
  branches already computed handed to it as the placement. Everything around it is untouched, and
  the library compiles for armv7 at 6.1.3 with the file that includes the header.

  **The check measures the port, and the table through it is now the port's own.** Three defects in
  the check are fixed: the port build compiles `CharonVisionBilinear.c`; each side's origin is printed
  with `dladdr` and the run **fails** if the two resolve to the same image, so a comparison that has
  collapsed into the framework against itself cannot read zero; and the verdict and the mutants are
  counted separately, with the mutants running whatever the verdict was. The mutant is the
  destination inset put back into the sample position, it hashes the file before and after and fails
  the run if the patch changed nothing, and it is caught: `the mutant changed the file:
  642746bd7e11 -> 8a45ff6e29b8`, `mutants: 1 run, 0 surviving`.

  Two native fixes came out of running it:

  - **The geometry.** The library handed the kernel a `long` cast of the placement's double, and the
    bars were drawn by a CoreGraphics context *underneath* the kernel's output -- two resamplers,
    with the CG one winning wherever they disagreed. The placement is now rounded the way the probe
    rounds it, and the bars are the kernel's own memset, whose value is Core ML's measured
    `00 00 00 00`.
  - **A cover is not clamped to the target.** Clamping the drawn size instead is a scale fit
    wearing a cover's name: a 100x50 picture at 224x224 is drawn 448 wide with an inset of -112 and
    the kernel writes only the 224 columns that land inside. That is what left the square
    centre-crop rows red, and removing the clamp made them exact.

  Through the check, the port against Core ML's own option for the same rule:

  | picture to | scale fit | centre crop |
  | --- | --- | --- |
  | 16x16 to 16x16 | **0** of 256 | **0** of 256 |
  | 8x8 to 16x16 | **0** of 256 | **0** of 256 |
  | 13x7 to 8x8 | 1 of 128 | 64 of 128 |
  | 4x7 to 33x9 | **0** of 432 | 297 of 432 |
  | 100x50 to 224x224 | 3208 of 50176 | 50176 of 50176 |

  So the scale fit is exact on three of the five and one count off on a fourth, and the **square
  centre crops are exact**.

  **Where the crop starts: the complete table, committed as a fixture**
  (`tests/backports/host/vision/croprect.md`, written by `.agent-work/runs/crop-probe/croprect.m`).
  A picture black except one white **column**, and another with one white **row**, each brought to a
  target of a different aspect under Core ML's own options, read across a row and down a column.
  The columns give the scale, the drawn size, the inset the port's rule computes, where that rule
  puts the impulse, and where Core ML's response is centred:

  | case | rule | scale | drawn | inset | rule puts it | Core ML centres it (row) | (column) |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | 100x50 to 224x224 | centre crop | 4.48 | 448x224 | -112, 0 | 112 | 116 | 109 |
  | 50x100 to 224x224 | centre crop | 4.48 | 224x448 | 0, -112 | 112 | 114 | 107 |
  | 16x8 to 32x8 | centre crop | 2 | 32x16 | 0, -4 | 16 | 16 | 2 |
  | 10x10 to 30x20 | centre crop | 3 | 30x30 | 0, -5 | 15 | 16 | 4 |
  | 20x10 to 20x20 | centre crop | 2 | 40x20 | -10, 0 | 20 | 10 | 8 |
  | 100x50 to 224x224 | scale fit | 2.24 | 224x112 | 0, 56 | 112 | 112 | 110 |
  | 50x100 to 224x224 | scale fit | 2.24 | 112x224 | 56, 0 | 56 | 112 | 110 |
  | 16x8 to 32x8 | scale fit | 1 | 16x8 | 8, 0 | 8 | 16 | 3 |
  | 10x10 to 30x20 | scale fit | 2 | 20x20 | 5, 0 | 10 | 15 | 8 |
  | 10x10 to 30x20 | scale fit, height exact | 2 | 20x20 | 5, 0 | 10 | 15 | 8 |
  | 5x10 to 30x20 | scale fit, height exact | 2 | 10x20 | 10, 0 | 4 | 14 | 8 |
  | 10x20 to 30x10 | scale fit, width exact | 0.5 | 5x10 | 12, 0 | 2 | 14 | 4 |

  Read down the "rule puts it" and the two Core ML columns and the shape of what is left is this:
  the **two overflow cases of the centre crop agree on the horizontal axis to within a source
  pixel** (112 against a response spanning 112 to 120, whose centre is 116 -- one source column at
  4.48 is 4.48, and a two-tap run of one source pixel is that wide, so the centres cannot agree to
  better than that from a run's midpoint), and the two **scale-fit rows where the picture fits
  exactly on an axis** put Core ML's centre 2 to 6 columns from the rule's answer, in both
  directions, with no sign that either axis is the one at fault: on the 100x50 centre crop the
  horizontal is 4 late and the vertical 3 early.

  So the table does **not** yet yield a rule, and per the coordinator's instruction **nothing in the
  library changes**: the fixture is committed, the rows that agree are recorded, and the rows that
  do not are recorded with their residuals (+4/-3 on the wide centre crop, +1/+2 on the small ones,
  +2/-2 on the fit rows). The next measurement the table says to take is the same case with the
  impulse at a *fractional* source position, which would separate "the crop rect is different" from
  "the response of one source pixel is wider than I am reading its centre as".

