# The six VideoToolbox queries: what the host answers, and what the release can answer at each band

Six functions SDK 26.2 declares, none of which any release this port builds exports:

| row | SDK | 4.3 | 6.1.3 | 16.0 | 18.0 |
| --- | --- | --- | --- | --- | --- |
| `VTIsHardwareDecodeSupported` | 11.0 | absent | absent | - | - |
| `VTIsStereoMVHEVCDecodeSupported` | 17.0 | absent | absent | - | - |
| `VTIsStereoMVHEVCEncodeSupported` | 17.0 | absent | absent | - | - |
| `VTCreateCGImageFromCVPixelBuffer` | 9.0 | absent | absent | - | - |
| `VTCopySupportedPropertyDictionaryForEncoder` | 11.0 | absent | absent | - | - |
| `VTRegisterSupplementalVideoDecoderIfAvailable` | 26.2 | absent | absent | - | - |

Measured with `tools/corpus/dump-cache.lua` over `~/.charon/dyld/4.3/dyld_shared_cache_armv7` (read-only)
and over v-audio's 6.1.3 armv7 dump, and over `coordination/corpus/caches/{6.0,7.0.1,10.3.4,12.0,16.0,18.0}.tsv`.

## A NEGATIVE RESULT THAT DECIDES THE FIRST ROW

`VTIsHardwareDecodeSupported` was going to be answered through the decoder's own supported-property
dictionary. **That function does not exist at any band the port builds or any band this wave holds**:

```
_VTDecompressionSessionCopySupportedPropertyDictionaryForDecoder   4.3=0  6.1.3=0  6.0=0  7.0.1=0  10.3.4=0  12.0=0  16.0=0  18.0=0
_VTCompressionSessionCopySupportedPropertyDictionaryForEncoder    4.3=0  6.1.3=0  6.0=0  7.0.1=0  10.3.4=0  12.0=0  16.0=0  18.0=0
```

so there is no dictionary to ask, at any band, and a port that answered from one would be answering from
nothing.

**The route that does exist is the release's own, and it is a specification key rather than a query:**

```
_kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder   4.3=1  6.1.3=1
_kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder      4.3=1  6.1.3=1
_kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder   4.3=1  6.1.3=1
_VTSessionCopySupportedPropertyDictionary                             4.3=1  6.1.3=1
_VTCopyVideoEncoderList                                               4.3=0  6.1.3=1
```

A decompression session created with `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder` set
to true exists only if the release can decode that codec in hardware, so asking the release by creating that
session IS the release's answer, on every band - not a table of which codec this hardware has.

## What the host answers, measured 2026-10-03 on this Mac

```
VTIsHardwareDecodeSupported
  H264             0x61766331 -> 1        MPEG2              0x6d703276 -> 0
  HEVC             0x68766331 -> 1        JPEG               0x6a706567 -> 1
  AppleProRes422   0x6170636e -> 1        Animation          0x726c6520 -> 0
  AV1              0x61763031 -> 1        VP9                0x76703039 -> 0
VTIsStereoMVHEVCDecodeSupported   -> 1
VTIsStereoMVHEVCEncodeSupported  -> 1
VTRegisterSupplementalVideoDecoderIfAvailable (returns void)
  VP9 before 0 -> after 1
  AV1 before 1 -> after 1
VTCreateCGImageFromCVPixelBuffer, a 3x2 buffer, options NULL
  32BGRA  -> 0  3x2 bits=8 bytesPerRow=64 bitmapInfo=0x2002
  32ARGB  -> 0  3x2 bits=8 bytesPerRow=64 bitmapInfo=0x4002
  420 biplanar -> 0  3x2 bits=8 bytesPerRow=64 bitmapInfo=0x2006
  OneComponent8 -> 0  3x2 bits=8 bytesPerRow=64 bitmapInfo=0x2006
VTCopySupportedPropertyDictionaryForEncoder(320, 240, codec, NULL, &id, &properties)
  codec 0x61766331 H264       -> 0  encoderID=com.apple.videotoolbox.videoencoder.ave.avc              keys=140
  codec 0x68766331 HEVC       -> 0  encoderID=com.apple.videotoolbox.videoencoder.ave.hevc             keys=169
  codec 0x6170636e ProRes422  -> 0  encoderID=com.apple.videotoolbox.videoencoder.appleproreshw.422   keys=59
  codec 0x6a706567 JPEG       -> 0  encoderID=com.apple.videotoolbox.videoencoder.jpeg.ajpeg           keys=54
  codec 0x6d703276 MPEG2      -> -12908  encoderID=(null)  keys=0
  codec 0x61763031 AV1        -> -12908  encoderID=(null)  keys=0
```

Two things in that table are worth naming because they are the whole content of the row:

- **every value in the returned dictionary is NULL** - 140 keys and 140 NULL values for H264, 169 and 169 for
  HEVC, 59 and 59 for ProRes422, 54 and 54 for JPEG. The function's own documentation says it "builds a list
  of supported properties", and what it builds is the KEY SET: a caller that reads a value gets NULL back, so
  the port must hand back the keys with no values rather than inventing any.
- **a codec with no encoder answers `kVTCouldNotFindVideoEncoderErr` (-12908)**, with no encoder ID and no
  dictionary, rather than an empty dictionary. `-12908` is the release's own code (`VTErrors.h:37`).

A first version of the probe asked for those six codecs in one process and died with SIGSEGV on the fifth;
each codec asked in its own process answers cleanly, so the crash was the probe's own doing (it was reading
the value of a NULL entry through a bridge cast) and not the function's.

**The one row whose behaviour is a change rather than an answer is `VTRegisterSupplementalVideoDecoderIfAvailable`**:
it returns void, and on this host it moved `VTIsHardwareDecodeSupported(VP9)` from 0 to 1 - the decoder was
present on the system and not registered by default, which is exactly what its own documentation says it does.
That is a row with a measurement behind it rather than an empty function, and it is the one the first two rows
have to be read next to: a `VTIsHardwareDecodeSupported` that answered from a table would disagree with the
release after this call.

## Source

- `coordination/corpus/caches/*.tsv` and the 4.3 and 6.1.3 caches, read-only, for the ladder.
- This Mac's own VideoToolbox, for the host's answers: `.agent-work/v-audio2/queries.m`, and
  `.agent-work/v-audio2/enc.m` for the one-codec-per-process table above.
- `VTErrors.h:37` for `kVTCouldNotFindVideoEncoderErr`.
- SDK 26.2 `VTUtilities.h:27-61`, `VTDecompressionSession.h:321-344`, `VTCompressionSession.h:341-346` and
  `VTVideoEncoderList.h:55-64`.