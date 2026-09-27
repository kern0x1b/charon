# Intents on a release with no assistant daemon

What `libIntentsBackports.dylib` is, and what each part of it answers on a device whose iOS
carries no `Intents.framework` and no assistant daemon. Every registry entry of this framework
points here.

## What this release has, and what it does not

The device is an iPhone 4S or an iPad 2 on iOS 6.1.3 (and the same builds are gated at 4.3).
There is no `Intents.framework` at all: the framework arrived with iOS 8, and the armv7 caches
this port is built against end at iOS 10.3.4, so the last release that ever had `Intents` is
beyond the newest release any armv7 device can run. There is no `SiriKit`, no assistant
daemon, no intent handler extension host, and no Spotlight index that reads an interaction.

So none of what `Intents` is *for* — the system reading a donation, launching an extension to
handle an intent, asking a user to disambiguate a value, speaking a vocabulary — can happen
here. That is the wall. Everything that does not go through it is implemented, and the seams
say what they are instead of answering as though the system were there.

## The two stores an application really keeps

The brief for this framework is that an application can donate, store and query interactions
and resolve and handle in process. Both stores are real files under **this application's own**
`Application Support/Charon/Intents`, written with
`NSPropertyListSerialization` and read back through the same path
(`CharonIntentsStore.m`), every write and every read on one serial queue, and every failure the
error the file system or the serialisation reported.

* `INInteraction donateInteractionWithCompletion:` stamps the interaction's date interval with
  the moment of the donation, archives it into the store and calls the handler with `nil` — or
  with the error the write failed with. The two `charon_interactions` accessors on
  `INInteraction` read the store back, newest last, and the deletion methods remove by
  identifier, by group identifier and all of them.
* `INVocabulary` writes the phrases an application offers, by type and in order, and
  `charon_vocabularyStringsOfType:` reads a type back.

On a release that does carry `Intents.framework` the release's own framework is linked instead
(`modules/apple/backports.lua`'s band drops this library's objects and re-exports the
framework's symbols), so none of this store is in a process that has the real thing.

## Where a value is read instead of by the system

`INIntentResolutionResult` has no public accessors in the SDK, and none of its subclasses have
any: on a release with Siri the system is the reader, so the result's value is a value the
system reads and an application never sees. Here the application that resolves a parameter is
the reader, so `CharonIntentsResolution.h` declares four accessors on the class — the resolved
value, the values to disambiguate, the value to confirm, and which of the six answers this is —
plus the one method every answer is built with. They are named as Charon's own, collide with
nothing Apple has, and are absent on a release that carries the framework itself.

A resolution result whose value is a value type rather than an object —
`INBooleanResolutionResult`, `INIntegerResolutionResult`, `INDoubleResolutionResult` and the
result classes typed with an enumeration — carries it as an `NSNumber` of the same value: the
base has nowhere to hold a value of the subclass's own type, and the value is what the
parameter was given.

## The classes whose behaviour is more than storage

Ten classes are hand written in `CharonIntents100.m` (the iOS 10.0.1 group) and one in
`CharonIntents110.m` (the 11.0 group); the other 104 of the 10.0.1 group, the 22 of the 10.3
group and the 56 generated classes of the 11.0 group are generated into `IN10_0.m`, `IN10_3.m`
and `IN11_0.m` by `tools/intents/gen-intents.py` from the SDK's own declarations. What is hand
written and why:

* **`INIntent`** makes a UUID string `identifier` where the intent is made. The system assigns
  that identifier when the interaction carrying the intent is donated; there is no system, and
  the store above is keyed by it, so it is made here instead — the same kind of value, at the
  moment the object exists. `intentDescription` is the class's own words with the framework's
  `IN` prefix and `Intent` suffix off (`INSendMessageIntent` reads "Send message"): the SDK does
  not document how the framework derives it and this release has no framework to ask, and nil
  would be the only other answer. `setImage:forParameterNamed:` and `imageForParameterNamed:`
  keep a real map of images by parameter name; `keyImage` returns the first parameter that has
  one, in parameter name order so that it is the same on every call.
* **`INImage`** is an opaque token in the SDK: it has no property and no reader at all. The
  three ways of being made are therefore all there is to implement, and each one really
  obtains what it says. `imageNamed:` resolves the name in the app's own asset catalogue
  through UIKit, which is where the catalogue lives on every release this port covers.
  `systemImageNamed:` is **not carried at all**, and its registry entry says so: the system
  images are SF Symbols, they arrived with iOS 13, and no release this package covers has a set
  of them, so there is no API on this release that could be asked for one and no behaviour to
  implement. A body that returned nil would be answered by the class and would be a claim this
  port cannot make, so the class has no such method, `respondsToSelector:` answers no, and the
  header's own availability mark (iOS 14) is still on it, so a port cannot call it either. `imageWithURL:` reads the URL and answers no image for a URL it cannot read, which is the
  header's own `nullable` on that method.
* **`INPreferences`** answers `INSiriAuthorizationStatusRestricted` for
  `siriAuthorizationStatus`, which is the header's own wording for a system where Siri
  services are restricted and the user cannot change the answer, and it hands the same status
  to `requestSiriAuthorization:`'s handler rather than waiting for a prompt this release cannot
  show. `siriLanguageCode` answers the language the release itself is set to: the SDK defines it
  as the code Siri is configured with, there is no Siri setting to read, and the device's own
  language is the one a voice would use. **This is a divergence and it is deliberate**: a
  release that has Siri answers Siri's setting, not the device's.
* **`INExtension`**'s own surface is empty; the one requirement it inherits from
  `INIntentHandlerProviding` is `handlerForIntent:`, which answers the instance of the loaded
  class that conforms to the intent's own handling protocol (`INRequestRideIntent` is handled by
  something conforming to `INRequestRideIntentHandling`) and responds to `-handleIntent:`, and
  nil where there is none. There is no extension host here to instantiate anything, so the
  lookup is the whole of what it can do.
* **`INPaymentMethod`**, **`INRideCompletionStatus`**, **`INSpeakableString`** and
  **`INIntentResolutionResult`** are described in their registry entries; each of them either
  carries a derived answer (`INRideCompletionStatus`'s six flags and amounts, computed from the
  outcome its factory methods name) or a value Apple's own class keeps in a way this port names.
* **`INParameter`** (iOS 11.0, `CharonIntents110.m`) is a class and a key path, which is all the
  header's own two properties say, so that is what it keeps. `isEqualToParameter:` compares those
  two, and `setIndex:forSubKeyPath:` / `indexForSubKeyPath:` keep a real index per sub key path,
  answering `NSNotFound` for one that was never given an index — an `NSUInteger` return has no
  other way of saying there is none. `-[INInteraction parameterValueForParameter:]` reads the
  intent's value by that key path, **one component at a time and each asked for by name first**,
  because a key-value lookup of a path the object has no accessor for raises: a path the intent
  does not have answers nil.

Two shapes of resolution result the iOS 11.0 group adds:

* **A result that wraps another result.** Five classes take a resolution result in their
  designated initialiser and expose no value of their own —
  `INSendPaymentPayeeResolutionResult` takes an `INPersonResolutionResult`, and the four others
  of that shape. The wrapper answers **what the result it was given answers**, status included,
  so its whole state is taken rather than re-derived: a caller that resolves a payee must get the
  answer the person result gave. That is one method on the base,
  `-charon_adoptResolutionOf:`, and the generator emits the call when a parameter's type is a
  resolution result.
* **`+unsupportedForReason:`** (also iOS 11.0, on those five and on every later group's
  equivalent). The reason is an enumeration and the classes expose **no reader for it in their own
  headers** — on the releases that added the method, the system is the only one who reads it, and
  this release has none. A result that swallowed the reason would answer "unsupported" with no way
  to say why, which is a different answer from the one the method's name promises, so the reason
  is kept and read back through `-charon_unsupportedReason` beside the four other accessors.

## What is generated, and what that means for a reader

`IN10_0.m` and `IN10_3.m` are generated, and the generator refuses to emit a body it cannot
justify: an initialiser parameter that names no property of the class or of a superclass and has
no line in `PARAMETER_PROPERTIES` stops the run rather than being dropped, and a member whose
type is a class of a later group is left `@dynamic` and takes an entry of its own that says so.
The registry is written from the generator's report of what it emitted, read back out of the
emitted text, so an entry cannot claim a member the library does not carry
(`tools/intents/gen-registry.py`).

Four places where the SDK's own names differ and the generator is told where a value goes,
each read off the header of iPhoneOS 16.4:

* `INBillPayee`'s and `INPaymentAccount`'s initialisers take `number:` and the class exposes it
  as `accountNumber` — the class's one `NSString` property.
* `INPriceRange`: the header's own comment on `minimumPrice` is "the lowest of the two prices
  used to construct this range", so `initWithRangeBetweenPrice:andPrice:` feeds the first price
  to the minimum and the second to the maximum, and `initWithPrice:` gives both ends the one
  price.
* `INPerson`'s `contactSuggestion` is declared `getter=isContactSuggestion`, so the initialiser
  that spells its parameter `isContactSuggestion:` is matched through the getter's own name.
The copy in `Intents/CharonIntentsCoding.m` reads the property an ivar belongs to through the `V_` field
of its own attributes — the way the runtime pairs them, so a property whose ivar is not spelled
after it is still found — and then reads the ownership out of the **field list** that follows the
type field, one character at a time, skipping the `G…`/`S…`/`V…` payloads. A property is copied
exactly when `C` is among those flags, and `&` (retain), `W` (weak) and their absence (assign) mean
it is not. Measured with the port's own compiler for `armv7-apple-ios6.1.3`:

| header | attributes | copied |
|---|---|---|
| `strong`, `retain` | `T@"X",&,N,V_p` | no — the ownership is `&` |
| `copy` | `T@"X",C,N,V_p` | yes |
| `assign` | `T@"X",N,V_p` | no |
| `weak` | `T@"X",W,N,V_p` | no |
| `readonly, strong` | `T@"X",R,&,N,V_p` | no — `R` is *readonly* |
| `getter=isFoo` | `T@"X",&,N,GisFoo,V_p` | no — `G` starts a payload |

Searching the string instead would read the `C` of **`INCar`**, the `S` of `NSString` and the `R`
of a readonly, which is how three `strong` properties of the 10.0.1 group were being copied.

### A success that says nothing is a notRequired

The host's own framework logs, for a success whose value is the "nothing to say" case of its
enumeration, `Success resolution with INCarSignalOptionsUnknown will be reformed to notRequired.`
(observed on the host's own Intents, 2026-09-27, and for nine enumerations: `INCarSignalOptions`,
`INTaskStatus`, `INRadioType`, `INRelativeReference`, `INRelativeSetting`, `INTaskPriority`,
`INVisualCodeType`, `INWorkoutGoalUnitType`, `INWorkoutLocationType`). A success that says nothing
is a success with nothing to say, which is what `notRequired` means, so the generated
`+successWithResolved…:` of a result of one of those enumerations builds a **notRequired** for its
zero case and a success for any other. The list is `NEUTRAL_ENUMERATIONS` in the generator, and it
is the host's own list of what it reform, not a guess about which enums have a zero case.

* A subclass initialiser that keeps a value its superclass declares **read-only**
  (`INRestaurantGuest`'s `nameComponents`, which is `INPerson`'s) calls the superclass's own
  designated initialiser, with the value it has and `nil` or `0` for the arguments the header
  marks `nullable`. For the six nullable arguments that is the only value a subclass initialiser
  can have, and the result holds nil for them.
* **The one exception is measured, not assumed.** `INPerson`'s designated initialiser takes
  `personHandle` *nonnull* (`INPerson.h:27`, inside `NS_ASSUME_NONNULL_BEGIN`, and the only
  parameter of the five that is not marked `nullable`), and nothing in the SDK's own headers says
  where a subclass would get one. The generator therefore **refuses to chain** and those four
  initialisers — `INRestaurantGuest`'s and its three siblings' — are left unimplemented, with
  their own registry entries saying so. It does not claim Apple's class does the same, and it
  does not pass nil to a parameter the SDK forbids: a call the header rules out is not a way to
  make an initialiser fit.
* The same refusal covers a class whose superclass declares a value read-only and offers **no
  designated initialiser at all** to put it in (`INBoatReservation`'s `itemReference`, which is
  `INReservation`'s): there is no chain to make, and a body would have to store the value in this
  class's own copy of a property it does not own.

### The groups above iOS 10.3 and what places them

The `armv7` ladder this package is gated against ends at iOS 10.3.4 — the newest release any
`armv7` device can run — so for the 11.0 group and everything above it **no held release cache
exports a single one of these symbols**. There is no measurement to be had, and the object file
of a group is placed by the header's own availability annotation, which is the one source
`modules/apple/backports.lua`'s `releases_in()` falls back to. The band machine handles that
correctly: a point at 11.0 or later matches no `armv7` release in the firmware catalogue, so no
band is cut for it and the API is carried by the last band that exists (iOS 10.3.4), which is the
newest release an `armv7` device runs and does need it. `release-split` confirms the split is
clean, one release per object file, on the ladder it has.

On **arm64** the same groups are reachable, and the `arm64` band plan *would* name caches to
fetch for the points between them. That is not measured here: this package is gated for `armv7`,
and the caches an `arm64` band would need are not held. It is the first thing to settle before
those groups can be called done for `arm64`.

The header and the release caches disagree more than once, and the caches decide the object file
every time:

* `INPaymentStatusResolutionResult` — the header says iOS 10.0, the armv7 caches of 10.0.1 do not
  export it, and it appears in 10.3. The header's own annotation stays in its registry entry,
  because that is what an application compiling against the SDK is told.
* `INCallRecordTypeResolutionResult` — the header says 11.0 and the 10.0.1 cache has it, so it
  rides in `IN10_0_1.m` with the 10.0.1 group and not in `IN11_0.m`.
* `INCallRecordResolutionResult` — the header says 16.2 and the 16.0 cache has it.

A member whose type the SDK's headers only `@class` forward declare is treated like one of a later
group: `INDateComponentsRange`'s `initWithEKRecurrenceRule:` takes **EventKit's** class, which
this package does not link and which the Intents header of iPhoneOS 16.4 names where 26.2 names
an `INRecurrenceRule`. That initialiser is not given a body and its entry says why; the property
of the same name, whose type *is* carried, is implemented.

## The four, and what is not carried

Four classes of this delivery are not implemented whole, and each says so in its own entry
rather than answering with a class that looks filled and is not: `INDateComponentsRange`'s
`recurrenceRule` (an `INRecurrenceRule`, which arrived with iOS 11), `INPaymentAccount`'s
`balance` and `secondaryBalance` (an `INBalanceAmount`, iOS 11), `INMessage`'s
`audioMessageFile` (an `INFile`, iOS 13) and `INIntent`'s `donationMetadata` (an
`INIntentDonationMetadata`, iOS 15). Each of those members is `@dynamic` — the header's
availability mark stays on it, so a port cannot call it, and `respondsToSelector:` answers no
instead of a process dying on an unrecognised selector. An initialiser that takes one of those
values is left unimplemented for the same reason and says so in its own entry.

## All 309 classes, and the nine declarations the port's SDK does not have

Every one of the SDK 26.2 surface's 309 Intents classes is carried: the measurement places them
at 10.0.1 (116), 10.3 (22), 11.0 (55), 12.0 (17), 16.0 (95) and 18.0 (4), one object file per
group, and `registry/Intents/` has a file for each.

Seven of those classes and the four declarations they are typed by are **newer than the SDK the
port compiles against**: the toolchain's `charon@iphoneos-sdk` is iPhoneOS 16.4, and
`INMessageLinkMetadata` (iOS 17), `INUnsendMessagesIntent`/`INUnsendMessagesIntentResponse` and
`INEditMessageIntent`/`INEditMessageIntentResponse` (iOS 17), `INMessageReaction` and `INSticker`
(iOS 18) appear first in the SDK of 17.0 and 18.0. Their contracts are read from the headers of
**iPhoneOS 26.2** (the SDK that `tools/intents/generate.sh` asks for as `SDK_262`, which the coordinator
keeps unpacked and a worktree sweep will delete) and the
declaration the implementation compiles against is `CharonIntents262.h` — the seven classes, the
two enumerations two of them are typed by, and the two response codes the two responses are typed
by. That is what a backport writes for API its SDK does not have, and the same generator builds
their bodies from the same declarations it builds every other class's from.

**Thirteen, not eleven:** the header declares seven classes, **four** enumerations and **two**
protocols, and the two protocols (`INUnsendMessagesIntentHandling`,
`INEditMessageIntentHandling`) were left out of the earlier count of what this file carries.

The generator takes a second AST for exactly this: `--dump-newer` is read for a class the port's
SDK does not declare at all, and **only** for those — a class both SDKs declare is taken from the
port's own, because that is the declaration the implementation compiles against and the newer one
names members (`INRelevantShortcut`, `INVoiceShortcut`) the port's headers do not.

### One class of the 16.0 group is an object file of its own

`INPaymentMethodResolutionResult` is in `INPaymentMethodResolutionResult10.3.m`, not in
`IN16_0.m`, and the reason is measured. The **armv7s cache of iOS 10.3.4 already exports it**,
while the caches of the 16.0 group's own release do not have the 94 classes it would have shared
an object with (`tools/intents/measure-group.lua`, which walks the release below the group's own
and names the classes it exports: 1 of 95, this one). One object that defines both is what
`modules/apple/backports.lua`'s `band()` refuses — "an object carries API that arrived in one
release, so split it" — and it refused it in the **armv7 band at 10.3.4** while the 6.1.3 gate,
which links the deployment band alone, did not. A one-class object is consistent in every band:
the release that has it re-exports the object, and every release that does not keeps it.

**The lesson, for every framework in this push:** the gate is a deployment-band check and the
package build is the per-band one. `xmake emulate install` stages every band and is what finds
this; `build-gate.lua` alone would not.

`INObjectCollection -initWithItems:` is the one member of the 16.0 group whose body is a
derivation rather than a store, and it is hand written in the generator with the header's own
words: `allItems` is the items, `sections` is them under one untitled section, and collation is
not indexed, because the items arrive in the order they were given.

The 16.0 and 18.0 groups are also the ones that are only reachable on **arm64**: no armv7 device
runs past 10.3.4, so for the armv7 band they are carried by the last band and cost nothing, and
for arm64 they need the band caches the arm64 plan names. Neither is measured here.

IntentsUI (58 rows, 43 of them entries, 15 absent with a reason each) is a library of its own,
`libIntentsUIBackports.dylib` over UIKit, and is in `facts/IntentsUI/IntentsUI.md`. AppIntents
(2323 rows) is a `swift-runtime` deliverable and is not here.

## What is not measured here

This framework's behaviour was written against the header of iPhoneOS 16.4 and measured against
macOS, where `Intents` exists as a framework, for the values the data classes carry and the
names they derive. It has **not** been run on the device or in the emulator: the
`donateInteractionWithCompletion:` path, the two stores, the resolution results and
`INPreferences`' three answers all need a run on the port itself before this file can say they
work rather than that they are the behaviour the header describes. Until that run, every entry
of this framework is **device-unverified**.
