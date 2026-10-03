# The two 11.0 sample-buffer render classes: the substrate is there, and the oracle is not on this machine

Two rows of `registry/AVFoundation/absent_AVFoundation.json`, `AVSampleBufferAudioRenderer` and
`AVSampleBufferRenderSynchronizer`, plus the protocol `AVQueuedSampleBufferRendering` named in
`Release11.md`. They stay `absent` and this page says what is measured, because what the row's `reason`
implied - that no 6.x buffer path can time a `CMSampleBuffer` - is wrong, and the correction matters more
than the row's status does.

## The substrate is on 6.1.3, measured from the images' own export tries

`xmake l tools/image-exports.lua 6.1.3 armv7 <image> <substring>`, which reads each image's export trie
rather than searching the cache's strings:

| symbol | image | on 6.1.3 armv7 |
| --- | --- | --- |
| `_AudioQueueNewOutput`, `_AudioQueueAllocateBuffer`, `_AudioQueueEnqueueBuffer`, `_AudioQueueDispose`, `_AudioQueueStart`, `_AudioQueueStop`, `_AudioQueueSetProperty`, `_AudioQueueGetProperty` | AudioToolbox | **all exported** (337 exports, 43 matching `AudioQueue`) |
| `_CMTimebaseCreate`, `_CMTimebaseSetTime`, `_CMTimebaseGetTime`, `_CMTimebaseSetRate` | CoreMedia | **all exported** (1819 exports, 62 matching `Timebase`) |
| `_CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer` | CoreMedia | **exported** (2 matching `AudioBufferList`) |

So everything a renderer of this shape needs is the release's own: an output queue to push buffers
through, a timebase to push them at a rate, and a way to get the audio out of a `CMSampleBuffer`. The two
class names themselves are nowhere near 6.1.3 - 0 hits for `AVSampleBufferAudioRenderer`,
`AVSampleBufferRenderSynchronizer` and `AVSampleBufferAudioRendererInternal` in the release's own
113 981-name selector set - which is what the row's `status` says and is not in dispute.

**What this changes.** `COORDINATION.md` section 2: "`absent` for a **strong-imported class symbol is
forbidden** - that is not a missing feature, that is dyld killing the application at launch." These two
are class symbols an app can strong-import, so on a release where the port does not carry them an app that
names them does not launch. They are the port's debt and they are landable; the measurement above is what
says so.

**What this does not change.** They are still `absent` here, because nobody has written them, and a row
whose status says `implemented` with nothing built is the failure mode the registry check exists to catch.
The `reason` is corrected to stop claiming there is no path, and the debt is written down.

## The oracle the coordinator pointed at is not available on this machine

The brief for this work was to carry the classes and hold them against "this Mac's
AVSampleBufferAudioRenderer". Measured, this machine cannot answer the 11.0 questions:

- **The 11.0 API is not declared in this Mac's SDK.** `-[AVSampleBufferAudioRenderer
  initWithAudioFormatDescription:bufferCapacity:]` and `-[AVSampleBufferAudioRenderer
  initWithAudioFormatDescription:]` do not compile against macOS's own headers - "no known instance method
  for selector" - so a probe cannot construct the object through the API the port must implement.
- **The class exists and is nothing like the 11.0 surface.** At runtime, through `class_copyMethodList`,
  `AVSampleBufferAudioRenderer` is PRESENT with superclass `NSObject`, instance size 16, and **51 own
  instance methods**: `-init`, `-requestMediaDataWhenReadyOnQueue:usingBlock:`, `-enqueueSampleBuffer:`,
  `-flush`, `-isReadyForMoreMediaData`, `-setRenderSynchronizer:error:`, `-setVolume:`, `-isMuted`,
  `-timebase`, `-status`, `-error`, `-setAudioTimePitchAlgorithm:`, `-outputContext`, `-expire` and a tail
  of `_`-prefixed and 26-era members (`-copyFigSampleBufferAudioRenderer:`, `-contentKeySession`,
  `-audioTapProcessor`). The 11.0 names the port must carry - `-renderSampleBuffer:`, `-renderingAlgorithm`,
  `-currentTime`, `-isRendering`, `-isRenderingForwards`, `-finishRendering` - are **not among them**.
  `AVSampleBufferRenderSynchronizer` is PRESENT with 39 own instance methods, of which the 11.0 ones that
  remain are `-currentTime`, `-rate`/`-setRate:`, `-addPeriodicTimeObserverForInterval:queue:usingBlock:`,
  `-removeTimeObserver:` and `-timebase`; the rest are `_`-prefixed.

So Apple's own class here cannot be the answer key for what the port should return: it does not have the
API, and its own API is a later one. An oracle is still reachable - the 11.0 declarations are in the 26.2
iOS SDK the port compiles against, and a probe can declare that interface itself and reach the runtime's
implementation through it, which is the same shape as
`tests/backports/host/avf-recommended-settings7` (the concrete class of a capture output on this machine is
`AVCaptureVideoDataOutput_Tundra`, a framework subclass, so that check calls the port's IMP fetched with
`class_getInstanceMethod` rather than a message send). What it costs is a reconstructed interface and a
runtime-driven probe, not an unavailable machine.

## What is left to write, named

- `AVSampleBufferAudioRenderer` as a port-defined class: `-initWithAudioFormatDescription:bufferCapacity:`
  over an `AudioQueue` created with `_AudioQueueNewOutput` on a format the description carries, buffers
  allocated with `_AudioQueueAllocateBuffer`, `-renderSampleBuffer:` copying the audio out with
  `_CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer` and enqueueing it with
  `_AudioQueueEnqueueBuffer`, `-flush` on `_AudioQueueFlush`, `-isRendering`/`-isRenderingForwards`/`-rate`
  from the queue's own state, `-currentTime` from the timebase the renderer owns.
- `AVSampleBufferRenderSynchronizer` as a port-defined class owning one `CMTimebase`, holding its renderers
  weakly, `-addRenderer:error:`/`-removeRenderer:error:` moving them onto and off that clock,
  `-currentTime` from `_CMTimebaseGetTime`, `-setRate:` on `_CMTimebaseSetRate`, and the two time observers.
- the protocol `AVQueuedSampleBufferRendering` as `@protocol`, which the renderer would then conform to -
  a protocol row needs the header the sources import, which is the check `protocol_headers_test` runs.
- a check in the shape of the two above: one source, Apple's own answers and the port's joined key by key,
  with mutations. The oracle has to be built first, per the paragraph above.

Every member of both classes needs a registry row of its own (a member of a class the port defines is API
the port carries, and `check_registry` asks whether a row says so), and `tools/cache-index/first-rung.py`
must answer 11.0 for all of them before they share an object with anything else.

## Reproducing

    xmake l tools/image-exports.lua 6.1.3 armv7 "AudioToolbox.framework/AudioToolbox" "AudioQueue"
    xmake l tools/image-exports.lua 6.1.3 armv7 "CoreMedia.framework/CoreMedia" "Timebase"
    xmake l tools/image-exports.lua 6.1.3 armv7 "CoreMedia.framework/CoreMedia" "AudioBufferList"
    grep -cxF AVSampleBufferAudioRenderer ~/.charon/dyld/6.1.3/selectors_armv7.txt   # 0

The runtime enumeration of this machine's two classes is `class_copyMethodList` over
`NSClassFromString(@"AVSampleBufferAudioRenderer")` and of its synchronizer; the numbers above (51 and 39 own
instance methods, superclass `NSObject`, instance size 16) are from that, on 2026-10-03.