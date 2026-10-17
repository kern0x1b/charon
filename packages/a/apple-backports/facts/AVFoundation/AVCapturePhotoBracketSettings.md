# AVCapturePhotoBracketSettings and the bracketed capture, iOS 10.0 and 11.0

What the port builds: the settings class (`AVCapturePhotoBracketSettings.m`, its two factories and its properties), the
output's bracketed capture (`AVCapturePhotoOutput.m`, `charon_captureOne:` and `capturePhotoWithSettings:delegate:`), and
the 11.0 photo the bracket's callbacks deliver (`AVCapturePhoto11.m`, facts/AVFoundation/AVCapturePhoto11.md).

## What the header says (iPhoneOS 26.2 SDK, AVCapturePhotoOutput.h)

- `AVCapturePhotoBracketSettings` is a subclass of AVCapturePhotoSettings, available from iOS 10.0 and unavailable on macOS.
  Its factories take `bracketedSettings`, an array of AVCaptureBracketedStillImageSettings (the 8.0 classes the port already
  carries, AVCaptureBracket8.m). The 10.0 factory names no file types; the 11.0 factory names the RAW and the processed file type.
- The factories raise NSInvalidArgumentException for a nil or empty array, and for a mix of the manual and the auto classes.
- At capture, `bracketedSettings.count` must be at most the output's `maxBracketedCapturePhotoCount`, else the capture raises.
- Manual members: ISO and exposure duration must lie in the device's activeFormat ranges. Auto members: the exposure target bias
  must lie in the device's `minExposureTargetBias` and `maxExposureTargetBias`.
- `lensStabilizationEnabled` defaults to NO and may be YES only when `lensStabilizationDuringBracketedCaptureSupported` is YES.
- The 11.0 callback `-captureOutput:didFinishProcessingPhoto:error:` fires `resolvedSettings.expectedPhotoCount` times for one
  request, and `photoCount` is the photo's 1-based index in it. The 10.0 callback takes the bracket setting of each photo as its
  `bracketSettings` argument.

## What 6.1.3 has (measured)

- The objc inventory of the 6.1.3 armv7 shared cache (`objc.inventory`, facts/AVFoundation/Demand8.md) finds no
  AVCapturePhotoOutput, no AVCapturePhotoSettings, no AVCapturePhoto and no AVCapturePhotoBracketSettings
  (`first-rung.py _OBJC_CLASS_$_AVCapturePhoto` answers NONE). The port's output is an AVCaptureStillImageOutput subclass
  (facts/AVFoundation/AVCapturePhotoOutput.md, "Why the output is a still image output").
- `AVCaptureDevice`'s own exposure selectors on 6.1.3 (Demand8.md, the same query on the 8.0 cache for the public names):
  the private `-setAutoExposureBias:` and `-autoExposureBias`; the private `-setExposureDuration:`, `-exposureDuration`,
  `-setExposureGain:`, `-exposureGain`; `-setExposureMode:`, `-exposureMode`, `-isExposureModeSupported:`;
  `-setExposurePointOfInterest:` and `-exposurePointOfInterest`. No ISO member and no bounds accessor of any name exists for
  the bias (AVFoundation80.md, Demand8.md).
- The public `-setExposureTargetBias:completionHandler:`, `exposureTargetBias`, `maxExposureTargetBias` and
  `minExposureTargetBias` are 8.0 names. The port drives the private pair for the first (AVFoundationDemand8.m) and leaves the
  bounds absent (Demand8.md).
- `AVCaptureStillImageOutput` on 6.1.3 has `captureStillImageAsynchronouslyFromConnection:completionHandler:` and none of the
  8.0 bracket members (see "Not carried").

## What the bracket applies, member by member

A bracket of N members is N stills, in order. Each member is applied with the controls 6.1.3 has for it:

| Member or setting | 6.1.3 control | Applied |
| --- | --- | --- |
| `AVCaptureAutoExposureBracketedStillImageSettings.exposureTargetBias` | the private bias pair, under `lockForConfiguration` (the same setter `-setExposureTargetBias:completionHandler:` drives) | Yes: set before the member's still. The camera's own bias, read before the bracket, is given back after the last photo. |
| `AVCaptureManualExposureBracketedStillImageSettings.exposureDuration` | the private `-setExposureDuration:` exists; its unit and what it does on the 4S are not measured | No. The still is taken at the camera's own exposure. Logged once per bracket. |
| `AVCaptureManualExposureBracketedStillImageSettings.ISO` | the private `-setExposureGain:` exists; the ISO-to-gain mapping is not measured | No. Same as the duration. |
| `AVCapturePhotoSettings.flashMode` (the request's, applied to every photo) | public `-setFlashMode:` on the camera (4.0) | Yes, for each photo, through the output's flash handling (`charon_setFlashMode:ofCamera:`). |
| Exposure point and lock, focus, white-balance lock | public members of 6.1.3's AVCaptureDevice | Not per member. No bracket member carries them; they are the application's own settings on the device, which the bracket does not change. |

The last row is a reading of the coordinator's instruction to apply each setting with exposure point and lock, focus, flash and
white-balance lock. Exposure lock applied per member would hold the exposure fixed and so cancel the bracket, and nothing in the
settings names a focus or a white-balance value. The reading is stated here so it can be overturned.

The bracket's photos are therefore: N stills at the camera's exposure, with the auto members' bias set in front of each. Where a
manual member is asked, the photo is the same as the others.

## maxBracketedCapturePhotoCount

The port answers `NSUIntegerMax`. A bracket is delivered as a chain of stills, each handed to the delegate when it is taken, and
the port keeps no photo of a bracket in memory: no count of its own limits a bracket. The header's limit is the device's, which
depends on the format and the preset; 6.1.3 does not report one, and no device measurement of it exists here. So the value is the
port's answer, and the header's rule (count at most the maximum) cannot fail for a bracket the port accepts.

## lensStabilizationDuringBracketedCaptureSupported

NO. The 4S has no lens stabilization. A bracket whose `lensStabilizationEnabled` is YES is refused at capture
(`NSInvalidArgumentException`, with the header's rule as its text).

## The capture

- The request counts as one capture in flight, from its call until its last photo is delivered.
- The photos run one after another: the next member's still is taken after the previous photo's callbacks.
- Callbacks: `willBeginCaptureForResolvedSettings:` once, before the first photo; `willCapturePhotoForResolvedSettings:`,
  `didCapturePhotoForResolvedSettings:` and the photo callback for each photo; `didFinishCaptureForResolvedSettings:error:` once,
  after the last. The camera's flash mode is given back after the last photo, as for a single capture.
- Each photo's callback carries its member: the AVCapturePhoto's `bracketSettings` is the member, its `photoCount` is the index
  (1-based), and its `resolvedSettings.expectedPhotoCount` is the bracket's count. The 10.0 callback gets the member as its
  `bracketSettings` argument.
- The bias of an auto bracket is set under the camera's lock, which the header requires; a camera that cannot be locked keeps its
  bias and the photo is taken at it, logged.

Refusals at capture: a count above `maxBracketedCapturePhotoCount` (cannot occur with the port's value), lens stabilization YES
where it is not supported, and a delegate with neither photo callback. A single request is refused in the same way it was before
the bracket was carried, except that the 11.0 callback now satisfies the rule.

## Not carried, and owed

- **AVCaptureStillImageOutput's own bracket members** (8.0): `captureStillImageBracketAsynchronouslyFromConnection:withSettingsArray:completionHandler:`,
  `prepareToCaptureStillImageBracketFromConnection:withSettingsArray:completionHandler:`, `maxBracketedCaptureStillImageCount`,
  `lensStabilizationDuringBracketedCaptureEnabled` and `lensStabilizationDuringBracketedCaptureSupported` on that class,
  `highResolutionStillImageOutputEnabled`, `stillImageStabilizationActive`, `stillImageStabilizationSupported` and
  `automaticallyEnablesStillImageStabilizationWhenAvailable`. They are the still output's own bracket API, which this port
  carries only where the photo output needs it. Owed: what they need is the still output's bracket delivered as an array of
  sample buffers at one completion, which the photo output's chain does not provide.
- **The header's device checks**: the exposure ranges (`minExposureTargetBias`, `maxExposureTargetBias`, the activeFormat's ISO and
  duration ranges). 6.1.3 reports none (Demand8.md), so the port checks none; a bias or duration outside what the sensor allows
  is not refused.
- **Manual exposure** on the 4S: duration and ISO are not applied (above). Owed: a measurement of the private `setExposureDuration:`
  and `setExposureGain:` on the device, and of the ISO-to-gain mapping, before the port drives them.
- **Measurement on a device.** Nothing here has been captured on the 4S. The bias's effect on the exposure, the time between the
  stills and the photos' pixels are unmeasured.
- **Overlapping requests.** A second request asked while a bracket runs starts its own still at once; the output's queue does not
  wait for a capture's completion. What the still image output does with two captures in flight from one connection is not
  measured here.

## The emulator

tests/backports/emulate/photobracket: the probe (app/main.m) checks the factories, members, refusals, the output's values and
refusals, the bracket's callback order, each photo's member and count, a single capture through the 10.0 callback, and the
AVCapturePhoto object from a BGRA buffer, a JPEG and an error. The emulator's captures end in AVFoundationErrorDomain -11800
(facts/AVFoundation/AVCapturePhotoOutput.md), so the bracket's photos are error photos there: the probe checks the sequence of
callbacks and the members, not pixels.

Result (iPhone4,1 at 6.1.3, 10B329, `run-app.sh` through heavy.sh; run `.agent-work/runs/v-impl-avf-1/photobracket-20261017-110255`):
25 of 30 checks pass: the factories, the members, the refusals, the output's values (the maxBracketedCapturePhotoCount port
answer, lens stabilization) and the photo objects (BGRA buffer, CGImage, JPEG file, metadata, error photo). Four fail, all of
them the camera: the emulator image reports 0 video devices (`camera-present`), so `camera-input`, `session-built` and
`connection-present` fail. The capture checks, which are the bracket's callback order, each photo's member and count, and the
single 10.0 capture, do not run on a session that has no camera: the bracket capture is NOT verified on the emulator. The
-11800 captures described above were not reproduced by this run, which had no camera to capture with. Re-running needs an
emulator image that presents a camera device; the probe then runs the capture checks unchanged.
