# The two 11.0 sample-buffer render classes: one cannot be timed on 6.1.3, the other can be built

Two rows of `registry/AVFoundation/absent_AVFoundation.json`, `AVSampleBufferAudioRenderer` and
`AVSampleBufferRenderSynchronizer`, plus the protocol `AVQueuedSampleBufferRendering` named in
`Release11.md`. Both stay `absent`. What changed is that each row's reason is now a measurement instead of
an impression, and the two point in OPPOSITE directions: the renderer is a wall, the synchronizer is not.

## The renderer: a wall, and the wall is the queue

`AVSampleBufferAudioRenderer` must play a buffer "at sampleBuffer's output presentation timestamp, as
interpreted by the timebase" (`AVQueuedSampleBufferRendering.h:60`). 6.1.3's AudioQueue cannot do that, and
the three places that could have said otherwise all say the same thing:

- **`AudioQueueBuffer` has no time field.** Its members are `mAudioDataBytesCapacity`, `mAudioData`,
  `mAudioDataByteSize`, `mUserData`, `mPacketDescriptionCapacity`, `mPacketDescriptions` and
  `mPacketDescriptionCount` - read from the SDK header the release's own AudioToolbox is built against.
- **`AudioStreamPacketDescription` has three fields and none is a time**: `mStartOffset`,
  `mVariableFramesInPacket`, `mDataByteSize`.
- **Of the 43 exports matching `AudioQueue` in 6.1.3's AudioToolbox, the three time members all READ a
  time**: `_AudioQueueGetCurrentTime`, `_AudioQueueDeviceGetNearestStartTime`,
  `_AudioQueueDeviceTranslateTime`. Not one of them schedules a buffer at one, and there is no
  `AudioQueueEnqueueBufferAtTime` among the 43.

A queue that can only play from now cannot honour a timestamp, so this class is not carried, and its row
now says exactly that instead of saying the release has no renderer. The release's own way to push
buffers at a rate - `AVAudioEngine` with `AVAudioPlayerNode` and `AVAudioPCMBuffer`, which the port
already carries - takes an `AVAudioPCMBuffer`, not a `CMSampleBuffer`.

## The synchronizer: NOT a wall, and here is the two-step that builds its clock

This is the correction, and it is the one that matters for what a next session does. The plain
`_CMTimebaseCreate` is **not** exported by 6.1.3's CoreMedia. The two-step form is:

    CMTimebaseCreateWithMasterClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase)

and **both halves are exported on this release**, read from CoreMedia's own export trie
(1819 exports, 62 matching `Timebase`):

| symbol | on 6.1.3 armv7 |
| --- | --- |
| `_CMTimebaseCreate` | **0** |
| `_CMTimebaseCreateWithMasterClock` | 1 |
| `_CMClockGetHostTimeClock` | 1 |
| `_CMTimebaseAddTimer`, `_CMTimebaseRemoveTimer` | 1 each |
| `_CMTimebaseSetTime`, `_CMTimebaseGetTime`, `_CMTimebaseGetTimeAndRate` | 1 each |
| `_CMTimebaseSetRate`, `_CMTimebaseGetRate` | 1 each |
| `_CMTimebaseDispose` | 1 |
| `_FigTimebaseCreateWithMasterClock`, `_FigClockRetain` | 1 each - the pre-4.0 spellings, private, and not to be used |

So every member `AVSampleBufferRenderSynchronizer` declares - `-timebase`, `-rate`/`-setRate:`,
`-setRate:time:`, `-currentTime`, `-addPeriodicTimeObserverForInterval:queue:usingBlock:`,
`-addBoundaryTimeObserverForTimes:queue:usingBlock:`, `-removeTimeObserver:` - is one `CMTimebase`
operation the release exports, and the clock itself is two exported calls. This class is the port's debt
and it is buildable, which is what the earlier reading of the row got wrong.

**What it is worth on 6.1.3, measured**: the release's own `AVSampleBufferDisplayLayer` carries
`-enqueueSampleBuffer:` and `-flush` (first-rung 6.0, and the port carries the class in
`AVFoundation/AVSampleBufferDisplayLayer8.m`), so a client puts the RELEASE'S display layer on this clock
and gets video frames timed against audio it plays itself. Without the renderer there is no CMSampleBuffer
sink, so the synchronizer's other end is the display layer and not this pair.

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