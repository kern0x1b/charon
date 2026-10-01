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

### 4.1 One class of these will not instantiate here, and nil answers every question

The same probe asks what a fresh instance of each of the observation classes answers for the methods
their own headers declare. Read the `alloc/init` lines FIRST, because they decide what the rest of
the block means:

```
alloc/init VNRecognizedText                   gave an object
alloc/init VNRecognizedTextObservation        gave an object
alloc/init VNFeaturePrintObservation          GAVE NIL
alloc/init VNSaliencyImageObservation         gave an object
alloc/init VNRecognizeTextRequest             gave an object
alloc/init VNNoClassOfThisName (the control)  no class, nil either way

fresh VNRecognizedText boundingBoxForRange:{0,0} = nil, error = none
fresh VNRecognizedText boundingBoxForRange responds: responds
fresh VNRecognizedTextObservation topCandidates:10 = 0 candidates, topCandidates:0 = 0, responds: responds
fresh VNFeaturePrintObservation computeDistance to itself = NO, distance = -1.000000, error = none
fresh VNFeaturePrintObservation elementType = 0 elementCount = 0 data = nil, responds: no selector
VNRecognizedText carries 14 method(s): string requestRevision hash initWithCoder: confidence .cxx_destruct isEqual: copyWithZone: debugDescription encodeWithCoder: boundingBoxForRange:error: crOutput initWithRequestRevision:CRImageReaderOutput: setRequestRevision:
VNRecognizedTextObservation carries 13 method(s): vn_cloneObject hash initWithCoder: .cxx_destruct isEqual: text setText: encodeWithCoder: isTitle setTextObjects: setIsTitle: textObjects topCandidates:
VNFeaturePrintObservation carries 5 method(s): elementType elementCount data computeDistance:toFeaturePrintObservation:error: computeDistanceToFeaturePrintObservation:error:
```

**The three `computeDistance` lines and the `elementType` line are a measurement of nil and are not
measurements of Vision.** `[[VNFeaturePrintObservation alloc] init]` gives nil on this host, so the
call answered `NO`, left the caller's `-1.0f` where it was, and set no error -- which is precisely
what messaging nil does, and what a reader would have written down as Apple's answer if the `alloc/init`
line had not been beside it. It was caught here by asking `respondsToSelector:` on the same object and
being told `no selector` while `class_copyMethodList` on its class listed the method in the same run:
`instancesRespondToSelector:` said yes and the instance said no, and the only thing that reconciles
those two is an object that is not an instance of that class. **The `alloc/init` line is now in the
probe, above the questions, and the control beside it is a name that is no class at all**, so that
this reading cannot be mistaken for an answer again.

What is left of that block is Apple's own, and it is what the port answers:

- **`boundingBoxForRange:error:` on a `VNRecognizedText` with nothing in it is `nil` with no error.**
  The class does instantiate here, so this is Apple's answer and not nil's.
- **`topCandidates:` on a `VNRecognizedTextObservation` with nothing in it is an empty array**, for a
  count of 10 and for a count of 0 alike.
- **`computeDistance:toFeaturePrintObservation:error:` cannot be measured against Apple's own Vision
  on this host at all**, and the reason is the one line above. `-computeDistance` is still defined and
  the port's answer is written down beside the reason (section 7).

The three `carries` lines are the runtime's own method lists, and they are here for two reasons: they
name the selector spellings the runtime holds (`crOutput` and
`computeDistanceToFeaturePrintObservation:error:` on the first and third, neither of which any 13.0
header declares, are this host's own later additions), and `class_copyMethodList` is the measurement
that settled the nil question above. `VNRecognizedTextObservation`'s `text`, `textObjects` and
`isTitle` are likewise 14.0 and 16.0 and are not 13.0.

### 4.2 The three catalogue methods, and the one of them the port can answer

```
knownClassificationsForRevision:1 = 1303 name(s), error = none
    the first is "abacus" and the last is "zucchini"
knownAnimalIdentifiersForRevision:1 = 2 identifier(s), error = none
    they are Cat,Dog
supportedRecognitionLanguagesForTextRecognitionLevel:accurate revision:1 = 1 language(s), error = none
knownClassificationsForRevision:2 = 1303 name(s), error = none
    the first is "abacus" and the last is "zucchini"
knownAnimalIdentifiersForRevision:2 = 2 identifier(s), error = none
    they are Cat,Dog
supportedRecognitionLanguagesForTextRecognitionLevel:accurate revision:2 = 8 language(s), error = none
knownClassificationsForRevision:3 = 0 name(s), error = com.apple.Vision 16
knownAnimalIdentifiersForRevision:3 = 0 identifier(s), error = com.apple.Vision 16
supportedRecognitionLanguagesForTextRecognitionLevel:accurate revision:3 = 33 language(s), error = none
```

Three class methods, each deprecated in 15.0 and each annotated `ios(13.0, 15.0)` in the header, so
all three are 13.0 API. **They are not printed in full** -- the classification catalogue is 1303 names
-- because the count is the whole of what a port that carries no such catalogue can be compared
against, and a reader who wants the names asks Vision for them.

- **`knownAnimalIdentifiersForRevision:` answers `Cat,Dog`, two of two, for every revision it carries.**
  That is the whole of the list and not a narrowing of it, and the port's answer is the two
  identifiers `Vision130.m` exports, whose own values section 3 read out of the 16.0 image. A revision
  it does not carry answers nothing and `com.apple.Vision` **16**, which is `VNErrorUnsupportedRevision`
  and the same code the port's request path already refuses an uncarrried revision with.
- **`knownClassificationsForRevision:` answers 1303 names and `supportedRecognitionLanguages…:` answers
  1, 8 and 33 language codes.** These are catalogues of models this port has not got: there is no
  classifier behind `VNClassifyImageRequest` and no text recogniser behind `VNRecognizeTextRequest`, and
  a list of another release's copied in would be a wrong list rather than a missing one. Section 7 says
  what a caller gets instead.

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
headers document -- and it is the wrong answer for three, which `Vision130.m` writes down. **Each of
the three has a row of its own, and the row is where a reader of the property looks:**

| member | row | zero is | what it answers instead |
| --- | --- | --- | --- |
| `VNDetectHumanRectanglesRequest.upperBodyOnly` | `registry/Vision/ios11.json` | NO | **YES**: "the request is setup to detect upper body only" |
| `VNGenerateImageFeaturePrintRequest.imageCropAndScaleOption` | `registry/Vision/ios11.json` | `CenterCrop` | **`ScaleFill`**, which is enumeration value **2** and not 0 |
| `VNRecognizeTextRequest.usesLanguageCorrection` | `registry/Vision/ios11.json` | NO | NO, and the row says why NO is not Apple's default |

The third is the one that is not fixed, and it is left unfixed on purpose: the header that ships in
this SDK says nothing about it, no release this port deploys on can be asked because none of them
carries Vision at all, and nothing here runs a text recognition that would set it. A `YES` written in
from memory would be an unmeasured value; a `NO` the row states out loud, together with the three
things that are known and the one that is not, is at least an honest one. Nothing can observe the
difference either way, because the request cannot be run.

The two that are fixed are now **measured answers** rather than transcriptions: the port's own classes
built under names of their own and read back, which is section 8.

That is also the whole of what the compile for armv7 is good for beyond the warnings: it is what found
the three. A Mac Catalyst build of the same source is silent about all of it.

## 7. The members these classes carry, and why none of them needs a row of its own

`Vision130.m` defines 39 members, and this section names the command that counts them, because a
member count without one is a number a reader cannot check. `.cxx_destruct` is dropped: clang emits one
per class with an ivar and no SDK header declares it.

```
python3 - <<'PY'
import re, subprocess
out = subprocess.run(["nm", "-m", OBJECTS .. "/Vision130.m.o"], capture_output=True, text=True).stdout
members = set()
for line in out.splitlines():
    m = re.search(r"\[Thumb\] ([-+])\[([A-Za-z0-9_]+)(?:\(([A-Za-z0-9_]+)\))? ([^\]]+)\]", line)
    if not m or m.group(4) == ".cxx_destruct":
        continue
    members.add("%s[%s %s]" % (m.group(1), m.group(2), m.group(4)))
open("Vision130-members.txt", "w").write("\n".join(sorted(members)) + "\n")
print("members:", len(members))
PY
```

```
members: 39
```

`OBJECTS` is the armv7 objects folder of a 6.1.3 build of this library, which
`.agent-work/runs/vision13-r13/armv7-one-library.lua` produces for one library in the seconds a
whole-tree gate build takes minutes:

```
CHARON_ROOT=<worktree> xmake l .agent-work/runs/vision13-r13/armv7-one-library.lua Vision <objects> 6.1.3
```

**The earlier reading of this section was wrong in both numbers and it is corrected here.** It said 34
members and "every one of them by the row of the class it belongs to". Re-measured, the object carries
39 and three of them are answered by rows of their own -- the precision and recall triple of
`VNClassificationObservation`, which are the only three of these 39 that a registry row names in its
own right. `nm -m`, not `nm -gU`: a method implementation on a class the port opens is `non-external`,
so `nm -gU` on this object lists 55 symbols of which NONE is a method, and a count taken that way
answers a different question.

None of the 39 needs a row of its own, and that is not an assumption -- it is the tree's own reader
asked over the list the command above writes:

```
CHARON_ROOT=<worktree> REGISTRY_ROOT=<worktree>/packages/a/apple-backports \
MEMBERS=<worktree>/Vision130-members.txt xmake l tools/vision/check-rows.lua
```

```
members checked: 39 | answered by a row of their own: 3 | answered by another row: 36 | UNANSWERED: 0
```

`entry_of` in `modules/apple/backports.lua` falls back to the row of the class a member belongs to,
because a class row answers for the members of a class the port defines wholly, and none of these
twelve classes is one a release carries. `check-rows.lua` calls that same function, so the 36 is the
tree's rule and not a copy of it.

The same shape is already in the tree: `VNRequests.o` defines `-[VNDetectRectanglesRequest
initWithCompletionHandler:]` and `-[VNImageBasedRequest initWithCompletionHandler:]`, and neither is a
row, while `VNDetectRectanglesRequest.minimumAspectRatio` and its six siblings are. Both are answered
by the class's own row.

### 7.1 A property is synthesised; a method is not, so every declared method is written down

Opening a class makes clang synthesise every **property** its header declares onto a new ivar, and
nothing at all for a **method**. So every property of these twelve classes is answered without a line
and every method had to be written down: a caller that sends one this object does not define does not
get a wrong answer, it loses the process to an unrecognised selector. **Nine methods are declared by
the 13.0 headers of these twelve classes**, read out of the SDK the package compiles against with

```
for h in VNClassifyImageRequest VNRecognizeAnimalsRequest VNRecognizeTextRequest VNFaceObservationAccepting; do
    awk '/^@interface/,/^@end/' "$SDK/System/Library/Frameworks/Vision.framework/Headers/$h.h" | grep -E '^[-+] \('
done
```

plus the `@interface` blocks of `VNRecognizedText`, `VNRecognizedTextObservation`,
`VNFeaturePrintObservation` and `VNSaliencyImageObservation` in the same SDK's `VNObservation.h` -- and
that last of the four declares no method at all. The nine:

| method | declared at | what this port does |
| --- | --- | --- |
| `-[VNRecognizedText boundingBoxForRange:error:]` | 13.0 | `nil`, no error -- Apple's own answer for the same class with nothing in it (4.1) |
| `-[VNRecognizedTextObservation topCandidates:]` | 13.0 | an empty array -- Apple's own answer for the same class with nothing in it (4.1) |
| `-[VNFeaturePrintObservation computeDistance:toFeaturePrintObservation:error:]` | 13.0 | `NO`, both out-parameters untouched -- **not measured against Apple**, whose class does not instantiate here (4.1) |
| `+[VNRecognizeAnimalsRequest knownAnimalIdentifiersForRevision:error:]` | 13.0, deprecated 15.0 | the two identifiers this library exports, and a revision the port's table does not carry refused with `VNErrorUnsupportedRevision` (4.2) |
| `+[VNClassifyImageRequest knownClassificationsForRevision:error:]` | 13.0, deprecated 15.0 | **not written down** -- 1303 names (4.2) |
| `+[VNRecognizeAnimalsRequest supportedIdentifiersAndReturnError:]` | 15.0 | not written down, and not 13.0 at all |
| `+[VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:revision:error:]` | 13.0, deprecated 15.0 | **not written down** -- 1, 8 and 33 language codes (4.2) |
| `+[VNClassifyImageRequest supportedIdentifiersAndReturnError:]` | 15.0 | not written down, and not 13.0 at all |
| `+[VNRecognizeTextRequest supportedRecognitionLanguagesAndReturnError:]` | 15.0 | not written down, and not 13.0 at all |

The three 15.0 rows are listed so that their absence is read as a decision: they are not 13.0 API, and
`introduced` in this registry means what the SDK annotates.

**The three that are left open are left open on purpose, and here is what a caller gets.** Each is a
catalogue method: it reports what a model can recognise, and this port has no model behind
`VNClassifyImageRequest` or `VNRecognizeTextRequest`. A list written in from another release would be
a wrong list -- this host's own catalogue is a generation past 13.0 and its own counts already differ
between revisions, which is exactly what the revision table above warns about -- and a wrong list is
worse than a missing one, because a caller cannot tell the difference between the two and will filter
on identifiers nothing here can produce. So `+knownClassificationsForRevision:error:`,
`+supportedIdentifiersAndReturnError:` and `+supportedRecognitionLanguagesForTextRecognitionLevel:revision:error:`
raise an unrecognised selector on this port, and the port's own probe says so rather than leaving a
reader to infer it:

```
VNClassifyImageRequest             +knownClassificationsForRevision:error:                     answered: no, a caller sending it gets an unrecognised selector
VNRecognizeAnimalsRequest          +supportedIdentifiersAndReturnError:                        answered: no, a caller sending it gets an unrecognised selector
VNRecognizeTextRequest             +supportedRecognitionLanguagesForTextRecognitionLevel:revision:error: answered: no, a caller sending it gets an unrecognised selector
```

Nothing is written to `coordination/crutches.md` for these three, because they are not a workaround
for a cause that can be fixed: the cause is that the recognisers are Apple's own models and no source
for Vision exists at all (`coordination/corpus/sources.md`). This is the honest end for them and the
question only the owner can answer is whether a band should carry a row per missing method so that the
registry says so rather than the facts page.

### 7.2 What release-split says about this library's objects, and what it cannot see

Run over the armv7 objects of the seven Vision sources of a 6.1.3 build, which is the whole library
except the three the build generates:

```
xmake l tools/release-split.lua <objects> <split.tsv>
```

```
CharonVisionBilinear.c.o   0 symbols   (no exported symbol at all: every symbol is internal)
VNConstants.m.o            29          11.0
VNHandlers.m.o              4          11.0
VNObservations.m.o         34          11.0
VNRecognizedObjectObservation.m.o  2   12.0
VNRequests.m.o             34          11.0
Vision110.m.o               2          11.0
Vision130.m.o              25          16.0
release-split: clean, every object file's symbols first-appear in one release (8 files, 130 symbols, 50 releases checked)
```

**`Vision130.m.o` is unchanged by this section's four methods: 25 symbols before them and 25 after.**
They are `non-external`, so `nm -gU` does not see them, which is the same reason `nm -gU` sees no method
at all in section 7 above. What release-split certifies here is the twenty-five symbols a caller binds
by name -- twelve `_OBJC_CLASS_$_`, twelve `_OBJC_METACLASS_$_` and `VNElementTypeSize` -- and their
first appearance, which is 16.0 for every one of them: after 12.0 and by 16.0, because the held set has
no 13.0, 14.0 or 15.0 in it (section 2).

**The three generated protocol objects are a blind spot, and it is measured rather than asserted.**
`VNRequestProgressProviding` is the only protocol row of 13.0, and the build writes
`VisionBackportsProtocols13.0.m` for it into `objects/Vision/protocols/`, one folder below the one
release-split walks. Asked for by name:

```
xmake l tools/release-split.lua <objects>/Vision/protocols <out> "$(cat <objects>/sdkdir)"
```

```
release-split: clean, every object file's symbols first-appear in one release (3 files, 0 symbols, 50 releases checked)
```

**Zero symbols.** That is `release-split`'s own `EXCLUDED` table doing what it is written to do --
`__OBJC_PROTOCOL_$_` is on it, because that symbol appears in no release's export surface -- and it
means the tool's "clean" here certifies nothing at all. It is the blind spot the script's own header
warns about, met exactly. The symbol is not a release export by measurement either:

```
python3 tools/cache-index/first-rung.py _OBJC_PROTOCOL_\$_VNRequestProgressProviding
```

```
_OBJC_PROTOCOL_$_VNRequestProgressProviding	NONE
```

so the exclusion is right and there is no mixed release here to find. What the row needs is not a
symbol but the metadata, and that is measured where it is linked -- `nm -a` on the
`libVisionBackports.dylib` of a 6.1.3 build of this tree:

```
__OBJC_PROTOCOL_$_VNRequestProgressProviding   (d, in __DATA)
__OBJC_$_PROTOCOL_INSTANCE_METHODS_VNRequestProgressProviding
```

and the protocol name itself is one of the strings in the image. `NSProtocolFromString` answering for
it by name is measured in section 4.

## 8. What a caller gets about the conformances, measured on the port's own classes

A class whose SDK header names a protocol is put in that protocol's conformance list **by the
declaration alone**. Nothing has to adopt it: declaring `@implementation VNRecognizeTextRequest` was
enough, and no adoption appears anywhere in this library. So `-conformsToProtocol:` and
`-instancesRespondToSelector:` answer for the protocol whether or not this port wants it to, and the
members it declares have to exist or the class answers YES and then raises.

Three of the twelve were in that position. The port's classes are built here under names of their own,
so an answer cannot come from the Vision of this host, and a name that is no class at all is asked for
as the control:

```
xcrun clang -target arm64-apple-ios15.0-macabi -isysroot "$(xcrun --show-sdk-path)" \
    -iframework "$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -w -include rename.h -I packages/a/apple-backports/Vision \
    -framework Foundation -framework Vision -framework CoreGraphics -framework CoreImage \
    -framework CoreVideo -framework CoreML -framework ImageIO \
    tools/vision/conforms130.m packages/a/apple-backports/Vision/*.c \
    packages/a/apple-backports/Vision/*.m -o conforms130 && ./conforms130
```

`rename.h` is the header `tests/backports/host/vision/run.sh` writes from
`registry/Vision/ios11.json`; the whole recipe is in the probe's own first comment.

```
CharonVNDetectFaceCaptureQualityRequest        conforms130            conforms:  VNFaceObservationAccepting  NSCopying
CharonVNRecognizeTextRequest                   conforms130            conforms:  VNRequestProgressProviding  NSCopying
CharonVNRecognizedText                         conforms130            conforms:  VNRequestRevisionProviding  NSSecureCoding  NSCopying
CharonVNDetectFaceLandmarksRequest             conforms130            conforms:  VNFaceObservationAccepting  NSCopying
VNNoClassOfThisName (the control)              nil class              conforms to nothing: no

VNRecognizeTextRequest progressHandler responds: responds, indeterminate = NO, usesLanguageCorrection = NO
VNRecognizedText supportsSecureCoding = YES, string = nil, confidence = 0.000000, requestRevision = 0
VNDetectHumanRectanglesRequest upperBodyOnly = YES
VNGenerateImageFeaturePrintRequest imageCropAndScaleOption = 2 (ScaleFill is 2, CenterCrop is 0)
```

Every answer says `conforms130`, which is the probe's own binary and not `Vision`, and the control
row is a `nil` class that conforms to nothing. Three things come out of it:

- **`VNRecognizeTextRequest` conforms to `VNRequestProgressProviding`, and its two members answer.**
  `progressHandler` responds and `indeterminate` is `NO` -- the same `NO` this host's own Vision
  answers for the class, which is section 4's measurement. The handler is never called, because the
  request cannot be run here. Two registry rows used to say the port does not adopt the protocol on
  this class; it did not adopt it, and it does not have to, because the header already conforms it.
  Both rows now say what the probe measured.
- **The two defaults of section 6 are answers, not transcriptions**: `upperBodyOnly` reads `YES` and
  `imageCropAndScaleOption` reads `2`.
- **`VNRecognizedText` conforms to three protocols** and answers all of them: `supportsSecureCoding`
  is `YES`, and `string`, `confidence` and `requestRevision` read nil, 0 and 0 because nothing of
  this port makes one.

## 9. Why registry-coherence.py could not judge three of these rows, and it is not their length

`coordination/registry-coherence.py` reported, twice, `no sample answered for` the three rows this
band added rather than flipped:

```
FAIL  registry coherence: no sample answered for VNDetectHumanRectanglesRequest.upperBodyOnly
FAIL  registry coherence: no sample answered for VNGenerateImageFeaturePrintRequest.imageCropAndScaleOption
FAIL  registry coherence: no sample answered for VNRecognizeTextRequest.usesLanguageCorrection
```

It is not the length of those rows, and the earlier theory that it was -- that a long row crowds out
the ones around it -- is wrong and was retracted in the commit that shortened them. Asking the tool's
own two functions over the same range is what settles it:

```
python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("rc", os.path.expanduser("~/Git/projects/ios/coordination/registry-coherence.py"))
rc = importlib.util.module_from_spec(spec); spec.loader.exec_module(rc)
rows = rc.changed_rows(".", BASE, "HEAD")
prompt = rc.build_prompt(rows, rc.definitions(".", BASE, "HEAD"))
print([a["api"] for _, b, a in rows if b is None and a["api"] not in prompt])
PY
```

```
collected: 42 | new at the tip: 22 | removed: 19 | flipped: 1
  flipped   1 rows,  0 of their apis absent from the prompt
  NEW      22 rows,  3 of their apis absent from the prompt
      absent: VNDetectHumanRectanglesRequest.upperBodyOnly
      absent: VNGenerateImageFeaturePrintRequest.imageCropAndScaleOption
      absent: VNRecognizeTextRequest.usesLanguageCorrection
```

**22 new rows, and 19 of their api strings are in the prompt anyway.** Those 19 are in it as
`REMOVED by this patch` lines -- `changed_rows` also collects the 19 rows this band took out of
`absent_Vision.json`, and `build_prompt` prints a removal's api. The three that are absent are the
three this band *added*, and the cause is in `build_prompt`:

```python
if before is None or isinstance(before, str):
    parts.append(f"  {path}: file is {'added' if before is None else 'unreadable at the base'}")
    continue
```

`before is None` is meant to mean *this file did not exist at the base*. `changed_rows` also produces
it for *this row did not exist at the base*, and the two are not told apart, so every row a patch adds
is answered with `ios11.json: file is added` -- printed 22 times, once per added row -- and the row's
own fields never reach the model. The tool then reports the consequence as its own failure, which is
the right thing to do and the wrong reason to report it: the rows are not unanswerable, they are
unasked.

The 40-row cap fails on the same range for a related reason: it counts 42, of which 19 are removals,
and a removal has no fields that can disagree with anything. The rows a reviewer would actually be
shown are the 22 added and 1 flipped, which is 23.

Both are in `coordination/`, which is not this band's to change. What the band can do is state them
where the next reader of its rows will find them, which is here.
