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

  | picture to | differing pixels, the port against Core ML | of |
  | --- | --- | --- |
  | 100x50 to 224x224, centre crop | 50175 | 50176 |
  | 100x50 to 224x224, scale fit | 49632 | 50176 |
  | 13x7 to 8x8, either | 64 | 128 |
  | 16x16 to 16x16, either (the exact 1:1) | **0** | 256 |
  | 8x8 to 16x16, either (an integer 2x) | 252 | 256 |

  The check is `tests/backports/host/vision/run-crop.sh` with `crop.m`: one program built twice,
  once against Core ML's own `+[MLFeatureValue featureValueWithCGImage:pixelsWide:pixelsHigh:pixelFormatType:options:error:]`
  -- which answers itself with 0 of every case, so the program is sound -- and once against the
  port's own resampler, compiled with the library under names of its own. Each case prints
  `differing=N of M` and the run fails if any N is not zero.

  **The port does not match, and the reason is not yet known.** The one case it matches exactly is
  the one where no resampling happens at all: a 16x16 picture asked for as 16x16 is handed on
  untouched, and 0 of 256 pixels differ. Every case that *scales* is wrong, and wrong by nearly
  every pixel rather than by the handful a blend-versus-paste difference would cost -- so this is
  not the interpolation quality, and `kCGInterpolationHigh` is not the answer either: the harness
  compiles the port's own function with each of CoreGraphics' three qualities and every one of them
  reads the same 50175 of 50176. Something about the drawing differs wholesale -- the channel order
  of the buffer it reads, or the geometry it draws into -- and the next thing to do is read the two
  buffers' first rows side by side and name the difference. The seam for the quality
  (`CHARON_VISION_INTERPOLATION`, defaulting to `kCGInterpolationHigh`) is what let all three be
  measured in one run, and it stays because it is how the right one will be recognised when the
  cause is found.

  The review's own figures -- 1996 of 50176 for 100x50 to 224x224 and 22 of 64 for 13x7 to 8x8 --
  were measured against a paste through a different path, and this check does not reproduce them;
  the numbers above are the ones this tree produces, and they are worse.

  The two rules themselves: centre crop scales until the picture covers the
  target and keeps the middle, scale fit scales until it fits and leaves the rest black. A buffer
  that is already the size the model wants is passed on untouched, so a camera or video frame costs
  nothing, and the row length a picture is drawn into is the buffer's own
  (`CVPixelBufferGetBytesPerRow`), never `width * 4` -- CoreVideo pads its rows to a boundary of its
  own, so a width that is not a multiple of 16 has rows longer than its own pixels.

  **What the host's Vision transform accepts is not yet known, and four shapes were measured to find
  out.** `vision_image` in `tools/coreml/make-models.py` is an image model; the host answers a
  *refusal* for every shape tried -- a fixed 32x32 input with a fixed output gets the wrapper made and
  the request fails with "The VNCoreMLTransform request failed", and a ranged input, with a fixed or a
  ranged output and with a preprocessing scaler, is refused by the wrapper itself with "Failed to
  initialize VNCoreMLTransformer". The port is held to the same answer, and the case records it. The
  three rules the request path would exercise behind an accepted model -- the two crop-and-scale rules
  and the Core ML branch of the handler -- are therefore named in `tests/backports/host/vision/run.sh`
  as unexercised rather than left to fail the mutant line, and the corpus change that would reach them
  is the open one. A `CIImage`, an image URL and image data are not pixel buffers, and a Core ML
  image input takes a buffer, so they reach the same failure any other unusable image reaches
  rather than pretending the picture was something it is not.

  The answers are mapped as Core ML maps them, and the mapping is decided by what the model's
  *description* says an answer is rather than by what the numbers look like: the name a classifier
  answers its label under becomes one `VNClassificationObservation` per class, highest score
  first, with the score as the observation's confidence; an image answer becomes a
  `VNPixelBufferObservation` under the name of the output it came from; anything else becomes a
  `VNCoreMLFeatureValueObservation` holding the value whole.

## What is not carried

No request runs: the port carries what an application names and answers the error of a function that is not implemented, so the application takes its own path, and not an empty result that says
nothing was found. Detecting a barcode, a rectangle, a face and its landmarks are next, each with the host's Vision as the oracle. The observations that only a running request makes (rectangles, barcodes, faces with landmarks) have
their properties and no way to be made yet; the landmark regions answer no points. `+revision:supportsConstellation:` arrived in iOS 13 and is not carried. The host's Vision is newer than the releases read and differs in what it does with a tracker's level (it ignores it), a copy of an observation (it
returns the same object), a yaw out of range (it clamps) and the symbologies it reads by default (it has more); the port follows iOS 12 there, and the records leave those out.
