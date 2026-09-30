# SensorKit, on a release that collects nothing

SensorKit arrived in iOS 14. This port deploys to iOS 6.1.3, and the release's armv7 6.1.3 cache
carries **no SensorKit surface at all**: `binary_inventory` at `modules/apple/objc.lua:395`, run over
the cache, finds no `SR*` class and no `SR*` symbol. There is no daemon, no usage database, and no
store a payload could be read out of. Everything below is that one fact and what follows from it.

## The witnesses this page's numbers come out of

Four paths, and every count below is one of their outputs. A number on this page that names none of
them is not evidence, and this page used to carry several. There are five now:

| what it answers | the path | what a run of it prints |
| --- | --- | --- |
| the 57 string constants, the port's against the host's own SensorKit | `tests/backports/host/sensorkit-names/run.sh` | `sensorkit-names: 57 names compared, 0 differing`, then three plants and the empty control |
| the four time functions, both sides in one binary | `tests/backports/host/sensorkit/run.sh` | the three relations, and the port's side `1, 1, 1` |
| which of the delegate's ten the reader sends, in the source and in the armv7 object | `tests/backports/host/sensorkit-reader/run.sh` | `4 of 10 protocol methods sent`, `4 of 10 protocol selectors in the object`, 5 plants |
| what one cache of one release carries, and what one image of it exports | `modules/apple/objc.lua`, `binary_inventory` at `:395` | the class and symbol inventory of a cache or an image |
| one symbol's release of first appearance, over the held ladder | `tools/cache-index/first-rung.py` | one TSV line per name, or `NONE` |

`tools/cache-index/first-rung.py` answers **presence, not version**, and that limit is load-bearing
here: the ladder it walks (`dyld.held_ladder` in `modules/apple/dyld.lua`) has a hole above 12.0, so a
`NONE` from it for a SensorKit name is not evidence about the release that introduced it and is not
used on this page as such. What introduced a SensorKit name comes from the SDK's own
`API_AVAILABLE(ios(...))` on the declaration, and every row's `source` names the header and the line.

## What is real, and what is not

**The 38 classes are real value objects.** Each is made, and each of its properties is kept in a
store keyed by the property's own name — the store `CharonValueStore.h` describes and MetricKit already
uses. A property reads back exactly what an application put there, and the archiver walks the same
property list, so a value archived and read back lands under the name it went in under. Nothing in this
framework is measured by the port: there is no sensor to measure.

**The four time functions are real, over the clocks the release actually has**, and one limit is
named rather than papered over. Measured over the cache's 158 520 exports: `mach_absolute_time`,
`mach_timebase_info` and `CFAbsoluteTimeGetCurrent` are all present and **`mach_continuous_time` is
not** — it arrived in iOS 10. So:

- `SRAbsoluteTimeGetCurrent()` reads `mach_absolute_time`, which **stops while the device sleeps**.
  The header promises "This timestamp ticks across sleeps and reboots", and this release cannot keep
  that promise: the clock that would is a symbol it does not have. The reading is still monotonic, so
  it never goes backwards and the two conversions are exact inverses of it.
- the two bases are joined by **one anchor**, read from the release's own `CFAbsoluteTimeGetCurrent`
  the first time it is needed. Neither number is invented: the anchor is a wall-clock reading the
  release produced, and every conversion after it is arithmetic on the two clocks it has.
- `SRAbsoluteTimeFromContinuousTime` takes the nanosecond count its name says and measures it from
  this boot session's anchor, which is the header's own rule about where a continuous time may come
  from. Nothing here can check that a count came from this session, and the code says so rather than
  pretending to.
- the wall-clock pair is the header's stated behaviour: if the system time is five seconds fast, so is
  the answer.

**`SRSensorReader` answers as the SDK documents for a device with no permission, and that is denied.**
Not `notDetermined` — that would promise a prompt still to come, and none is coming, because there is
no store behind the question. Not `authorized` — that would claim data there is not. There is nothing
for a user's answer to be about, and `denied` is what that is. Each of the three ways of asking the
system to collect something is answered with the SDK's *own* failure callback rather than left hanging,
and `+requestAuthorizationForSensors:completion:` **runs** its block with SensorKit's own
`SRErrorDataInaccessible` (read out of the 16.4 `SRError.h`, "Data is not accessible at this time"),
because a caller waiting for a prompt this release never shows would wait forever. `+sharedReader` is
made through `-initWithSensor:`, the only way the header leaves open, with the accelerometer: a reader
for a sensor that exists on some devices and not others, and one that cannot be asked for data either
way. No device list is fabricated.

## The four measurements the build forced, and the four absences that follow from them

The lowered **16.4** SDK this package compiles against is four minor versions behind the one this
package develops against, and the gap is the whole reason `CharonSensorKit.h` exists:

| what the build cannot see | measured how | what the port does |
| --- | --- | --- |
| **19 of the 38 classes** | compiling a probe of all 38 names against the 16.4 headers | declared in `CharonSensorKit.h` — same superclass, selectors, property types, no ivars, and the availability annotations left out, as the other three redeclarations in this package do |
| **15 of 25 property types** | the same probe, then the header compiled and read for collisions | declared; the other ten, including nine integer enumerations the 26.2 headers spell differently from the 16.4 ones, are left to the SDK |
| **13 properties on 6 classes** | a per-class diff of the two headers' property lists | declared in `(CharonSensorKitNNN)` categories, one per release, because a class the SDK declares cannot be declared again |
| **4 property types from frameworks this package does not carry** | a probe naming `ARFaceAnchor`, `SNClassificationResult`, `SFSpeechRecognitionResult`, `SampleType` against the build's headers | **not carried**: `SRFaceMetrics.faceAnchor`, `SRSpeechMetrics.soundClassification`, `SRSpeechMetrics.speechRecognition`, `SRFetchResult.sample`. There is no such type here to answer with, and a property declared over one would read nil for ever |

## The 57 string constants, and why the eighteen newest could not be carried before

All of SensorKit's string constants are **const object-pointer variables**, never macros. `SRSensor`,
`SRDeviceUsageCategoryKey`, `SRPhotoplethysmogramSampleUsage` and
`SRPhotoplethysmogramOpticalSampleCondition` are each a typedef of `NSString *`, and each constant is
declared `SR_EXTERN <type> const <name>` with no initializer anywhere. So no header this package
builds against spells a value, and the release's own cache holds no SensorKit symbol to read one from:
the value has to come from somewhere, and the only honest somewhere is Apple's own framework.

**It is on the host.** `/System/Library/Frameworks/SensorKit.framework` exports every one of them, so
`tests/backports/host/sensorkit-names/run.sh` measures each value rather than writing it down: one
process `dlopen`s the framework and `dlsym`s each name **dereferencing once** — these are variables,
so `dlsym` returns the address of the variable and the address of the variable is the string — and
another process links the port's own definitions and prints those. The two are independent because an
object wins at link time.

A run of it prints:

```
sensorkit-names: 57 names compared, 0 differing
sensorkit-names: 57 names compared, 57 differing      <- the all-wrong plant
the one-wrong plant of SensorKitNames14.m is red and names exactly 1 row: SRDeviceUsageCategoryBooks
the one-wrong plant of CharonSensorKitNames.h is red and names exactly 1 row: SRSensorSiriSpeechMetrics
sensorkit-names: 0 names compared, 57 differing  <- COMPARED NOTHING   <- the empty-host control
```

Those three plants and that control are what make the comparison falsifiable rather than decorative: a
value that differs is red, a name one side did not print is red, and **a host file with no rows at
all is red**, so a run that compared nothing cannot come out green. There are two one-wrong plants
rather than one because there are two port-side sources now, and a mutation that reached only the
first would leave the second unwatched.

The **57** is `names.txt`, and the count is not the interesting part. The interesting part is the
eighteen that were `absent` before this change and are `implemented` now, in six objects:

| release | the object | the constants | what the host's framework holds |
| --- | --- | --- | --- |
| 15.0 | `SensorKit150.m` | `SRSensorSiriSpeechMetrics`, `SRSensorTelephonySpeechMetrics` | `com.apple.SensorKit.speechMetrics.siri`, `…telephony` |
| 15.4 | `SensorKit154.m` | `SRSensorAmbientPressure` | `com.apple.SensorKit.ambientPressure` |
| 16.4 | `SensorKit164.m` | `SRSensorMediaEvents` | `com.apple.SensorKit.mediaEvents` |
| 17.0 | `SensorKit170.m` | `SRSensorWristTemperature`, `SRSensorHeartRate`, `SRSensorFaceMetrics`, `SRSensorOdometer` | `com.apple.SensorKit.wristTemperature`, `…heart.rate`, `…faceMetrics`, `…odometer` |
| 17.4 | `SensorKit174.m` | `SRSensorElectrocardiogram`, `SRSensorPhotoplethysmogram`, and the six `SRPhotoplethysmogram…` | `com.apple.SensorKit.ECG`, `com.apple.SensorKit.PPG`, and `SignalSaturation`, `UnreliableNoise`, `ForegroundHeartRate`, `DeepBreathing`, `ForegroundBloodOxygen`, `BackgroundSystem` |
| 26.0 | `SensorKit260.m` | `SRSensorAcousticSettings`, `SRSensorSleepSessions` | `com.apple.SensorKit.hearing.acousticSettings`, `com.apple.SensorKit.sleep.sessions` |

Two of these deserve their own sentence, because they are the cases a rule written from the shape of
the name would have got wrong, and the harness is the only reason they are carried at all:

- **the six photoplethysmogram values are the SUFFIX of the constant's own name, not the name.**
  `SRPhotoplethysmogramSampleUsageDeepBreathing` is the string `DeepBreathing`. They look exactly
  like `#define NAME @"NAME"` constants and are not macros at all, which is why the older version of
  this page refused to guess them: there was nothing to check a guess against. There is now.
- **two of the values are Apple-internal shapes the name does not suggest**: `SRSensorHeartRate` holds
  `com.apple.SensorKit.heart.rate`, and `SRSensorElectrocardiogram` and `SRSensorPhotoplethysmogram`
  hold `com.apple.SensorKit.ECG` and `com.apple.SensorKit.PPG`. The port does not construct these
  strings; it carries what the host's framework holds, and the comparison is what says they are right.

**The values are the HOST's, not a device's.** No iOS device has been asked what its SensorKit holds,
and every row says so in its own `effect`. This is the limit of this measurement and it is a real one.

**Where the values live, and why they are not written six times.** An object carries the API of exactly
one release, so the eighteen belong to six objects; their values, though, are one list, and the
harness has to walk that whole list from a single host-compilable source. They are therefore defined
once, in `CharonSensorKitNames.h`, behind one guard per release: each release object defines its own
guard and imports the header, and the harness's `names-extra.m` defines all six and imports it. One
definition of each string in the tree, read seven ways.

## What the delegate's ten methods are, and which four the port reaches

**There are ten of them, all `@optional`, and the port's reader sends four.** That is the whole shape
of this corner, and the numbers are the SDK 26.2 header's own: `@protocol SRSensorReaderDelegate
<NSObject>` at `SRSensorReader.h:21`, `@optional` at `:22`, and ten declarations between `:40` and
`:84`, the protocol's `@end` at `:86`.

`tests/backports/host/sensorkit-reader/run.sh` is what produces that split, twice over, and its own
output is the claim:

```
sensorkit-reader: 4 of 10 protocol methods sent, 0 failures
sensorkit-reader-object: 4 of 10 protocol selectors in the object, 0 failures
sensorkit-reader: OK - 10 protocol methods, 4 sent and 4 in the object, 5 plants noticed
```

The first line reads the port's own `SRSensorReader.m` and names all ten, SENT or NEVER. The second reads
the **compiled armv7 object** — built `armv7-apple-ios6.1.3` against the 16.4 SDK and dumped with
`otool -v -s __TEXT __objc_methname` — and is a different claim: an object's `__objc_methname` is what
the linker binds `@selector()` references against, so a selector in that section is one the reader can
actually send. Both halves have plants: three change the source (a send removed, a send swapped for one
of the six, the authorization no longer `denied`), a fourth hands the check a reader that sends nothing
at all, and a fifth is the swap again carried through the compiler, so the object check is not merely
agreeing with the source check by construction. All five are noticed.

**Why this is not a differential, and that is measured rather than assumed.** There is no behavioural
oracle for `SRSensorReader` on this machine. The host's own `SensorKit.framework` declares the class and
implements nothing — `respondsToSelector:` is 0 for `+authorizationStatus` and `+sharedReader` — and the
port's `CharonSensorKit.h` cannot be compiled against the host's newer SDK at all: clang answers
`typedef redefinition with different types ('NSInteger' vs 'enum SRAcousticSettingsSampleLifetime')`
for the fifteen enumerations it redeclares, because the host's SensorKit spells them `NS_ENUM`. Building
the port's reader for Catalyst against the 16.4 SDK instead was tried and does not work either, on this
SDK: `Foundation/NSURL.h:10` imports `Foundation/NSURLHandle.h`, which the store's 16.4 SDK does not
carry.

The four, and the six, are these:

| sent by the port's reader | from | why it is the answer |
| --- | --- | --- |
| `sensorReader:startRecordingFailedWithError:` | `-startRecording` | there is no store to start recording into |
| `sensorReader:stopRecordingFailedWithError:` | `-stopRecording` | nothing is recording, so this is a stop that did not happen |
| `sensorReader:fetchingRequest:failedWithError:` | `-fetch:` | no store, no readings, no payload |
| `sensorReader:fetchDevicesDidFailWithError:` | `-fetchDevices` | the device list is the one fetch that could succeed without a database, and the port will not invent one |

Each of the four carries SensorKit's own `SRErrorDomain` and its own `SRErrorDataInaccessible` from
`SRError.h` — "Data is not accessible at this time", which is exactly what is true here — and each is
guarded by `respondsToSelector:` on the delegate, so a subscriber that implements one is messaged and
one that does not is not messaged at all, never messaged wrongly.

| never sent, and why | |
| --- | --- |
| `sensorReader:fetchingRequest:didFetchResult:` | it hands over a result and `-fetch:` has none: the request fails instead |
| `sensorReader:didCompleteFetch:` | it says a fetch finished, and no fetch in this port ever does |
| `sensorReader:didChangeAuthorizationStatus:` | `-authorizationStatus` answers `SRAuthorizationStatusDenied` and nothing writes to it, so there is no change to report |
| `sensorReaderWillStartRecording:` | it says a recording is about to begin, and none ever does |
| `sensorReaderDidStopRecording:` | it says a recording stopped, and `-stopRecording` answers with the failure callback because there was never a recording |
| `sensorReader:didFetchDevices:` | it hands over a device list, and the port will not fabricate one |

Every one of the six is `@optional`, so a conformer may leave it out and the compiler accepts that. A
conformer that implements one is never called, which is the SDK's own behaviour on a device that collects
nothing — **the port does not fabricate a result, a device list or a status change to make a callback
fire**, and that is the line every one of those six rows rests on.

**The protocol itself is now carried**, which it was not before: the delegate is the application's own
object, so nothing in the port adopts `SRSensorReaderDelegate`, and a port that emits a protocol's
metadata only where a class adopts it therefore emitted none — so an application compiled against the
SDK found no such protocol at run time and could not conform to one it declared.
`CharonSensorKitProtocols.h` names it and the object `modules/apple/backports.lua` generates from the
registry row, `SensorKitBackportsProtocols14.0.m`, makes clang emit
`__OBJC_PROTOCOL_$_SRSensorReaderDelegate`. Measured by compiling that generated object for
`armv7-apple-ios6.1.3` against the 16.4 SDK and reading the symbol out of it with `nm -gU`. The header
forward-declares the protocol and lets the umbrella import supply the body, because the 16.4 SDK already
declares it with one — the same shape `CharonMetalProtocols.h` uses — and a forward declaration on its
own is not a protocol: `@protocol X;` emits nothing, and `protocol_getMethodDescriptionCount` on it
would answer 0 for all ten.

**What is still not claimed.** That a device reaches a subscriber. The call test on the emulator has not
been run; what is proven here is that the armv7 object carries the four selectors, the source sends
exactly those four, and each carries SensorKit's own error.

## The four shapes in the source, each forced by something measured

- a class is implemented in the class itself, **except** `SRKeyboardMetrics`, which the SDK declares
  over four categories of its own: a property one of those declares can be neither `@dynamic`-able in
  a category of ours (the name would be declared twice on the class) nor implemented in a class
  implementation, so its 69 such accessors are written out by hand and only the five the class declares
  are `@dynamic`;
- a property the header declares in a category is implemented in that category;
- a property of a class the port *owns* has its class's `@dynamic` name every property the header
  declares for it, whichever release it arrived in — otherwise the compiler auto-synthesises the
  missing ones, and a synthesised getter on a store-backed class reads an ivar nothing ever writes;
- a struct-valued property (`CMTimeRange`, a chromaticity) is an `NSValue` over its own bytes, since
  it can be neither cast out of the store the way an object can nor put in a dictionary.

Six classes the SDK's own headers declare as conforming — `SRDeletionRecord`, `SRDevice`,
`SRMediaEvent`, `SRSupplementalCategory`, `SRFetchRequest`, `SRFetchResult` — carry the three archiving
methods and, where the header says `NSCopying`, `-copyWithZone:`. The obligation is in each class's
own implementation, not in a category: a category *may* satisfy a protocol, but clang checks the primary
class for it, and that is also where a contract belongs.

## The one thing this framework shares with another

`CharonValueStore.h` — the property walk, the conversion table, the archiver walk and the store. Its
recognition test is **"a class that answers `charon_valueForKey:` is one of ours"**, because
SensorKit has thirty-eight value classes and MetricKit has two, every one of both an `NSObject`
subclass: there is no common superclass left to name, and the accessor the store adds is the test both
frameworks already have.

## Not measured, and what a differential could hold

**The host's SensorKit is in the host's SDK, and under Mac Catalyst the `SRSensorReader` class is
declared — and implements nothing.** `respondsToSelector:` is 0 for both `+authorizationStatus` and
`+sharedReader`, and sending either raises `unrecognized selector`. So there is **no oracle for the
reader**: its answers cannot be held to anything but the header, and this file says so rather than
claiming a comparison that is not possible.

What the host *does* answer is the four time functions, and that is the differential that exists
(`tests/backports/host/sensorkit`): one binary carries both, the port's four renamed, and three
relations from the header are asked of each — never backwards, the pair naming the same instant as
`CFAbsoluteTimeGetCurrent` within a second, and the round trip within a microsecond. Two mutations of
the port's file must each change a record.

Two things the host's own answers measured, which is why those relations are the ones chosen:

- **the round trip is not bit-exact, on the host either.** Its measured drift is `1.162e-07` seconds,
  and that is not a defect: an `SRAbsoluteTime` is a `CFTimeInterval`, and a double near 8·10⁸ cannot
  resolve better than about 120 ns. A value that comes back within a microsecond came back exactly as
  far as these clocks can tell, which is all the header claims.
- **two readings in a row may be equal.** The host's own do it, for the same 120 ns. So the relation
  is "never less", and a third reading after a nap must be greater — which both halves satisfy.

**The device call test has not been run.** It would be the one thing that could catch a mistake in the
store's key for a property, and the delivery says so.

**The `NSDate(SensorKit)` category is the same clock on the other side, and its three rows are carried.**
`+[NSDate dateWithSRAbsoluteTime:]`, `-[NSDate initWithSRAbsoluteTime:]` and `NSDate.srAbsoluteTime` are
three wrappers over the two conversions this file already measures — `SRAbsoluteTimeToCFAbsoluteTime` and
`SRAbsoluteTimeFromCFAbsoluteTime`, each the other's inverse through the one anchor — so nothing new is
computed and the numbers are the ones the time functions already answer. The header's declaration is in
`SensorKit.framework/Headers/NSDate+SensorKit.h` of the SDK 16.4, and `SRAbsoluteTime` is
`CFTimeInterval` (`SRAbsoluteTime.h:14`).

`tests/backports/host/sensorkit` now asks three more relations of **both** builds — the round trip through
the two instance methods within a microsecond, a date and the clock agreeing within a second, and two
dates made from two readings never in the wrong order — and the port's side answers 1, 1, 1 on six
consecutive runs.

**A measurement of mine that was wrong, and what it cost.** A probe I wrote to see whether the host's own
build has `+[NSDate dateWithSRAbsoluteTime:]` answered **no**, and I built the comparator on it as an
expected difference. The suite said otherwise: the host has all three. The probe used
`class_getInstanceMethod`, which finds an **instance** method — the class method lives on the metaclass,
so the probe could not see it. That is the second time in these two families a runtime lookup answered a
question it was not asked (`SRSensor*` "0 of 10" from `objc_getClass`, in slice 1). The expected
difference is gone and both sides are held to the same three relations.

**The host's account of that surface, measured through the runtime rather than assumed:**
`SRSensorReaderDelegate` is present on the host and declares **exactly ten** methods, all `optional`,
with the type encodings `v24@0:8@16`, `v32@0:8@16q24`, `v32@0:8@16@24` (×3), `B40@0:8@16@24@32`,
`v40@0:8@16@24@32` and `v24@0:8@16` — so the surface is Apple's and it is exactly the ten rows above.
What this page used to conclude from it — that the port's not declaring the protocol is the measured
right answer — is no longer what the tree does: the protocol is carried now, and the ten are split four
sent and six never sent, each row saying which. The one row of the reader's own surface still `absent`
is `-[SRSensorReader init]`, and the section above says why.

**And the host's relation `roundTripWithinAMicrosecond` is flaky**, which is why the numbers above are
"on six consecutive runs" and not "always": the HOST's own round trip failed once in eight runs of this
suite (`DIFFERS the host's does not satisfy roundTripWithinAMicrosecond ('0')`). The relation is
pre-existing and the host's own; this slice neither added it nor relaxed it, and it is named here
because a gate that runs this suite may catch it red for a reason that is not the port's.

Open source checked: swift-corelibs-foundation 6.x - not used. The arithmetic is Foundation's own
`NSTimeInterval` read through this package's existing conversion pair, and the surface is Apple's.
