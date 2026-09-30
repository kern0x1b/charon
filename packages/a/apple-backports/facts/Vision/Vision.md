# Vision of iOS 11.0 and later, on releases that have none of it

`libVisionBackports.dylib`, built with the `vision` config, carries the parts of Vision that a release
without Vision can still answer: the request objects, and the constants a caller may name directly. This
file is what the work was read out of, what the store is, and where the constants' values come from.

## What was measured, and from what

**The framework is absent from the port's releases.** Neither the armv7 shared cache of iOS 6.1.3 nor the
one of iOS 4.3 holds a Vision image, and neither exports a name of it. Read with the repository's own
reader, `tools/corpus/dump-cache.lua`, over both caches:

    cache      export lines   Vision   Foundation   UIKit
    6.1.3          264,243        0        1,171    3,147
    4.3            164,907        0          900    2,816

Foundation and UIKit are the controls that say the probe finds what is there: a reader that found nothing
anywhere would prove nothing, and these two are present in both. `PassKit` is a third control and is
counted in 6.1.3 (308) and absent from 4.3, which is correct - PassKit arrived in iOS 6.0 - so it is not
offered as a control for the older rung. **So nothing here is a release's own, and every Vision row is the
port's.** That single fact is why 138 rows are `absent`, and each of those rows' reason cites this page.

**The constants' values are not in the headers.** A declaration such as

    VN_EXPORT VNHumanBodyPoseObservationJointName const VNHumanBodyPoseObservationJointNameNose
        API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0), watchos(14.0));

carries the type, the name and the availability, and **not the value**: an `NS_TYPED_ENUM` string constant's
value lives in the framework image, not in a header line. So a header can say when a constant arrived and
what it is called, and nothing about what it equals. **The name is never the value**, and no value is typed
here.

Where the value comes from, and which release has Apple's own body for the class:

    $ python3 tools/cache-index/first-rung.py VNDetectHumanBodyPoseRequest VNRecognizeAnimalsRequest
    VNDetectHumanBodyPoseRequest   16.0
    VNRecognizeAnimalsRequest      16.0

`first-rung.py` is a PRESENCE oracle, not a version oracle: it says the name is real and which held release
has Apple's own implementation of it. 16.0 is the nearest held release that carries Vision at all - the
held set is dense to 12.0 and then jumps to 16.0 and 18.0, so a name the SDK dates to 13.0 or 14.0 reads as
"16.0" here. The SDK headers and `coordination/corpus/sdk-26.2-surface.tsv` are the VERSION oracle, and
`introduced` comes from them.

## What a caller gets on a release with no Vision

A Vision class is not there: `NSClassFromString` answers nil and a compile-time reference to it crashes. A
Vision constant that this port exports is the framework's own text, so a code path that names it directly,
without a check of the release, links and does not read a null pointer - and then nothing on this release
can act on it, because there is no Vision to act with. Both halves belong in a constant row's `effect`, and
neither half alone is honest.
