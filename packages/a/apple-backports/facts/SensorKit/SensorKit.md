# SensorKit, on a release that collects nothing

SensorKit arrived in iOS 14. This port deploys to iOS 6.1.3, and the release's armv7 6.1.3 cache
carries **no SensorKit surface at all**: `objc.binary_inventory` over the cache finds no `SR*` class
and no `SR*` symbol. There is no daemon, no usage database, and no store a payload could be read out
of. Everything below is that one fact and what follows from it.

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

Two more blocks of absences, for reasons that are the same in kind:

- **the 58 `SRDeviceUsageCategory*` constants.** The SDK declares each as a
  `SRDeviceUsageCategoryKey const SRDeviceUsageCategoryGames` **variable**, not as a macro, so no
  header this package builds against gives the value, and the release's cache has no SensorKit symbol
  to read it from. The port does not invent a value the system would not recognise, so they are not
  carried. This is the one place in the delivery where a reviewer might reasonably have wanted the
  constant's own name — and the SDK's own form is the reason that is not safe here: these are not
  `#define NAME @"NAME"` constants, and unlike MessageUI's usage categories there is nothing to check
  the guess against.
- **the 20 `SRSensorReaderDelegate` methods.** The delegate is the application's own object: no class
  of this port conforms to the protocol, so the port carries no protocol and emits **no
  `__OBJC_PROTOCOL_$_` for it**. The reader still *sends* these messages — that half of the contract
  is implemented and is what the two `didFailWithError:` callbacks above are — but it declares nothing.

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
(`tests/backports/host/sensorkit`): the host's own answers read first, the port's against them, and a
mutation of either must change a record.

**The device call test has not been run.** It would be the one thing that could catch a mistake in the
store's key for a property, and the delivery says so.
