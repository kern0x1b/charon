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

## What the gate does not see in these classes

The package gate cannot tell a member of these three classes that works from one that does not, so every member
needs a test of its own (host oracle and device). Read in `modules/apple/backports.lua` at 7bb1720d:

- `check_registry` counts a member row as built when its class is built: `built = built or (owner and
  found.classes[owner])` (line 782). A row `AVCapturePhotoSettings.depthDataDeliveryEnabled` listed `implemented`
  passes whether the library answers the selector or not, and so does a row naming a member the class never had.
- `surface()` records members only for categories on a class the library does not define (`if not class.image and
  not ours[name]`, line 597), and `known()` takes any member of a listed class as described (line 741): a member
  the port adds to its own class needs no row at all to pass.
- A property the SDK header declares on the class and the port leaves unimplemented is synthesized by the compiler:
  a getter answering zero and a setter nobody reads, both real methods in the binary. Even a check that looked for
  the selectors would pass them. Measured 2026-09-24 on the gate's `libAVFoundationBackports.dylib` with
  `otool -ov`: 28 such properties on `AVCapturePhotoSettings` (`depthDataDeliveryEnabled`,
  `embeddedThumbnailPhotoFormat`, `highResolutionPhotoEnabled`, `livePhotoMovieFileURL`, ...), and until the bfw2
  band's change every member but `uniqueID` of `AVCaptureResolvedPhotoSettings`.

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

## The resolved settings

`AVCaptureResolvedPhotoSettings` (`AVCaptureResolvedPhotoSettings.m`) is made by
`-capturePhotoWithSettings:delegate:` before `-captureOutput:willBeginCaptureForResolvedSettings:` and is the one
object every callback of the request gets, as on 10.0. Until 2026-09-24 the class carried `uniqueID` alone, and
because its other members are properties the SDK header declares on the class itself, the compiler synthesized each
to a zero: the built library answered `photoDimensions` 0x0, `flashEnabled` NO, `expectedPhotoCount` 0 (read from
the gate's `libAVFoundationBackports.dylib` with `otool -ov`: an ivar and a getter per header property). The one
method of the class, `-dimensionsForSemanticSegmentationMatteOfType:`, was an unrecognized selector. Now every member
answers explicitly, and one registry row names each.

- `photoDimensions`: the dimensions of the video port's format (`connection.inputPorts[0].formatDescription`) as the
  session runs it, read before the capture. Measured on an iPhone 4S, 6.1.3 (a probe outside the tree, the log
  `device-4s-resolvedmeasure.log` of the bfw2 band): for all eight session presets the camera offers (Photo
  3264x2448, High and 1920x1080, 1280x720, iFrame 960x540, 640x480, Medium 480x360, Low 192x144) the JPEG still, the
  32BGRA still and the JPEG still at a 2x scale and crop come at exactly the port's dimensions, and the port's do not
  change across the capture. A port can have no format yet: in `photooutput10.m` on the 4S, the first capture after the
  photo output joined a running session found none (the release's own still image output had captured in that session
  just before). The settings are then resolved from the still's own format when it comes, and
  `-captureOutput:willBeginCaptureForResolvedSettings:` is sent then, before the other callbacks: the order of the
  header holds and no callback is told dimensions that are not the photo's, and only the moment of willBeginCapture
  differs from 10.0's, which sends it before the shutter.
- `previewDimensions`: the preview's longest side (above) applied to `photoDimensions` with its aspect ratio, before
  the capture; the preview buffer is made at exactly these. 0x0 with no preview format.
- `flashEnabled`: NO when the camera has no flash or its flash mode is Off once the request's mode is set on it.
  Otherwise the still's own answer: bit 0 ("flash fired") of the Exif Flash tag the release attaches to the still's
  sample buffer, and the settings are resolved, and willBeginCapture sent, when the still comes, as when the port has
  no format (above). The camera's `flashActive` ("When the flash is active, it will flash if a still image is
  captured", iOS 5) cannot answer before the capture. Measured on an iPhone 4S, 6.1.3, 2026-09-24, with the session
  running and no still captured (a probe outside the tree, `device-4s-flashmeasure.log` of the bfw2 band): with the
  mode set to Auto, `flashActive` read right after `-unlockForConfiguration` is NO, and its KVO change to YES comes
  28 ms later (the scene was dark); set to On, it is YES at once; set to Off, NO at once. An earlier version read
  `flashActive` right after setting the mode, and would have said NO for an Auto flash that fires. The flash has
  never been fired for a measurement, so the Exif branch (Auto/On) has not run on a device, in either direction: the
  NO measured below is the Off branch, answered before the still without reading its Exif.
- `stillImageStabilizationEnabled`: the still image output's `isStillImageStabilizationActive` where it has it (7.0
  on); NO on 6.x, which has no stabilization.
- `uniqueID`: the settings' own.
- `embeddedThumbnailDimensions` (11.0): the thumbnail the capture embeds when the settings ask for one ("The
  embedded thumbnail", below): the photo's dimensions with its aspect ratio and, as the longest side, the larger of the
  format's `AVVideoWidthKey` and `AVVideoHeightKey`, or 160 when it gives neither; never more than the photo. 0x0 when
  none is asked (the header).
- `rawPhotoDimensions`, `livePhotoMovieDimensions` (10.0.1), `rawEmbeddedThumbnailDimensions`,
  `portraitEffectsMatteDimensions` (12.0), `-dimensionsForSemanticSegmentationMatteOfType:` (13.0): 0x0, the header's
  answer for each when the capture did not request it, and what this capture delivers: the still image output's own
  photo, with none of them. A request for one is refused at capture ("The photo output", below).
- `expectedPhotoCount` (11.0): 1. The header counts calls of `-captureOutput:didFinishProcessingPhoto:error:`; a
  request here delivers its one photo through the 10.0 callback with sample buffers, once.
- `dualCameraFusionEnabled` (10.2), `virtualDeviceFusionEnabled` (13.0): NO. The class is carried only below 10.0.1,
  where every camera is a single one.
- `redEyeReductionEnabled` (12.0): NO. Red-eye reduction came to capture in 12.0: `autoRedEyeReductionEnabled`,
  `isAutoRedEyeReductionSupported` and `isRedEyeReductionEnabled` are in no string of the arm64 cache of 11.0 and all
  in 12.0's (the control, `photoDimensions`, is in both).
- `photoProcessingTimeRange` (13.0): `kCMTimeRangeInvalid`. The release makes no estimate; an invalid range says so,
  where a zero range would say the photo takes no time.
- `contentAwareDistortionCorrectionEnabled` (14.1): NO, never applied here.

The ladder of the members, by selector string in the caches: `photoDimensions`, `rawPhotoDimensions`,
`livePhotoMovieDimensions` and `capturePhotoWithSettings:delegate:` are in no string of the armv7 cache of 9.3.6 and
in the arm64 cache of 10.0.1; `isDualCameraFusionEnabled` first appears at 10.2. `expectedPhotoCount`, which the header
places at 11.0, is already a string of the 10.0.1 cache; that does not say which class carries it, so its row keeps
the header's 11.0.

## What differs from the release, honestly

- The output is an `AVCaptureStillImageOutput` (above): `isKindOfClass:[AVCaptureStillImageOutput class]`
  answers `YES` and it responds to the still image output's own methods, where 10.0's
  `AVCapturePhotoOutput` sits directly under `AVCaptureOutput`. An application that looks through
  `session.outputs` for a still image output finds the photo output, and capturing from it works.
- `AVCapturePhotoOutput.availableRawPhotoPixelFormatTypes` is always an empty array: RAW capture has
  no path on this release's sensor pipeline.
- The preview photo is drawn by the port. `AVCapturePhotoSettings.availablePreviewPhotoPixelFormatTypes`
  is the host's `[420f, 420v, 32BGRA]`, in its order. At capture a `previewPhotoFormat` whose
  pixel format is not in that list, or that gives a width without a height or the other way round,
  raises `NSInvalidArgumentException` (the text is the port's). Otherwise the captured still is decoded
  (a JPEG through ImageIO's thumbnail, which decodes at the reduced size; an uncompressed buffer through
  CoreImage) and drawn into an IOSurface-backed 32BGRA pixel buffer, the format CoreGraphics draws into; for 420v and
  420f that picture is converted to bi-planar 4:2:0 YCbCr by ITU-R BT.601 (luma 0.299 R + 0.587 G + 0.114 B, video
  range 16...235 and 16...240, full range 0...255, each chroma sample the mean of its two by two pixels) and the
  buffer says its matrix (`kCVImageBufferYCbCrMatrix_ITU_R_601_4`). It is delivered with the still's presentation
  time as `previewPhotoSampleBuffer`. Its size follows the header: "Width and height are
  only honored up to the display dimensions. If you specify a width and height whose aspect ratio
  differs from the RAW or processed photo, the larger of the two dimensions is honored and aspect ratio
  of the RAW or processed photo is always preserved": the longest side is the larger of the two asked,
  held to the display's longest side in pixels, the display's when none is asked, and never more than
  the still's own. A preview that cannot be made is said in the log, and the photo comes without it.
- `-isFlashScene` is `NO` "unless you set `photoSettingsForSceneMonitoring` to a non-nil value" (the header). Setting
  them puts their flash mode on the camera, as a capture does, and a capture puts it back after its own; with Auto the
  answer is the camera's own `flashActive`
  ("When the flash is active, it will flash if a still image is captured", iOS 5), `NO` with On or Off. Nothing fires
  until a capture.
- `-livePhotoCaptureEnabled` is `NO`, and setting it to `YES` raises `NSInvalidArgumentException` with the host's text
  for a device without Live Photo: `livePhotoCaptureSupported` is `NO`, as no movie is paired to a still on this
  release.
- `-highResolutionCaptureEnabled` is stored, and from 8.0 turns the still image output's own
  `highResolutionStillImageOutputEnabled` on and off. Before 8.0 the still image output takes a still at the size its
  session's preset gives, and there is no other size to ask for.

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

iPhone 4S, 6.1.3, 2026-09-24, with the resolved settings (`AVCaptureResolvedPhotoSettings.m` built in): 94 checks, 0
failed. Every capture hands one resolved settings object to its four callbacks in the header's order, under the
request's unique ID; its photo dimensions are the photo's (3264x2448) and its preview dimensions the preview's (960x720,
160x120, 320x240, 0x0 with none), both already at willBeginCapture; RAW and Live Photo 0x0; no stabilization; the flash
not enabled with the flash Off. The camera's flash is held Off for the whole run and put back to its mode after; the
captures with the flash On and Auto (`photooutput <log> flash-on`; Auto in the dark fires it as On) fire the flash of a
phone someone may be using and were not run, so `flashEnabled` YES is not measured. With `flashEnabled` taken from the
still's Exif (above), the same run on the same 4S the same day: 96 checks, 0 failed; the still captured with the flash Off carries Exif Flash 16 ("did not fire"),
and its resolved settings say NO. That NO is the Off branch, answered before the still without reading the Exif: the run
shows that the release attaches the tag and that the port's keys find it, not the Exif branch, which only the captures
with the flash On and Auto of `flash-on` reach and which has not run on a device.

With every member of the settings and the output (the bfw3 band), `photooutput10` on the same 4S, 2026-09-24, the flash
held Off: 160 checks, 0 failed (`bfw3/.agent-work/runs/capture4s/device-4s-photooutput-4.log`). Every capture calls
its five callbacks in the header's order, `willCapturePhoto` second. A thumbnail asked with no size resolves to
160x120 and one asked 320x320 to 320x240 for the 3264x2448 photo; each is in IFD1 of the delivered photo's own JPEG at
those dimensions, read by the Exif layout, with the host's tags, and the port's JPEG of the photo keeps it; the
release's `+jpegStillImageNSDataRepresentation:` of it has no IFD1 (as on the host). With the 960x720 preview given,
the port's JPEG holds a 160x120 thumbnail. The settings' Exif user comment is in both JPEGs. A RAW photo, a Live Photo
movie, depth data, quality 3 over the output's 2, a unique ID used twice, a thumbnail width without a height and a
delegate without the sample buffer callback each raise `NSInvalidArgumentException`; prepared settings are answered YES once with the session running;
`availablePhotoCodecTypes` is `[jpeg]`. With scene monitoring for Auto the camera's mode is Auto and `isFlashScene`
equals `flashActive`, a capture with the flash Off in between leaves the camera back on Auto, and with Off the camera is
Off and `isFlashScene` NO; `flashActive` was NO in that scene,
and the YES answer is not measured. The 420v and 420f previews came after this run; `photooutput10` checks their format,
size and BT.601 luma against the photo (with the upside-down control), and that run has not been made yet.

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

## The photo settings

Since the bfw3 band's change every member of `AVCapturePhotoSettings` in the 16.4 header (38 properties, the six
constructors, `NSCopying`) has an accessor or a method of the port's own, with an explicit `_charon…` ivar: the host
oracle `tests/backports/host/photosettings/run.sh` reads the member list from clang's AST of the header, checks each
against the host class's type encoding, and refuses any ivar synthesized for a declared property. The same oracle
refuses the class as `7bb1720d` carried it (390 failures), its negative control.

Measured on the host (macOS 27.0 Catalyst, the real class, no camera; `bfw3/.agent-work/runs/probe/`, `defaults.log`,
`gaps.log`, `aliases.log`, `metakeys.log`, summary in `NOTES.md`) and held by the oracle, port against host:

- Defaults: format `{AVVideoCodecKey: jpeg}`, processedFileType `public.jpeg`, flash Off, quality Balanced (2), fusion
  YES, `embeds*` YES, `depthDataFiltered` YES, the rest NO, metadata `{}`, Live Photo codec `avc1`, the Live Photo movie
  metadata one content identifier item of the settings' own.
- The constructors: `photoSettingsWithFormat:` raises for `{}` ("source passthru (empty dictionary) is not
  supported"), for neither key and for both; a codec gives its file type (jpeg JPEG, hvc1 HEIC, avc1 none), a pixel
  format TIFF. The RAW constructors raise for a pixel format that is not RAW ("Unrecognized raw pixel format type"); a
  Bayer one gives quality Speed and no fusion, Apple ProRAW Balanced with fusion. `-copy` keeps the unique ID,
  `+photoSettingsFromPhotoSettings:` takes a new one; both keep every setting.
- The set-time checks, with the host's texts: metadata keys outside the CGImageProperties top level, quality outside
  1..3, a preview or thumbnail format without the key it needs or with a value not offered, and the Live Photo content
  identifier item given by the application. Everything else is stored and checked at capture.
- The two fusion flags share one value; `setHighResolutionPhotoEnabled:` puts `maxPhotoDimensions` back to 0x0.

Named divergences, each a check that fails if the host ever stops answering so:

- `autoStillImageStabilizationEnabled` is YES by default, the header's default; the Mac answers NO. It acts at capture
  from 7.0 (above).
- `availableEmbeddedThumbnailPhotoCodecTypes` is `[jpeg]` for a JPEG format, as on the host, and `[]` for a pixel format
  or HEVC, where the host answers `[jpeg]` and `[hvc1, jpeg]`: the port delivers an uncompressed photo as a pixel
  buffer, with no file to hold a thumbnail, and makes no HEIC. `availableRawEmbeddedThumbnailPhotoCodecTypes` is `[]`:
  no RAW photo is taken here.
- `setMetadata:` refuses `{MakerApple}`, which the host takes: its constant is not in 6.1.3's ImageIO.

## The photo output

`CharonPhotoOutput` answers every member of the header's `AVCapturePhotoOutput` and its category
`AVCapturePhotoOutputDepthDataDeliverySupport`, checked against the host by the same oracle.

- Without a camera behind it, as the host with no session answers: every `*Supported` NO, the `available*` lists empty,
  `supportedFlashModes` `[Off]`. With the 4S camera (`photooutput10`): `supportedFlashModes` Off, On and Auto,
  `availablePhotoCodecTypes` `[jpeg]`, the still image output's own codecs. `availablePhotoFileTypes` is JPEG for its
  JPEG codec and TIFF for its pixel formats (not checked on the device).
- The setters of features no camera of these releases has (depth, portrait matte, segmentation mattes, Live Photo,
  its suspension and trimming, dual photo, constituent photos, content-aware correction, Apple ProRAW) raise
  `NSInvalidArgumentException` for YES with the host's texts, as a device without the feature does.
  `maxPhotoQualityPrioritization` is stored and raises outside 1..3 (the host's text); `maxPhotoDimensions` goes through
  the camera's `activeFormat` (7.0) and otherwise raises the host's text.
- `photoSettingsForSceneMonitoring` holds a copy, and answers one (the host does). `setPreparedPhotoSettingsArray:`
  stores copies and calls the handler with YES once the session runs, at once when it already does; a later call
  answers the earlier handler NO (the host's answer).
- `-capturePhotoWithSettings:delegate:` checks the request against the header's rule list before anything is
  captured and raises `NSInvalidArgumentException` for each broken rule: first the host's own "No active and enabled
  video connection", then a unique ID used twice, a RAW format, a format, file type or quality the output does not
  offer, a flash mode not supported, a preview or thumbnail size with a width and no height or the other way round
  ("you must specify both width and height", the header), a Live Photo movie without Live Photo capture, a maximum size above the output's,
  depth, mattes, calibration, dual and constituent photos and content-aware correction asked where the output cannot
  enable them, and a delegate without
  `-captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:`
  (the header's 10.0 rule: the photo is delivered through that callback alone, and a delegate without it got no photo,
  silently, until this change). The texts after the first are the port's own, each naming its rule: the host cannot
  show them without a camera.
- The capture takes "a defensive copy" of the settings (the header), puts their flash mode on the camera, enables
  stabilization from 7.0 when asked and the quality is not Speed, merges their metadata into the dictionaries the
  release attaches to the still (the settings' values win), so both JPEGs of the photo carry it, and sends
  `-captureOutput:willCapturePhotoForResolvedSettings:` after willBeginCapture: right before the still image output's
  capture when the settings are resolved before it, right after willBeginCapture when they are resolved from the still.
- `+JPEGPhotoDataRepresentationForJPEGSampleBuffer:previewPhotoSampleBuffer:` is the release's own JPEG of the sample
  with its attachments, and a thumbnail (next section); a sample that is not a JPEG raises the host's "Not a jpeg sample
  buffer". `+DNGPhotoDataRepresentationForRawSampleBuffer:previewPhotoSampleBuffer:` raises the host's "Unrecognized
  raw format" for a sample that is not RAW, and is nil for one that is: no RAW sample comes from this release.

## The embedded thumbnail

The Exif standard keeps a thumbnail in IFD1 of the TIFF block of the JPEG's APP1 "Exif" segment, as a JPEG (Compression
6) found by JPEGInterchangeFormat and JPEGInterchangeFormatLength. ImageIO writes one only from 8.0
(`kCGImageDestinationEmbedThumbnail`); the format is open, so the port writes the segment itself
(`CharonJPEGWithThumbnail` in `AVCapturePhotoOutput.m`): it keeps the TIFF block as it is, appends IFD1 and the
thumbnail, and links IFD1 from IFD0; a JPEG with no Exif segment gets one. A segment longer than 65535 bytes cannot be
written: the thumbnail is then written again at ImageIO's lowest quality, and when that does not fit either, the
photo comes without one, the log says so, and `embeddedThumbnailDimensions` is 0x0. So that it can say so, settings
that ask for a thumbnail are resolved, and willBeginCapture sent, when the still comes, as when the flash may fire.

What the host writes, measured with `bfw3/.agent-work/runs/probe/thumbs.m` (`thumbs.log`): the host's
`+JPEGPhotoDataRepresentationForJPEGSampleBuffer:previewPhotoSampleBuffer:` puts the preview into IFD1 with Compression
6, XResolution and YResolution 72/1, ResolutionUnit 2, the offset and the length, and the thumbnail JPEG has no APPn
segment. It is the preview no longer than 160 on its longest side, never enlarged: 32x24 stays 32x24; 160x120,
320x240, 640x480 and 1600x1200 all give 160x120; 200x200 gives 160x160, 120x160 stays. With no preview there is no
IFD1, and a thumbnail the sample's own JPEG carries is dropped by the repackaging. The port writes the same tags and
sizes, and the oracle compares the two for both photo sizes and every preview above. (On the host,
`CGImageSourceCreateThumbnailAtIndex` with no options answers the full image for a file with no thumbnail, so the
oracle and the device test read IFD1 by the Exif layout, `tests/backports/device/jpeg-exif.h`.)

At capture, settings with `embeddedThumbnailPhotoFormat` (a JPEG photo only, above) get the still drawn at the resolved
`embeddedThumbnailDimensions` embedded in the photo's own JPEG "before calling the AVCapturePhotoCaptureDelegate" (the
header): the delegate's photo sample buffer is the still's, with the same format, timing and attachments, whose data
is that JPEG. With no size asked the longest side is 160, the host's own thumbnail size above. The release's
`+jpegStillImageNSDataRepresentation:` of that sample does not keep the thumbnail, as the host's repackaging does not;
the port's `+JPEGPhotoDataRepresentationForJPEGSampleBuffer:previewPhotoSampleBuffer:` with no preview puts it back,
where the host keeps none (a named divergence: on the host no capture can put one there).

