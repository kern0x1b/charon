# The multi-image and options decode variants: what each one can do here, and the one that cannot be written

Six rows of SDK 26.2, none of which any release this port builds exports. This page records the ladder, the
contracts, the four that are carried, and the two that are not written at all - with the mechanical reason.

## The ladder (tools/corpus/dump-cache.lua over the 4.3 armv7 cache, read-only, and v-audio's 6.1.3 armv7 dump, 2026-10-03)

```
_VTDecompressionSessionDecodeFrameWithMultiImageCapableOutputHandler   4.3=0  6.1.3=0
_VTDecompressionSessionSetMultiImageCallback                           4.3=0  6.1.3=0
_VTCompressionSessionEncodeMultiImageFrame                             4.3=0  6.1.3=0
_VTCompressionSessionEncodeMultiImageFrameWithOutputHandler            4.3=0  6.1.3=0
_VTDecompressionSessionDecodeFrameWithOptions                         4.3=0  6.1.3=0
_VTDecompressionSessionDecodeFrameWithOptionsAndOutputHandler         4.3=0  6.1.3=0
_kVTDecodeFrameOptionKey_  (any key)                                   4.3=0  6.1.3=0
_VTDecompressionSessionDecodeFrame                                     4.3=1  6.1.3=1
_VTCompressionSessionEncodeFrame                                       4.3=1  6.1.3=1
_VTCompressionSessionEncodeFrameWithOutputHandler                      4.3=0  6.1.3=0
```

The 16.4 SDK declares none of the six either; its `VTDecompressionSession.h` and `VTCompressionSession.h`
name them nowhere, so all six are declared in `CharonVideoToolbox.h`, transcribed from SDK 26.2.

## The four that are carried, and the refusal each one earns

| row | answer | why the release cannot do it |
| --- | --- | --- |
| `VTDecompressionSessionSetMultiImageCallback` | `kVTVideoDecoderNotAvailableNowErr` (-12913) | the callback is reached only "when the video decoder outputs CMTaggedBufferGroups"; the release's own decode callback ends at `CVImageBuffer imageBuffer` (16.4 SDK `VTDecompressionSession.h:85-92`), so a callback stored here could never be called |
| `VTDecompressionSessionDecodeFrameWithMultiImageCapableOutputHandler` | -12913 | the handler receives a `CMTaggedBufferGroupRef`, and the release's callback has no parameter that could receive one; the header itself says the block "will not be called" if the call returns an error |
| `VTCompressionSessionEncodeMultiImageFrame` | `kVTVideoEncoderNotAvailableNowErr` (-12915) | the multi-image encode's SOURCE is a `CMTaggedBufferGroupRef`; the release's encode entry point takes a `CVImageBuffer`, so there is no release function that reads one |
| `VTCompressionSessionEncodeMultiImageFrameWithOutputHandler` | -12915 | the same source, and a block the header says "may be called asynchronously, on a different thread from the one that calls" it - a promise that needs an encode to run it after |

`CMTaggedBufferGroup` arrived with iOS 14 and no release the port builds has it. A variant that accepted its
argument and did nothing with it would be the silent fake the brief forbids; these refuse with the release's
own codes, before any work, and each `infoFlagsOut` is set to 0 with the file saying why - the two flags the
header names are set by a decoder or encoder as it runs, and nothing ran.

## The two that are NOT written: VTDecompressionSessionDecodeFrameWithOptions and its handler twin

`VTDecompressionSessionDecodeFrameWithOptions` is `VTDecompressionSessionDecodeFrame` with two parameters
added, and the obvious implementation is to forward to the release's own decode. **That forwarding cannot be
written as one object across the port's bands, and the reason is mechanical rather than a matter of taste:
the release changed the arity of `VTDecompressionSessionDecodeFrame` itself.**

```
16.4 SDK, VTDecompressionSession.h:184-190      API_AVAILABLE(macosx(10.8), ios(8.0), tvos(10.2))
  VTDecompressionSessionDecodeFrame(session, sampleBuffer, decodeFlags, sourceFrameRefCon, infoFlagsOut)
```

The `infoFlagsOut` parameter did not exist before iOS 8, so the 4.3 symbol takes FOUR arguments and the 8.0+
symbol takes five. The 4.3 and the 6.1.3 caches both export `_VTDecompressionSessionDecodeFrame`, so an
object that calls the five-argument form links at every band and **calls a four-argument function with five
arguments at 4.3**. `backports.lua`'s `band()` keys on a symbol's presence in the band, not on its signature,
so nothing in the build can catch it. The two rows stay owed rather than being written with a call that is
wrong on the port's lowest band.

The second reason the row is owed, which would apply even with a per-band forward: **`frameOptions` has
nothing to be honoured with.** The header says it "contains key/value pairs specifying additional options for
decoding this frame" and that "only keys with `kVTDecodeFrameOptionKey_` prefix should be used" - and there is
no `kVTDecodeFrameOptionKey_` of any kind in the 4.3 or the 6.1.3 cache (zero hits, above). No release
function takes such a dictionary, so a caller's options cannot be passed anywhere; forwarding the decode and
dropping them would answer `noErr` for a request the release never honoured.

What would clear both: a release whose `VTDecompressionSessionDecodeFrame` has the five-argument shape
throughout the port's bands (measured: it does not, at 4.3), and a release that defines a
`kVTDecodeFrameOptionKey_` (measured: none does, at either band the port builds).

`VTDecompressionSessionDecodeFrameWithOptionsAndOutputHandler` is owed for the same arity reason plus the one
the 9.0 output-handler pair already established: `_VTDecompressionSessionDecodeFrameWithOutputHandler` is
absent at both bands, so a block handed to the port could only be called by the port itself, from a decode it
cannot reach.

## Source

- The ladder: `tools/corpus/dump-cache.lua` over `~/.charon/dyld/4.3/dyld_shared_cache_armv7` (read-only) and
  v-audio's 6.1.3 armv7 dump.
- SDK 26.2 `VTDecompressionSession.h:388-480` and `:484-566`, `VTCompressionSession.h:349-428`; `VTErrors.h:42`
  and `:45` for the two codes.
- The 16.4 SDK's `VTDecompressionSession.h:85-92` (the decode callback's shape) and `:184-190` (the decode's
  arity and its iOS 8 date).