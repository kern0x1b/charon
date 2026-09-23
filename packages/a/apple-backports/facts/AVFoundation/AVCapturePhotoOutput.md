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

## Why the output is a still image output

On this release `AVCapturePhotoOutput` is an `AVCaptureStillImageOutput` itself: the class the port
defines under that name has the release's still image output as its superclass, so
`-[AVCaptureSession addOutput:]` takes it, builds it into the graph and runs it as the output it is,
and `-outputs`, `-canAddOutput:` and `-removeOutput:` are the release's own, unchanged. The SDK
declares the class above `AVCaptureOutput`, so `AVCapturePhotoOutput.m` declares the implementation
under a name of its own (`CharonPhotoOutput`) with clang's `objc_runtime_name("AVCapturePhotoOutput")`:
the class, its metaclass and their `_OBJC_CLASS_$_`/`_OBJC_METACLASS_$_` symbols carry the API's
name, which is all an application or the registry check ever sees (`nm -m` of the probe:
`_OBJC_CLASS_$_AVCapturePhotoOutput` in `__objc_data`, `AVCaptureStillImageOutput` undefined as its
superclass).

The first version was a facade: an `AVCaptureOutput` instance holding a still image output of its own,
with `-addOutput:`/`-canAddOutput:`/`-removeOutput:`/`-outputs` of `AVCaptureSession` exchanged to put
the held output into the session and to answer the facade back from `-outputs`. No capture through it
ever finished on 6.1.3. Measured on an iPad 2 (`tests/backports/device/photooutput10.m` and a scratch
probe, 2026-09-23):

- the control, the release's own `AVCaptureStillImageOutput` in the same session with the Photo preset,
  captured a 960x720 JPEG twice before the facade and once after it;
- through the facade, the first capture ended in `AVFoundationErrorDomain` -11800 (underlying OSStatus
  -12780) and the next ones never called back; on an iPhone 4S (an earlier run of the same probe) no capture gave a photo. The zoom's hooks were not in
  that probe, and the iPad 2 has no flash, so neither was the cause;
- 6.1.3's `AVCaptureSession` calls its own `-outputs` three times from inside AVFoundation while
  `-startRunning` builds the graph, and again each time a capture posts its notifications (a counting
  `-outputs` with `backtrace`/`dladdr`), so the exchanged `-outputs` handed the release the facade in
  place of the output it had built;
- with only the `-outputs` exchange taken back out, the same facade's held output captured with a
  buffer.

A class of its own beside the release's output can therefore not be listed in `-outputs` without the
release reading it there; the still image output subclass is what lets `session.outputs` hold the very
object the application added. The four exchanged methods and the facade's `-init` through
`objc_msgSendSuper` are gone with it.

## What fires for real

- `-capturePhotoWithSettings:delegate:` applies `settings.flashMode` to the real device (through
  the real, iOS-4.0-era `-isFlashModeSupported:`/`-flashMode` pair, still present and functional
  on 6.1.3 despite being deprecated in the SDK header at 10.0) and
  `settings.autoStillImageStabilizationEnabled` onto
  `automaticallyEnablesStillImageStabilizationWhenAvailable` where the release has it, and
  `settings.format` onto `outputSettings` (a JPEG, `AVVideoCodecJPEG`, when the settings have no
  format, so a capture never inherits the format of the one before it), then captures for real through
  its own `-captureStillImageAsynchronouslyFromConnection:completionHandler:`, delivering the real
  `CMSampleBufferRef` to the delegate.
- Still image stabilization arrived on `AVCaptureStillImageOutput` in 7.0 (the armv7 caches: 6.1.3's
  still image output has no stabilization selector, 7.0's has the four). An earlier version of this
  port set it unconditionally, "real since iOS 5.0", and every capture on 6.1.3 died of an unrecognized
  selector (`tests/backports/device/photooutput10.m`, 2026-09-23); retracted. On 6.x the setting is
  kept and enables nothing, what it does on a device without the feature.
- `-availablePhotoPixelFormatTypes` is the output's own `availableImageDataCVPixelFormatTypes`
  (`420f`, `420v`, `32BGRA` on an iPad 2).
- `-supportedFlashModes` queries the real device behind the connection for real, not a fixed list.
- `-photoSettingsWithFormat:`'s format dictionary is carried through and applied to the
  output's `outputSettings` at capture time.
- `AVCaptureResolvedPhotoSettings.uniqueID` matches the `AVCapturePhotoSettings.uniqueID` used to
  initiate the request, per Apple's own documented contract - real, monotonically-incrementing
  storage, not a placeholder.

## What differs from the release, honestly

- The output is an `AVCaptureStillImageOutput` (above): `isKindOfClass:[AVCaptureStillImageOutput class]`
  answers `YES` and it responds to the still image output's own methods, where 10.0's
  `AVCapturePhotoOutput` sits directly under `AVCaptureOutput`. An application that looks through
  `session.outputs` for a still image output finds the photo output, and capturing from it works.
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

## Measured on device

`tests/backports/device/photooutput10.m`, built with `AVCapturePhotoOutput.m` and the zoom's files
(`AVCaptureDevice+VideoZoom7.m`, `CharonAVCapture.m`, `AVCaptureDevice+ActiveFrameDuration.m`), as
the library carries them. iPad 2, 6.1.3: 27 checks, 0 failed. The class keeps its name and
`session.outputs` holds it, and loses it on removal. A photo alone comes as a 960x720 JPEG. The
previews come in 32BGRA at 960x720 (the photo's size, under the display's 1024), at 160x120 when
160x160 is asked, and held to the display past it. An uncompressed 32BGRA photo gets its preview
through CoreImage at 320x240. The next settings without a format give a JPEG again. With a 2x zoom,
the photo output's still connection carries 2.00 as its scale and crop, and the zoomed capture comes
with its preview. Each preview is within 0.005 levels of the probe's own drawing of the photo at the
preview's size, and further from the photo turned upside down (0.96 to 1.91 levels). The control is
weak on the iPad: its camera saw a dark, nearly even scene (mean about 10 of 255, spread 1.6 to 2.8).
Still, a preview drawn empty would have been about 10 levels off, which the check (under 6) refuses.

Not measured: Telegram's own `-captureOutput:didFinishProcessingPhotoSampleBuffer:...` with a `nil`
`bracketSettings` (documented `nullable` in the header).

## Owner of `availablePreviewPhotoPixelFormatTypes`, corrected

The first version of this port defined `-availablePreviewPhotoPixelFormatTypes` on
`AVCapturePhotoOutput`. `apple.objc.inventory()` over the armv7 cache ladder finds that selector on
`AVCapturePhotoSettings` from 10.0.1 and on `AVCapturePhotoOutput` in no release up to 10.3.4 (a
nonsense selector as negative control, `-isFlashScene` on the output as positive); the corpus row
(rank 634) names `AVCapturePhotoSettings` too. The method now lives on `AVCapturePhotoSettings`,
the registry key with it. Every other selector of these classes first appears at 10.0.1, the release
their registry rows carry.
