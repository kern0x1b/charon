# What a release that has Vision answers, and what the two this port deploys on have

Every number below was read out of a cache or out of a framework on this machine, and every one of
them names the command that produced it so a reader can read it again. Nothing here is a reading of
a header: a header carries a name, a type and an availability, and the value of a constant is in the
framework's own image.

## 1. Neither release this port deploys on carries a Vision image

This is the fact every `absent` row of the Vision library rests on, and it is a fact about the two
releases rather than about this port.

```
CHARON_ROOT=<worktree> xmake l tools/corpus/cache-census.lua VN 6.1.3 4.3 11.0 12.0
```

```
6.1.3     $HOME/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming VN 0
         classes 11378, of which VN* 0
         protocols 1171, of which VN* 0
4.3       $HOME/.charon/dyld/4.3/dyld_shared_cache_armv7
         images 354, of which naming VN 0
         classes 7187, of which VN* 0
         protocols 564, of which VN* 0
11.0      $HOME/.charon/dyld/11.0/dyld_shared_cache_arm64
         images 1258, of which naming VN 0
         classes 52768, of which VN* 155 (<the 155 names elided>)
         protocols 8954, of which VN* 18 (<the 18 names elided>)
12.0      $HOME/.charon/dyld/12.0/dyld_shared_cache_arm64
         images 1368, of which naming VN 0
         classes 63192, of which VN* 222 (<the 222 names elided>)
         protocols 11426, of which VN* 23 (<the 23 names elided>)
control: 418 name(s) beginning VN found in this run, so a zero on another rung is the release's and not the reader's
```

Two things are changed in that and nothing else: the cache paths carry `$HOME` where the run printed
an absolute home path, which this repository does not track, and the parenthetical lists of the 418
names found on 11.0 and 12.0 are cut where they begin -- the counts are the whole of what the
control is for, and the run's whole output is in the band's run directory.

**The control is the point, and it is in the same run.** A census that prints 0 is ambiguous: the
name may really be absent, or the reader may be looking at the wrong thing, and a zero cannot tell
those apart. 6.1.3 is read through 11 378 classes and 1 171 protocols and carries none beginning
`VN`, and the same reader finds 155 classes and 18 protocols in 11.0 and 222 and 23 in 12.0. The
zero is the release's.

`VN` names nothing among the *images* of either release either, so the images themselves are named
`Vision.framework/Vision`:

```
CHARON_ROOT=<worktree> xmake l tools/corpus/cache-census.lua Vision.framework 11.0 12.0
```

```
11.0               images 1258, of which naming Vision.framework 3
12.0               images 1368, of which naming Vision.framework 3
```

Those are the run's `images` lines with the cache paths dropped, which is all of this second census
that section 1 does not already settle.

Which release carried the framework is not the question the rows ask -- the rows ask what 6.1.3 and
4.3 answer, and the answer is that they never had it -- but it is the reason the tree's own
`source` fields for the Vision library read "Vision of the arm64 shared cache of iOS 12.0", and that
is a fact about how the registry was read rather than about when Vision arrived: 11.0 already carries
155 `VN*` classes, so the framework itself arrived with 11.0 and 12.0 is only the rung the names were
read out of.

## 2. Each name of this slice is real, and the first held rung that has it

```
python3 tools/cache-index/first-rung.py VNClassifyImageRequest VNDetectFaceCaptureQualityRequest \
    VNDetectHumanRectanglesRequest VNGenerateAttentionBasedSaliencyImageRequest \
    VNGenerateImageFeaturePrintRequest VNGenerateObjectnessBasedSaliencyImageRequest \
    VNRecognizeAnimalsRequest VNRecognizeTextRequest VNRecognizedText VNRecognizedTextObservation \
    VNFeaturePrintObservation VNSaliencyImageObservation VNRequestProgressProviding \
    _VNElementTypeSize revision:supportsConstellation: hasPrecisionRecallCurve \
    hasMinimumPrecision:forRecall: hasMinimumRecall:forPrecision:
```

```
VNClassifyImageRequest                        16.0
VNDetectFaceCaptureQualityRequest             16.0
VNDetectHumanRectanglesRequest                11.0
VNGenerateAttentionBasedSaliencyImageRequest  16.0
VNGenerateImageFeaturePrintRequest            16.0
VNGenerateObjectnessBasedSaliencyImageRequest 16.0
VNRecognizeAnimalsRequest                     16.0
VNRecognizeTextRequest                        16.0
VNRecognizedText                              16.0
VNRecognizedTextObservation                   16.0
VNFeaturePrintObservation                     16.0
VNSaliencyImageObservation                    16.0
VNRequestProgressProviding                    16.0
_VNElementTypeSize                            16.0
revision:supportsConstellation:                16.0
hasPrecisionRecallCurve                       16.0
hasMinimumPrecision:forRecall:                16.0
hasMinimumRecall:forPrecision:                16.0
```

The tool's own separator is a tab; the columns above are aligned by hand and nothing else about them
is changed.

**16.0 is not a version, it is a bound.** The held set is dense to 12.0 and then has a hole -- no
13.0, 14.0 or 15.0 is held -- so a name of 13.0, 14.0 or 15.0 reads as 16.0: after 12.0 and by 16.0.
`tools/release-split.lua` prints the same note in a run of its own. What a row's `introduced` says is
the SDK's annotation, which is this registry's own source, and it is not read out of a cache.

**`VNDetectHumanRectanglesRequest` reads 11.0, and that is not a mistake.** It is a real class of
11.0's Vision, with `VNHumanObservation` and `VNHumanDetector` beside it in the same census, while the
SDK annotates it `ios(13.0)`. A release can carry a class before the release that declares it
public. It changes nothing for a row whose `minimum` is 6.0, because the rung the port deploys on is
6.1.3 and it carries no Vision at all; and it is the reason that row is implemented rather than left
absent, since `modules/apple/backports.lua` refuses a row the release the band runs on carries itself.

## 3. The two constants' values, read out of the image

The value of a constant is Apple's data. For an `NS_TYPED_ENUM` name the header carries the type, the
name and the availability and no value, so nothing about the spelling of the name says what the text
is -- measured on three unrelated names before this one: `MTLCounterErrorDomain` is
`"MTLCounterErrorDomain"`, `PHLivePhotoShouldRenderAtPlaybackTime` is
`"LivePhotoShouldRenderAtPlaybackTime"`, and `CVPixelBufferVersatileBayerKey_BayerPattern` is
`"ProResRAW_BayerPattern"`.

```
printf 'VNAnimalIdentifierCat\tp\tp\ts\nVNAnimalIdentifierDog\tp\tp\ts\n' > .agent-work/runs/vision13/animals.syms
CHARON_ROOT=<worktree> xmake l tools/corpus/cache-value.lua \
    $HOME/.charon/dyld/16.0/dyld_shared_cache_arm64e .agent-work/runs/vision13/animals.syms
```

```
#cache	arm64e	8
VNAnimalIdentifierCat	/System/Library/Frameworks/Vision.framework/Vision	0x1d6496b78	80b034e001000800	3761549440	2251807870201984	1.1125409097017451e-308	0x1e034b080	Cat	8	8
VNAnimalIdentifierDog	/System/Library/Frameworks/Vision.framework/Vision	0x1d6496b80	60b034e001002000	3761549408	9007207311257696	4.45015567791066e-308	0x1e034b060	Dog	8	328
```

`Cat` and `Dog`. Both symbols are exported by the Vision image of the 16.0 arm64e cache -- which is
split, the base file being a header of some 380 KB and the bodies in `.01`, `.03` and `.05`, and
`cache-value.lua` goes through `modules/apple/dyld.lua`'s own `open_cache`, so the slide a stored
pointer carries and the mapping it lands in are undone by the code that already binds them. The
value read is a CFString's chars at +16 and its length at +24 for this ABI, not the first bytes at
whatever the pointer names, and the tool refuses a read wider than the distance to the next export in
the same image.

`VNElementTypeSize` is exported by the same image, at `0x1a17f696c`, and its first word is a code
pointer rather than a pointer to data -- it is a function, and its answers are in section 4.

## 4. What Vision itself answers, measured against this host

The host's Vision is a real one, and every answer below comes from it: the probe reports the image
each symbol resolved in (`dladdr`), and a name the Vision does not carry is asked for as well, so a
reader can tell an absence from a broken reader. `tools/vision/probe130.m` is the probe, and it is
in the tree so that this is one command a reader can paste rather than one they have to trust.

```
sdk=$(xcrun --show-sdk-path)
xcrun clang -target arm64-apple-ios15.0-macabi -isysroot "$sdk" \
    -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -w \
    -framework Foundation -framework Vision -framework CoreGraphics \
    -framework CoreImage -framework CoreVideo tools/vision/probe130.m -o probe130 && ./probe130
```

The only change made to the run's output below is the `NSIndexSet` pointer in each `supportedRevisions`
line, which is this host's heap address and carries nothing; it is written `ADDRESS`.

```
VNElementTypeSize from: Vision
+[VNDetectFaceLandmarksRequest class] from: Vision
&VNAnimalIdentifierCat from: Vision
revision 1 supports constellation 0: NO
revision 1 supports constellation 1: YES
revision 1 supports constellation 2: NO
revision 2 supports constellation 0: NO
revision 2 supports constellation 1: YES
revision 2 supports constellation 2: NO
revision 3 supports constellation 0: NO
revision 3 supports constellation 1: YES
revision 3 supports constellation 2: YES
revision 4 supports constellation 0: NO
revision 4 supports constellation 1: NO
revision 4 supports constellation 2: NO
VNElementTypeSize(0) = 0
VNElementTypeSize(1) = 4
VNElementTypeSize(2) = 8
VNElementTypeSize(3) = 0
VNElementTypeSize(4) = 0
VNAnimalIdentifierCat = Cat
VNAnimalIdentifierDog = Dog
NSProtocolFromString(VNRequestProgressProviding) = found
NSProtocolFromString(VNNoProtocolOfThisName) = nil
NSClassFromString(VNClassifyImageRequest) = found
NSClassFromString(VNRecognizeAnimalsRequest) = found
NSClassFromString(VNRecognizeTextRequest) = found
NSClassFromString(VNDetectHumanRectanglesRequest) = found
NSClassFromString(VNRecognizedText) = found
NSClassFromString(VNRecognizedTextObservation) = found
NSClassFromString(VNFeaturePrintObservation) = found
NSClassFromString(VNSaliencyImageObservation) = found
NSClassFromString(VNGenerateAttentionBasedSaliencyImageRequest) = found
NSClassFromString(VNGenerateObjectnessBasedSaliencyImageRequest) = found
NSClassFromString(VNGenerateImageFeaturePrintRequest) = found
NSClassFromString(VNDetectFaceCaptureQualityRequest) = found
NSClassFromString(VNNoClassOfThisName) = nil
VNRecognizeTextRequest conformsToProtocol(VNRequestProgressProviding) = YES
VNRecognizeTextRequest indeterminate = NO
VNRecognizeAnimalsRequest                      supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 2 (in 1 ranges), indexes: (1-2)] currentRevision = 2 revisionProviding = NO
VNClassifyImageRequest                         supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 2 (in 1 ranges), indexes: (1-2)] currentRevision = 2 revisionProviding = NO
VNDetectHumanRectanglesRequest                 supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 2 (in 1 ranges), indexes: (1-2)] currentRevision = 2 revisionProviding = NO
VNDetectFaceCaptureQualityRequest              supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 3 (in 1 ranges), indexes: (1-3)] currentRevision = 3 revisionProviding = NO
VNGenerateAttentionBasedSaliencyImageRequest   supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 2 (in 1 ranges), indexes: (1-2)] currentRevision = 2 revisionProviding = NO
VNGenerateObjectnessBasedSaliencyImageRequest  supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 2 (in 1 ranges), indexes: (1-2)] currentRevision = 2 revisionProviding = NO
VNGenerateImageFeaturePrintRequest             supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 2 (in 1 ranges), indexes: (1-2)] currentRevision = 2 revisionProviding = NO
VNRecognizeTextRequest                         supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 3 (in 1 ranges), indexes: (1-3)] currentRevision = 3 revisionProviding = NO
VNDetectFaceLandmarksRequest                   supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 3 (in 1 ranges), indexes: (1-3)] currentRevision = 3 revisionProviding = NO
VNDetectRectanglesRequest                      supportedRevisions = <NSIndexSet: ADDRESS>[number of indexes: 1 (in 1 ranges), indexes: (1)] currentRevision = 1 revisionProviding = NO
```

Four things are read out of that, and one of them is not read out of it at all.

**`VNElementTypeSize` is 4 for a float, 8 for a double and 0 for everything else**, which is what
`Vision/Vision130.m` answers, with the widths taken as `sizeof` rather than written as literals.

**`+revision:supportsConstellation:` is the truth table above**: revisions 1 to 3 for 65 points,
revision 3 alone for 76, and NO for every other pair including the not-defined constellation and
every revision outside 1 to 3. The port transcribes it; it does not narrow it to the revisions it
carries, because a revision the port cannot run is refused by the request handler with
`VNErrorUnsupportedRevision`, which is a different question from the one this method asks.

**`VNAnimalIdentifierCat` is `Cat` and `VNAnimalIdentifierDog` is `Dog`**, read here straight out of
the constant's own value and matching what section 3 read out of the 16.0 image.

**`VNRequestProgressProviding` is reachable by name** and the nonsense name the probe asks for beside
it is not, so the pair is what makes a "found" here mean something, and `NSProtocolFromString`
answering for the port's own protocol object is a different answer from one the reader would give
anyway. The port does not adopt the protocol on its `VNRecognizeTextRequest`, and says so in that row:
this port cannot run a text recognition, so there is no progress to report, and a `progressHandler`
that is stored and never called would answer the same as none at all.

**The protocol's metadata reaches the image twice, from the same declaration and not from two.** The
build writes one `<Library>Protocols<release>.m` per release a library's implemented protocol rows
arrived in and names every protocol of that release in it, so the row above causes a
`VisionBackportsProtocols13.0.m`; and `Vision130.m`'s own `@implementation VNRecognizeTextRequest`
emits the same protocol object, because the SDK declares that class as conforming to it and reopening
a class emits the protocols it conforms to. Both definitions come out of the one SDK declaration, so
they are the same weak symbol and the runtime keeps one. This is not the trap
`tests/addon/registry_test.lua`'s `protocol_declarations` guards -- that one is about a source
*defining* `@protocol X <...>` with a member list of its own, which would emit a second object whose
contents could disagree with the SDK's, and no source of this library does that.

**The revision counts above are the host's, and they are NOT copied.** This host's Vision is a
generation past 13.0, and its `supportedRevisions` count every revision Apple has added since --
revisions 2 and 3 of the text and capture-quality requests, for instance, arrived in 14.0 and 16.0
and did not exist in 13.0. What 13.0 had is read from the SDK's own per-revision annotations, which
are the same source a row's `introduced` comes from:

| request | revisions declared at 13.0 | later revisions, and when |
| --- | --- | --- |
| `VNClassifyImageRequest` | 1 | none |
| `VNDetectFaceCaptureQualityRequest` | 1 | 2 at 14.0 |
| `VNDetectHumanRectanglesRequest` | 1 | 2 at 15.0 |
| `VNGenerateAttentionBasedSaliencyImageRequest` | 1 | none |
| `VNGenerateImageFeaturePrintRequest` | 1 | none |
| `VNGenerateObjectnessBasedSaliencyImageRequest` | 1 | none |
| `VNRecognizeAnimalsRequest` | 1 | 2 at 15.0 |
| `VNRecognizeTextRequest` | 1 | 2 at 14.0, 3 at 16.0 |

Every one of them had exactly revision 1 in 13.0, which is what `VNRequests.m`'s own revision table
already answers for a request class it has never heard of -- so no request of this slice needed a
revision of its own to be placed correctly. Copying the host's counts would have put a 16.0 release's
revisions into a 13.0 row, which is the way a modern answer becomes a wrong one.

## 5. What this port does with a request whose work it cannot do

`VNHandlers.m`'s `charon_vision_failure` answers `VNErrorNotImplemented` for every request it cannot
run, and `VNErrorUnsupportedRevision` for a revision the port's own table does not carry. That is
where a request of this slice ends when a handler runs one, and it is why a class row here says the
class is there and answers what a caller can test, rather than that the request works.

## 6. Three defaults a fresh ivar would have got wrong

Opening a class whose SDK header declares a property makes clang synthesise that property's accessors
onto a new ivar, and a new ivar holds zero. That is the right answer for most of what these classes
declare -- `string`, `confidence`, `elementType`, `elementCount`, `data`, `salientObjects`,
`customWords`, `recognitionLevel` (whose `VNRequestTextRecognitionLevelAccurate` is 0),
`minimumTextHeight` (0.0) and `automaticallyDetectsLanguage` (NO) all start at the value their own
headers document -- and it is the wrong answer for three, which `Vision130.m` writes down:

| member | zero is | the documented default | where the default is written |
| --- | --- | --- | --- |
| `VNDetectHumanRectanglesRequest.upperBodyOnly` | NO | **YES**: "the request is setup to detect upper body only" | `initWithCompletionHandler:` |
| `VNGenerateImageFeaturePrintRequest.imageCropAndScaleOption` | `CenterCrop` | **`ScaleFill`**, which is enumeration value **2** and not 0 | `initWithCompletionHandler:` |
| `VNRecognizeTextRequest.usesLanguageCorrection` | NO | **not declared** by the 16.4 header this package compiles against, so it is left at NO and not guessed | the object, in a comment |

The third is the one that is not fixed, and it is left unfixed on purpose: the header that ships in
this SDK says nothing about it, and no release answers it here because no release this port deploys
on carries Vision at all. A `YES` written in from memory would be an unmeasured value; a `NO` that
the object says out loud is at least a stated one. Nothing can observe the difference either way,
because the request cannot be run.

That is also the whole of what the compile for armv7 is good for beyond the warnings: it is what found
the three. A Mac Catalyst build of the same source is silent about all of it.

## 7. The members these classes carry, and why none of them needs a row of its own

`Vision130.m` defines 34 members, which `nm` on its armv7 object reads out one by one. None of them
is named by a registry row of its own, and none of them needs to be: `entry_of` in
`modules/apple/backports.lua` falls back to the row of the class a member belongs to, because a class
row answers for the members of a class the port defines wholly, and none of these twelve classes is
one a release carries. That is not an assumption -- it is the tree's own reader asked directly:

```
CHARON_ROOT=<worktree> REGISTRY_ROOT=<worktree>/packages/a/apple-backports \
MEMBERS=<the nm output> xmake l tools/vision/check-rows.lua
```

```
members checked: 34 | answered by a row of their own: 0 | answered by another row: 34 | UNANSWERED: 0
```

The same shape is already in the tree: `VNRequests.o` defines `-[VNDetectRectanglesRequest
initWithCompletionHandler:]` and `-[VNImageBasedRequest initWithCompletionHandler:]`, and neither is a
row, while `VNDetectRectanglesRequest.minimumAspectRatio` and its six siblings are. Both are answered
by the class's own row.
