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
- Core ML is not in this release, so `+[VNCoreMLModel modelForMLModel:error:]` answers nil and `VNErrorInvalidModel`.

## What is not carried

No request runs: the port carries what an application names and answers the error of a function that is not implemented, so the application takes its own path, and not an empty result that says
nothing was found. Detecting a barcode, a rectangle, a face and its landmarks are next, each with the host's Vision as the oracle. The observations that only a running request makes (rectangles, barcodes, faces with landmarks) have
their properties and no way to be made yet; the landmark regions answer no points. `+revision:supportsConstellation:` arrived in iOS 13 and is not carried. The host's Vision is newer than the releases read and differs in what it does with a tracker's level (it ignores it), a copy of an observation (it
returns the same object), a yaw out of range (it clamps) and the symbologies it reads by default (it has more); the port follows iOS 12 there, and the records leave those out.
