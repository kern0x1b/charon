# The AVFoundation constants the releases this port targets do not export: 116 names, every value read

One object per release, in `AVFoundation/AVFoundationGlobals<NN>.m`, because an object may only carry
API that arrived in one of them and the gate reads that off the stub. Six objects, six releases:

| object | release | constants | of those read twice |
| --- | --- | --- | --- |
| `AVFoundationGlobals100.m` | 10.0 | 1 | 1 |
| `AVFoundationGlobals140.m` | 14.0 | 1 | 1 |
| `AVFoundationGlobals170.m` | 17.0 | 29 | 29 |
| `AVFoundationGlobals174.m` | 17.4 | 1 | 1 |
| `AVFoundationGlobals180.m` | 18.0 | 23 | 23 |
| `AVFoundationGlobals260.m` | 26.0 | 61 | 7 |
| | | **116** | **62** |

## The two oracles, and what each can reach

**The release's own cache.** `tools/corpus/cache-value.lua` reads what a symbol an image of a dyld
shared cache exports actually holds: the export gives the variable's address, the variable holds a
slid pointer, the pointer names a `__CFString`, and the string's own words give the bytes and their
count. It uses the tree's own cache reader (`modules/apple/dyld.lua`), so the split cache and the
slide a stored pointer carries are handled by the code that already binds them.

```
CHARON_ROOT=$PWD xmake l tools/corpus/cache-value.lua \
    ~/.charon/dyld/18.0/dyld_shared_cache_arm64e .agent-work/avf/symbols-pointer.tsv > .agent-work/avf/values-18.tsv
CHARON_ROOT=$PWD xmake l tools/corpus/cache-value.lua \
    ~/.charon/dyld/16.0/dyld_shared_cache_arm64e .agent-work/avf/symbols-pointer.tsv > .agent-work/avf/values-16.tsv
CHARON_ROOT=$PWD xmake l tools/corpus/cache-value.lua \
    ~/.charon/dyld/12.0/dyld_shared_cache_arm64  .agent-work/avf/symbols-pointer.tsv > .agent-work/avf/values-12.tsv
```

Its own controls, on each of the three caches, from the first lines of the run:

```
# control AVMediaTypeVideo	STRING	vide	4 bytes	isa __NSCFConstantString
# control AVMediaTypeCharonProbeNoSuchConstant	ABSENT	-
```

The first is a name the cache exports and holds as a string, the second a name it does not export:
between them a run that examined nothing cannot pass. The ladder ends at 18.0, so this oracle reaches
every constant up to and including 18.0 and **nothing** above it - 59 of this framework's 26.0
constants are in no cache this machine holds.

**The host's own AVFoundation.** `coordination/corpus/ledger/constant-values-AVFoundation.tsv` holds
231 rows measured with `dlopen + dlsym` on the host, decoded through `CFStringGetCString` as UTF-8,
each row naming the image it read and the build:

```
AVAssetExportPresetHEVC4320x2160	26.0	NSString *const	AVAssetExportPresetHEVC4320x2160	dlopen + dlsym on the host, decoded through CFStringGetCString as UTF-8	/System/Library/Frameworks/AVFoundation.framework/AVFoundation	macOS 26A428
AVTrackAssociationTypeRenderMetadataSource	26.0	NSString *const	rndr	dlopen + dlsym on the host, decoded through CFStringGetCString as UTF-8	/System/Library/Frameworks/AVFoundation.framework/AVFoundation	macOS 26A428
```

116 of the 121 constants this worker's list holds appear there. This machine's own macOS is 27.0,
which has **no** AVFoundation at all - `/System/Library/Frameworks/AVFoundation.framework/Versions/A`
holds `_CodeSignature` and `Resources` and no binary, and `dlsym` for `_AVMediaTypeVideo` on the
image path answers nothing - so this oracle is read from the corpus, from the macOS 26A428 build it
was measured on, and not re-taken here.

## Where the two oracles meet

62 names are in both. Every one of them agrees, which is the point of reading twice:

```
agree 62 differ 0
```

(`coordination/corpus/ledger/constant-values-AVFoundation.tsv` column `value` against
`.agent-work/avf/values-{18,16,12}.tsv` column 9, over the 62 names in both.)

The agreement is not a formality. `AVURLAssetOverrideMIMETypeKey` is **not** the string its own name
says:

```
17.0   AVURLAssetOverrideMIMETypeKey   AVURLAssetOutOfBandMIMETypeKey
```

and `AVPlayerInterstitialEventMonitorInterstitialEventWasUnscheduledErrorKey` is spelled
`InterstitialEventWasUnschedule` - without the `d` - in the value the host's own symbol holds. Both
were written out by name first and the measurement disagreed with what had been written, which is the
reason every value here is read and none is typed.

## The five this cannot answer

`AVCaptureWhiteBalanceTemperatureAndTintValues{Cloudy,Daylight,Fluorescent,Shadow,Tungsten}` are not
strings. `AVCaptureWhiteBalanceTemperatureAndTintValues` is a struct of two `float`s
(`AVCaptureDevice.h:1671-1673` in the SDK 26.2), so there is no CFString to read and no
`__cfstring` behind the symbol; they are also `API_UNAVAILABLE(macos)`, so the host oracle cannot
reach them either, and no cache this machine holds is of a release that has them. Their values are a
pair of colour temperatures and tints that only Apple's own image holds. They are **not** carried:
a constant with an invented value is a silent fake, and the pair would be invented. See
`coordination/wave-2026-10-03/v-avf-report.md`.

## What these constants are for, on this port

None of them is the release's own: 6.1.3 exports none of these names, so an application that names
one loads the string below instead of a missing symbol. Where it hands that string to the release -
`AVAssetExportSession presetName`, `AVMetadataItem keySpace`/`key`, a format description's
`AVMediaType`, a `NSNotificationName` - the release compares it against the strings it knows and
answers as it answers for any string it does not know. That is the whole behaviour, and it is the
same behaviour the release has for a string it has never heard of; the point of carrying the name is
that an application which names it links and runs instead of failing to load.