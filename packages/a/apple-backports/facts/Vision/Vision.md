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

  It has now run, with the port's own resampler built into the probe
  (`.agent-work/runs/crop-probe/`, the harness's trick, renamed header and all), and **it corrects
  the previous round's conclusion.**

  `VNImageCropAndScaleOption` is CenterCrop=0, ScaleFit=1, ScaleFill=2 in Vision's own header, and
  the probe takes the value from that header rather than from a literal, so a mismatched value is
  not what happened. The 3x3 for 100x50 brought to 224x224, differing pixels, columns what the
  probe hands Core ML and rows the port's own rule:

  | port \ key | CenterCrop (0) | ScaleFit (1) | ScaleFill (2) | no option |
  | --- | --- | --- | --- | --- |
  | port CenterCrop | 50026 | 50175 | 50148 | 50148 |
  | port ScaleFit | 50176 | 49632 | 50174 | 50174 |
  | no option vs Core ML's own | 50174 | 50175 | **0** | -- |

  Two corrections, and the second is the one that matters:

  - **Core ML's no-option default is `ScaleFill`**, exactly: the framework's answer with nothing in
    the options dictionary and its answer with 2 under the key differ by 0 of 50176. So the stretch
    this row was reading -- the whole source scaled to 2.24 across and 4.48 down -- is the
    *default*, not `CenterCrop`, and the previous round's claim that "Core ML's own CenterCrop is a
    stretch" was **wrong**. The centre crop Core ML answers to 0 under the key is a fourth thing again
    that the port does not match.
  - **The five zero rows do not survive a change of where the source bytes come from.** They were
    measured with the source built by the port's own picture helper, whose fresh buffer has a zero
    fourth byte; this run hands the same rule a source from Core ML's own 100x50 answer, which has
    `ff` there, and the 100x50 to 224x224 scale-fit row reads **49632** instead of 0. So those zeros
    were agreement on a byte that depended on the buffer the source was built in -- the alpha -- and
    not a general agreement; the kernel question is open again behind it, and the five rows must be
    re-measured with one source, whichever is chosen, before any of them can be called zero.

  What the three options mean to Core ML, and what they mean to Vision, is the next thing to read: the
  port carries two of the three (`ScaleFill` is not among them), and the matrix says it matches none
  of the three for this picture. The centre-crop row is therefore **not** yet characterised and the
  facts should not claim it is a divergence.

