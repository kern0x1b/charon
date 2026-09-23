# AVCapturePhotoOutput, iOS 10.0.1

Ranks 16/17 of `coordination/corpus/crash-demand-top.tsv`, `LOAD-FAIL`, `class_confirmed` against
both `telegram` and `session`'s own trees - the densest single pair in this pass after
`AVFoundation`'s own top cluster.

## What was checked before writing code

`apple.objc.inventory()` against the armv7 shared cache of 6.1.3 found none of
`AVCapturePhotoOutput`, `AVCapturePhotoSettings` or `AVCaptureResolvedPhotoSettings` under any
name - a genuine gap, not a name already claimed by something else. `AVCaptureStillImageOutput`,
the class the real header documents the whole modern API as sitting above, is real and exported
on this release, and is already a working `AVCaptureOutput` subclass. A `grep` of this tree's own
`.m` files found no orphaned implementation already carrying a demanded selector.

Ladder-walked with the same cache-by-cache inventory `tools/release-split.lua` uses, not read from
the SDK header's availability attribute (which names when Apple *published* the symbol, not when
it first exports): all three classes first export at 10.0.1, not the header's bare "10.0".

## The delegate design decision, made from real evidence

`-capturePhotoWithSettings:delegate:` needs to call back into the delegate the host app supplies.
Modern code implements `-captureOutput:didFinishProcessingPhoto:error:`, which needs a real
`AVCapturePhoto` object this port does not build (out of scope: no demand row names it, and
building one would need image-processing machinery this release does not have). The alternative is
the original, `CMSampleBufferRef`-based callback from iOS 10 itself, before `AVCapturePhoto`
existed - deprecated in 13.0, never removed.

Rather than guess which one Telegram's binary actually relies on, `coordination/corpus/defcache/telegram.json`
was checked directly: Telegram defines **both**
`-captureOutput:didFinishProcessingPhoto:error:` and
`-captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:`.
The sample-buffer variant is the one this port can deliver for real without inventing
`AVCapturePhoto`, and Telegram's own binary already ships it as a working fallback path for
pre-11 devices - this is the same code Telegram uses when the modern callback isn't the one being
exercised, not a code path invented for this port.

## Why a facade, not a real subclass wired into the session

`AVCaptureOutput` is not meant to be handed to `-[AVCaptureSession addOutput:]`'s private setup as
a client subclass - the existing precedent in this tree for absent `AVCaptureOutput`-family
surface (`AVCaptureDataOutputSynchronizer.m`) only *observes* real, existing outputs; it never
injects a new one into the session's own graph. `AVCapturePhotoOutput` has to be addable to a
session, so it is a facade: a real `AVCaptureOutput` subclass instance the caller holds, wrapping
an internally-held real `AVCaptureStillImageOutput` that never has its own `-init` special-cased -
`AVCaptureOutput`'s inherited `-init` runs the same way any subclass's does, and the facade is
never itself passed into `AVCaptureSession`'s private graph, so nothing in that private machinery
ever sees or depends on the facade's own (otherwise ordinary) `AVCaptureOutput` ivars.

`-[AVCaptureSession addOutput:]`/`-canAddOutput:`/`-removeOutput:`/`-outputs` are swizzled (the
same interception pattern `CharonPushBridge` and `CharonRemoteCommandBridge` already use in this
tree) to detect a facade and substitute its real `AVCaptureStillImageOutput` on the way in, and to
map the real object back to its facade on the way out (`-outputs`), via a
`weakToWeakObjectsMapTable` keyed by the real output - so a caller doing
`[session.outputs containsObject:photoOutput]` with the facade it originally passed to
`-addOutput:` still gets the answer it expects. The genuine graph node the session ever touches is
always the real, on-release `AVCaptureStillImageOutput`.

## What fires for real

- `-capturePhotoWithSettings:delegate:` applies `settings.flashMode` to the real device (through
  the real, iOS-4.0-era `-isFlashModeSupported:`/`-flashMode` pair, still present and functional
  on 6.1.3 despite being deprecated in the SDK header at 10.0) and
  `settings.autoStillImageStabilizationEnabled` onto
  `AVCaptureStillImageOutput.automaticallyEnablesStillImageStabilizationWhenAvailable` where the
  release has it, then captures for real through
  `-captureStillImageAsynchronouslyFromConnection:completionHandler:`, delivering the real
  `CMSampleBufferRef` to the delegate.
- Still image stabilization arrived on `AVCaptureStillImageOutput` in 7.0 (the armv7 caches: 6.1.3's
  still image output has no stabilization selector, 7.0's has the four). An earlier version of this
  port set it unconditionally, "real since iOS 5.0", and every capture on 6.1.3 died of an unrecognized
  selector (`tests/backports/device/photooutput10.m`, 2026-09-23); retracted. On 6.x the setting is
  kept and enables nothing, what it does on a device without the feature.
- `-availablePhotoPixelFormatTypes` forwards to the real
  `AVCaptureStillImageOutput.availableImageDataCVPixelFormatTypes`.
- `-supportedFlashModes` queries the real device behind the connection for real, not a fixed list.
- `-photoSettingsWithFormat:`'s format dictionary is carried through and applied to the real
  output's `outputSettings` at capture time.
- `AVCaptureResolvedPhotoSettings.uniqueID` matches the `AVCapturePhotoSettings.uniqueID` used to
  initiate the request, per Apple's own documented contract - real, monotonically-incrementing
  storage, not a placeholder.

## What differs from the release, honestly

- `AVCapturePhotoOutput.availableRawPhotoPixelFormatTypes` is always an empty array: RAW capture has
  no path on this release's sensor pipeline.
- The preview photo is drawn by the port. `AVCapturePhotoSettings.availablePreviewPhotoPixelFormatTypes`
  is `[32BGRA]`, the format CoreGraphics draws into directly. At capture a `previewPhotoFormat` whose
  pixel format is not in that list, or that gives a width without a height or the other way round,
  raises `NSInvalidArgumentException` (the text is the port's). Otherwise the captured still is decoded
  (a JPEG through ImageIO's thumbnail, which decodes at the reduced size; an uncompressed buffer through
  CoreImage) and drawn into an IOSurface-backed 32BGRA pixel buffer, delivered with the still's
  presentation time as `previewPhotoSampleBuffer`. Its size follows the header: "Width and height are
  only honored up to the display dimensions. If you specify a width and height whose aspect ratio
  differs from the RAW or processed photo, the larger of the two dimensions is honored and aspect ratio
  of the RAW or processed photo is always preserved": the longest side is the larger of the two asked,
  held to the display's longest side in pixels, the display's when none is asked, and never more than
  the still's own. A preview that cannot be made is said in the log, and the photo comes without it.
- `-isFlashScene` always answers `NO`. Apple's own header already documents this as the correct
  default "unless you set `photoSettingsForSceneMonitoring` to a non-nil value" - this port carries
  no scene-monitoring pipeline, so that property is never non-nil, and `NO` is the release's own
  documented answer for that state, not a fabricated one.
- `-livePhotoCaptureEnabled` always answers `NO`, and setting it to `YES` throws
  `NSInvalidArgumentException` - the same exception real `AVCapturePhotoOutput` throws when
  `livePhotoCaptureSupported` is `NO`, which it unconditionally is here: no motion/video pipeline
  paired to still capture exists on this release.
- `-highResolutionCaptureEnabled` is real, settable `BOOL` storage that this port always honors for
  free: the underlying `AVCaptureStillImageOutput` already captures at the device's full
  active-format resolution regardless of this flag, unlike a video data output's preview-resolution
  stream, so there is no lower-resolution path to opt out of.

## What is not proven

Not measured on device this pass - the session-integration swizzle (`addOutput:`/`canAddOutput:`/
`removeOutput:`/`outputs`) and the facade pattern are host-syntax-checked and gate-verified only.
A device pass would confirm: that a real `AVCaptureSession` accepts the substituted
`AVCaptureStillImageOutput` from inside the swizzled `-addOutput:` the same way it would if the app
had passed that real class directly (expected, since the session never sees anything but a real,
on-release class, but not yet exercised end-to-end with a live camera and a real delegate); and
that Telegram's own `-captureOutput:didFinishProcessingPhotoSampleBuffer:...` implementation
handles a `nil` `previewPhotoSampleBuffer` and `nil` `bracketSettings` gracefully (expected, since
both are documented `nullable` in Apple's own header, but not measured against Telegram's actual
code).

## Owner of `availablePreviewPhotoPixelFormatTypes`, corrected

The first version of this port defined `-availablePreviewPhotoPixelFormatTypes` on
`AVCapturePhotoOutput`. `apple.objc.inventory()` over the armv7 cache ladder finds that selector on
`AVCapturePhotoSettings` from 10.0.1 and on `AVCapturePhotoOutput` in no release up to 10.3.4 (a
nonsense selector as negative control, `-isFlashScene` on the output as positive); the corpus row
(rank 634) names `AVCapturePhotoSettings` too. The method now lives on `AVCapturePhotoSettings`,
the registry key with it. Every other selector of these classes first appears at 10.0.1, the release
their registry rows carry.
