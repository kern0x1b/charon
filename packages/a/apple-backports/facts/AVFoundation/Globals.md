# The AVFoundation constants the releases this port targets do not export: 116 names, every value read

One object per release, in `AVFoundation/AVFoundationGlobals<NN>.m`, because an object may only carry
API of one release and the gate reads that off the object. Five objects, five releases:

| object | release the name is first exported by | constants | of those read twice | header's own introduced version |
| --- | --- | --- | --- | --- |
| `AVFoundationGlobals1001.m` | 10.0.1 | 1 | 1 | 10.0 |
| `AVFoundationGlobals110.m` | 11.0 | 1 | 1 | 17.0 |
| `AVFoundationGlobals160.m` | 16.0 | 9 | 9 | 14.0, 17.0 and 26.0 |
| `AVFoundationGlobals180.m` | 18.0 | 51 | 42 | 17.0, 17.4, 18.0 and 26.0 |
| `AVFoundationGlobals260.m` | no held cache exports it | 54 | 0 | 26.0 |
| | | **116** | **62** |

The split is by **measured** release, not by the header's `API_AVAILABLE`. `tools/symbol-first-release.lua`
over the held cache ladder answers the question an object is placed by: the first release whose
AVFoundation *exports* the name. The two disagree for 30 of the 116 names, and by a lot in one
direction - the ladder holds no cache between 12.0 and 16.0 and none above 18.0, so every name that
arrived in 13.x to 15.x measures as 16.0 and every name that arrived in 17.x measures as 18.0, whatever
the header says. `AVMediaTypeAuxiliaryPicture` is the clearest case: the header says iOS 14.0 and the
measurement says the 16.0 cache exports it. That is the whole reason for the rule, and it is why
`relcheck.lua` (which is what the gate runs) refuses an object that holds names from two releases.


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

## What the ladder measures, and the run that measured it

```
CHARON_ROOT=$PWD xmake l tools/symbol-first-release.lua .agent-work/avf/first-names.txt > .agent-work/avf/first-release.tsv
ladder: 53 rungs, 3.0 (armv7) .. 18.0 (arm64e)
owner filter: on, the .tbd libraries of .../iPhoneOS16.4.sdk
```

The names are spelled with the leading underscore the image exports, and that matters: asked the way C
spells them the same tool answers `none` for every one of the 116, which would have placed all of them
in the 26.0 band. Its own header states what it measures - "the first held release that exports it,
read from that release's own dyld shared cache ... what it reports is where a client can first bind the
symbol, not what a header's availability annotation says" - and its `owner filter` line says which
libraries count.

The distribution over the 116:

```
  1 10.0.1      1 11.0      9 16.0     51 18.0     54 none
```

`none` is an answer, not a gap: it is how this port decides an API is not in any held release at all, and
those 54 names are placed by their registry row's own `introduced` (26.0 for every one of them), which
is why they form one object.

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