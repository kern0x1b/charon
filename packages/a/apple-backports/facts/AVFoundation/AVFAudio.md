# AVFAudio, the value types under AVAudioEngine's graph

`AVAudioFormat`, `AVAudioBuffer` and `AVAudioPCMBuffer` are the immutable format and mutable
buffer types the rest of AVFAudio's node graph (`AVAudioEngine`, `AVAudioPlayerNode`,
`AVAudioUnitEQ`, `AVAudioConverter` - not yet carried) is built on. iOS 6 has none of the classes,
but it has everything they wrap: `AudioStreamBasicDescription` and `AudioBufferList` are Core
Audio structs this release's own AUGraph, Audio Units and Audio Converter Services already read
and write, unchanged since. Nothing here is emulated - an `AVAudioFormat`'s `streamDescription`
is a real ASBD any Core Audio call on this device already knows how to take.

## AVAudioFormat

Wraps one `AudioStreamBasicDescription`, immutable once constructed. The four common formats
this port builds by hand - `AVAudioPCMFormatFloat32`/`Float64`/`Int16`/`Int32`, each interleaved
or not - are filled into the ASBD the same way Core Audio's own linear PCM convention already
requires: `mFormatID = kAudioFormatLinearPCM`, `mFramesPerPacket = 1`, and, for a non-interleaved
format, `mBytesPerFrame`/`mBytesPerPacket` describe **one buffer's** bytes (one channel), not the
frame's total - the convention every Core Audio unit on this device already reads
`kAudioFormatFlagIsNonInterleaved` ASBDs by.

More than two channels without an explicit `AVAudioChannelLayout` is refused, matching the real
class's own documented behaviour (`initStandardFormatWithSampleRate:channels:` and
`initWithCommonFormat:sampleRate:channels:interleaved:` both fail past 2 channels by design, not
only in this port) - `AVAudioChannelLayout` itself is not carried yet (no application in this
project's corpus references the class directly; see `registry/CallKit/absent_CallKit.json`-style
reasoning applied the same way for the audio cluster), so the layout-taking initializers accept a
caller's own layout object structurally but cannot be exercised by anything this port also builds.

`initWithSettings:` reads the same `AVFormatIDKey`/`AVSampleRateKey`/`AVNumberOfChannelsKey`/
`AVLinearPCMBitDepthKey`/`AVLinearPCMIsFloatKey`/`AVLinearPCMIsNonInterleaved` keys
`AVAudioSettings.h` has carried since iOS 3-4 (already real on this release, used by
`AVAudioRecorder`) and only rejects more than 2 channels or a bit depth this port's four common
formats don't cover.

Not carried: `magicCookie` (iOS 10), `initWithCMAudioFormatDescription:`/`formatDescription`
(iOS 9, needs `CMAudioFormatDescriptionRef` bridging this port doesn't build), and
`initWithStreamDescription:channelLayout:`/`initWithCommonFormat:sampleRate:interleaved:channelLayout:`
in the multi-channel case (needs a real `AVAudioChannelLayout` to read `channelCount` from).
`NSSecureCoding` (`initWithCoder:`/`encodeWithCoder:`) is declared by the real header but not
implemented - nothing in this port's corpus archives an `AVAudioFormat`.

## AVAudioBuffer and AVAudioPCMBuffer

**`AVAudioBuffer` is a real trap, measured, not assumed.** The build gate's own `band()`/
`duplicated()` check refused to let this port define the class under its own name, and reading
why was worth doing rather than working around: `objc.inventory` against the real iOS 6.0 and
6.1.3 armv7 shared caches (`.charon/dyld/{6.0,6.1.3}/dyld_shared_cache_armv7`) shows
`AVAudioBuffer` already exists on this release - as a **completely different, private,
AudioQueue-era class** (`-initWithAudioQueueBuffer:channels:`, `-packetDescriptions`,
`-bytesDataSize`, `-channels`; no `format`, no `audioBufferList`) that predates and has nothing to
do with the class AVFAudio publicly introduced under the same name in iOS 8. `AVAudioFormat` and
`AVAudioPCMBuffer` themselves are confirmed absent on both caches - only the base class name
collides. Left alone, this port's `AVAudioPCMBuffer` would have silently inherited the *wrong*,
incompatible `AVAudioBuffer` at runtime and crashed on the first `-format`/`-audioBufferList` call
with an unrecognized-selector, while the build itself stayed green - exactly the coordinator's
warning about this cluster, one level lower than expected.

The fix follows the gate's own suggested pattern for this exact situation ("carry it under a name
of Charon's own"): the base class lives under `CharonAudioBuffer`, declared and implemented in
`AVFoundation/CharonAVAudioBuffer.h`/`AVAudioBuffer8.m`, never under the real, already-taken
`AVAudioBuffer` name. `AVAudioPCMBuffer` (`AVAudioPCMBuffer8.m`) keeps its real name - nothing
collides there - and its *runtime* superclass is `CharonAudioBuffer`, not what Apple's own header
declares. That difference is invisible to every caller: Objective-C dispatch is dynamic, and an
application compiled against Apple's SDK header only ever sends selectors, never inspects the
declared ancestry at link time, so every method a real caller sends still resolves correctly.

Not in the registry under `AVAudioBuffer.*`: `format`, `audioBufferList` and `mutableAudioBufferList`
work on every `AVAudioPCMBuffer` instance (inherited from `CharonAudioBuffer`), but the registry
only describes API by the name a caller and the corpus demand data actually use, and nothing
references `AVAudioBuffer` directly - only `AVAudioPCMBuffer`'s own methods and properties are
registered, since that is the class this port's registry can honestly claim to carry under its
real name.

`AVAudioBuffer`'s header declares its own storage as an opaque `@protected void *_impl` - the
real class does not expose its layout either - so this port keeps its state in a `CharonAudioBufferImpl`
struct of its own, stored behind a private ivar and shared between `AVAudioBuffer8.m` (the base
class: `format`, `audioBufferList`, `mutableAudioBufferList`, `dealloc`) and `AVAudioPCMBuffer8.m`
(the only real subclass this port carries) through `AVFoundation/CharonAVAudioBuffer.h`, a header
private to this package.

`-initWithPCMFormat:frameCapacity:` builds one `AudioBufferList` with as many `AudioBuffer`s as
the format has channels when deinterleaved, or one interleaved buffer otherwise - each `mData`
`calloc`'d (not `malloc`'d: a freshly made buffer reads as silence, matching what an application
expects from a buffer it has not written into yet, not heap garbage). `floatChannelData`/
`int16ChannelData`/`int32ChannelData` are cached pointer arrays built once at construction time,
pointing **into the same memory** the `AudioBufferList` itself holds - not a copy kept in sync by
hand, which is exactly the kind of split state that would let a channel-data write silently fail
to reach `-audioBufferList`. `frameLength`'s setter updates every `AudioBuffer.mDataByteSize` in
the same call, keeping the two views (`floatChannelData`'s frame count and the raw
`AudioBufferList`'s byte size) from drifting apart.

`-copyWithZone:` allocates a fresh buffer of the same format and capacity and `memcpy`s the
sample bytes across; the copy owns its own memory throughout, never aliases the original's.

**Measured, not just built, and run - not just compiled.** The coordinator's warning about this
cluster - a graph that runs and produces nothing, with no exception and a green gate - is
answered by `tests/backports/device/avfaudio.m` (35 checks), which writes a known, non-zero
waveform into every sample of every channel through `floatChannelData`, then reads every one of
them back **through the same pointers and through the raw `AudioBufferList`**, checking for an
exact match rather than a non-nil pointer. A copy's samples are checked to match the original's
while occupying different memory. `nm` showing defined symbols proves linkage; this proves data
actually moved through the buffer the way an application's own read of `floatChannelData` would
see it. Run through `xmake emulate -d iPhone4,1 -r 6.1.3 run /usr/libexec/<test>` - a real armv7
guest, not the host - against the freshly built canon: `checks=35 failures=0`.

Not carried: `AVAudioCompressedBuffer` (a sibling subclass for compressed formats; nothing in
this port's corpus references it) and `-initWithPCMFormat:bufferListNoCopy:deallocator:` (iOS 15).
