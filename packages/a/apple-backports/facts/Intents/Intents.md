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
* **`INIntentSetImageKeyPath`** and **`_INIntentSetImageKeyPath`** are **not carried at all**,
  and their registry entries say so. They are not Objective-C declarations: the two methods they
  name, `-[INIntent setImage:forParameterNamed:]` and `-[INIntent imageForParameterNamed:]`, are
  in `INIntent.h` marked `NS_REFINED_FOR_SWIFT`, and that attribute is what sends their Swift
  names into these two protocols instead of leaving them on the selectors - which is why a
  search of the SDK's headers finds the methods and not the protocols. What the SDK writes of
  the protocols is in its Swift overlay, `Intents.swiftmodule/arm64-apple-ios.swiftinterface`
  (the private one, the public one refining it, and `INIntent` conforming to both), and as Swift
  symbols in `usr/lib/swift/libswiftIntents.tbd`; 16.4 and 26.2 write the same. Both SDKs are
  read the same way here, so there is nothing one of them has and the other does not.
  The entries are `absent` rather than `implemented` because there is no header to lower: the
  two methods are carried, with their own iOS 12.0 marks lowered, and they are what a client on
  this release calls. An entry that said this protocol was carried by lowering its header was
  claiming a mechanism no Swift declaration can be carried by, and a lift refuses by name a
  registered protocol it can find in no header - which is what it did.
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

### One bare `-init` that the header declares *available*, and the loop that never visited it

`INListCarsIntent`'s own entry in `INListCarsIntent.h:17` is

    - (instancetype)init NS_DESIGNATED_INITIALIZER;

Available, and the class's only initialiser: it is an `INIntent` with no property of its own, so
the whole of it is the superclass's `-init`. `INIntent` declares none of its own, so that is
`NSObject`'s, and nothing in the chain marks one unavailable - the selector can be spelled, so the
body is `return [super init];` and no IMP is reached through.

Its row said `absent` with the reason *"the header marks the initialiser unavailable, so a port
cannot call it"*, which is false of this header. The cause is a gap in the generator, not a
judgement: the loop that writes an initialiser body visits only selectors spelled `initWith…:`,
so a bare `-init` reached the file only through the separate block that exists for the classes
whose header marks one unavailable, and this class is not one of those. Its body is written by
hand in `EXTRA_METHODS` for that reason, and the registry row's `source` says so rather than
carrying the sentence about the 110 `-init` rows a header really does mark.

What the release was asked, and how:

    sh tools/intents/probe-host-absent.sh packages/a/apple-backports/registry/Intents/ios16.json

    ios16.json  -[INListCarsIntent init]  found=yes answers=yes declared-by=INListCarsIntent init=object
    # absent rows: 1, control rows: 464 implemented rows of the same files
    # rows=465 parsed=465 unparsed=0 found=465 answered=214 inherited-from-NSObject=25

`declared-by=INListCarsIntent` is the column that separates this row from the 110: there, the
selector is declared by `NSObject` and the port has to forward through an IMP because the header
forbids naming it; here the class declares it itself and the header permits the name. `init=object`
is `[[INListCarsIntent alloc] init]` on the host's own class, through the IMP, since a compile-time
call to a member the port's SDK marks unavailable does not build. All 465 names were found in the
same process, so the row's `yes` is the release's and not the reader's.

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
The copy in the charon-coding package reads the property an ivar belongs to through the `V_` field
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

### The six members iOS 17.0 added to INMessage

`INMessage` is a class of the 10.0.1 group, so `IN10_0_1.m` defines it. The six members iOS
17.0 added to it were sitting `absent` with the reason "the SDK's own headers do not declare this
member, so there is nothing to answer" - a claim about the SDK **of 16.4**, which this package
compiles against, and not about any release. All six are declared by the header of iPhoneOS 26.2,
each `API_AVAILABLE(ios(17.0), watchos(10.0))`:

```
$ grep -n "attachmentFiles\|linkMetadata\|numberOfAttachments" \
    ~/.xmake/packages/i/iphoneos-sdk/26.2/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk/System/Library/Frameworks/Intents.framework/Headers/INMessage.h
72:                   attachmentFiles:(nullable NSArray<INFile *> *)attachmentFiles API_AVAILABLE(ios(17.0), watchos(10.0)) API_UNAVAILABLE(macos);
126:                      linkMetadata:(nullable INMessageLinkMetadata *)linkMetadata API_AVAILABLE(ios(17.0), watchos(10.0)) API_UNAVAILABLE(macos);
137:               numberOfAttachments:(nullable NSNumber *)numberOfAttachments API_AVAILABLE(ios(17.0), watchos(10.0)) API_UNAVAILABLE(macos);
198:@property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY)  NSArray<INFile *> *attachmentFiles API_AVAILABLE(ios(17.0), watchos(10.0)) API_UNAVAILABLE(macosx);
200:@property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) NSNumber *numberOfAttachments API_AVAILABLE(ios(17.0), watchos(10.0)) API_UNAVAILABLE(macosx);
204:@property (readonly, copy, nullable, NS_NONATOMIC_IOSONLY) INMessageLinkMetadata *linkMetadata API_AVAILABLE(ios(17.0), watchos(10.0)) API_UNAVAILABLE(macosx);
```

and the registry's own source says the same, `coordination/corpus/sdk-26.2-surface.tsv`, one row
per name at 17.0. So the reason was false about the release and true about the port, and the six
are now written by hand in `Intents/IN17_0.m`.

The cause is one word in `tools/intents/generate.sh`: the 10.0.1 and 10.3 groups run with
`newer: no`, so `gen-intents.py` reads only the port's own SDK for their classes, and a member
only iPhoneOS 26.2 declares is invisible to them. The 12.0, 16.0 and 18.0 groups already run with
`newer: yes`. Flipping it for the 10.0.1 group would generate these six where they belong - in
`IN10_0_1.m`, beside the class, in the file's own `@implementation`, with the ivars the charon-coding
walker reads - but it rewrites `registry/Intents/ios10.json` and `IN10_0_1.m` whole, and both belong
to other slices of the same file. Until it is flipped the six are answered by the category, and
`coordination/crutches.md` carries the entry.

**What a release this port deploys on carries.** Neither band end carries the class at all, and
the run carries its own control - the 10.0.1 rung is in it and does carry `INMessage`, so a zero on
6.1.3 and 4.3 is the release's and not the reader's:

```
$ CHARON_ROOT=$PWD xmake l tools/corpus/cache-census.lua INMessage 6.1.3 4.3 10.0.1
# (cache paths below abbreviated to ~; the tool prints them absolute)
6.1.3     ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming INMessage 0
         classes 11378, of which INMessage* 0
         protocols 1171, of which INMessage* 0
4.3       ~/.charon/dyld/4.3/dyld_shared_cache_armv7
         images 354, of which naming INMessage 0
         classes 7187, of which INMessage* 0
         protocols 564, of which INMessage* 0
10.0.1    ~/.charon/dyld/10.0.1/dyld_shared_cache_armv7s
         images 1082, of which naming INMessage 0
         classes 39319, of which INMessage* 3 (INMessage INMessageAttributeOptionsResolutionResult INMessageAttributeResolutionResult)
         protocols 6111, of which INMessage* 1 (INMessageExport)
control: 4 name(s) beginning INMessage found in this run, so a zero on another rung is the release's and not the reader's
```

**Which held release first carries each name.** `tools/cache-index/first-rung.py`, over the whole
ladder, with a nonsense name in the same run as the negative control. Read it as PRESENCE and
nothing else: `numberOfAttachments` reads 3.0 and `linkMetadata` reads 10.0.1, and neither is
`INMessage`'s - they are other classes' selectors of the same name, which is the same trap
`fileSystemRepresentation` sets, and it is why a selector's rung is never evidence about its owner.

```
$ printf '%s\n' 'initWithIdentifier:conversationIdentifier:content:dateSent:sender:recipients:groupName:messageType:serviceName:attachmentFiles:' \
    'initWithIdentifier:conversationIdentifier:content:dateSent:sender:recipients:groupName:serviceName:linkMetadata:' \
    'initWithIdentifier:conversationIdentifier:content:dateSent:sender:recipients:groupName:serviceName:messageType:numberOfAttachments:' \
    attachmentFiles numberOfAttachments linkMetadata charonNoSuchSelector17Control \
  | python3 tools/cache-index/first-rung.py
initWithIdentifier:conversationIdentifier:content:dateSent:sender:recipients:groupName:messageType:serviceName:attachmentFiles:	18.0
initWithIdentifier:conversationIdentifier:content:dateSent:sender:recipients:groupName:serviceName:linkMetadata:	18.0
initWithIdentifier:conversationIdentifier:content:dateSent:sender:recipients:groupName:serviceName:messageType:numberOfAttachments:	18.0
attachmentFiles	18.0
numberOfAttachments	3.0
linkMetadata	10.0.1
charonNoSuchSelector17Control	NONE
```

The armv7 ladder ends at 10.3.4 and the three initialisers and `attachmentFiles` first appear at
18.0, so no release this package is gated against has any of the six, and none could: they are
newer than every release an armv7 device runs. That is why the six are not answered by anything a
release has, and it is not a reason to leave them out - `INFile` (13.0) and `INMessageLinkMetadata`
(17.0) are both carried by this package, so the three values are objects the port already has and
what a caller gets back is the copy of what it passed.

**Where the three values are kept, and the three of the class's own methods this file answers.**
A class extension may declare ivars in a translation unit that does not hold the `@implementation` -
clang accepts it and the file compiles - and it does not link:

```
$ xcrun clang -fobjc-arc -framework Foundation -o t a.m b.m main.m
Undefined symbols for architecture arm64:
  "_OBJC_IVAR_$_Foo._lateIvar", referenced from:
      -[Foo(Late) lateIvar] in b.o
```

So the three live in an associated object each, and `-copyWithZone:`, `-encodeWithCoder:` and
`-initWithCoder:` - the class's own three, which walk its ivar list through the one helper in
`packages/c/charon-coding` - are answered in `IN17_0.m` beside them, under the keys that helper
itself uses (`INMessage.attachmentFiles` and so on, which are the keys the class of iOS 17.0
occupies for the same three). Without that a copy and an archive of an `INMessage` would carry
ten of its thirteen values and drop exactly the three of 17.0. Those three methods are not API of
this release: the SDK's header declares none of them (the class takes them from `NSObject`'s
protocols), no registry row names any of them, and so nothing this file carries is placed by them.

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

## Where the tables and the walker come from, and that nothing came from liblouis

**The braille tables are written from the standard, not copied from an implementation.**
liblouis is the implementation everyone uses and it is **LGPL**: read it, do not copy it, and
**this package never had a copy of it** — there is no liblouis in the tree, in the store or in
anything this work read. What is in `CharonBraille.m` is written out here:

* the twenty-six letter cells, as the dot numbers the grade-1 alphabet gives each letter, and
  every cell the **Unicode braille pattern** those dots are (`U+2800 +` the dot bitmask, dot 1 the
  lowest bit), which is the published block's own definition;
* the capital sign as **dot 6** (`U+2820`), the number sign as **dots 3, 4, 5 and 6** (`U+283C`),
  the grade-1 indicator as **dots 5 and 6** (`U+2830`), and the digits `1-9` as `a-i` with `0` as
  `j`;
* the punctuation cells the standard covers with one cell, and the two places two characters share
  a cell, which the table says rather than the code inventing a second one;
* the run rules: one sign for a capital on its own, **twice** before a run of consecutive capitals,
  the number sign once for a run of digits, and the grade-1 indicator before a letter `a-j` that
  follows a digit.

The **coding walker** is this package's own: it walks a class's ivar list through the Objective-C
runtime, from the object's class up to `NSObject`, and encodes a value type by its bytes and an
object by its value. The one part that follows something outside is the **ownership read**, and
that is the runtime's own documented attribute format: a property's `property_getAttributes` string
ends in its backing ivar (`T@"NSString",C,N,V_name`), and the ownership is a flag in the field list
after the type field. The field-list walk and the table of what each declaration compiles to are in
this file, and the negative control for it is `tests/backports/callgen/ownership-test.sh`.

## What is not measured here

This framework's behaviour was written against the header of iPhoneOS 16.4 and measured against
macOS, where `Intents` exists as a framework, for the values the data classes carry and the
names they derive. It has **not** been run on the device or in the emulator: the
`donateInteractionWithCompletion:` path, the two stores, the resolution results and
`INPreferences`' three answers all need a run on the port itself before this file can say they
work rather than that they are the behaviour the header describes. Until that run, every entry
of this framework is **device-unverified**.

## The 110 `-[X init]`, what the header says and what the port answers

110 rows, one bare `-init` per class, and the reason they are `implemented` is not the header: the
header **denies** the method on every one of them, and a row that cited it would be citing the wrong
authority. These are the classes whose own SDK marks

    - (instancetype)init NS_UNAVAILABLE;

which is a compile-time marker. It says a caller must not *name* the selector. It does not say the
system has no answer, and the system has one — which is the thing that had to be measured before the
rows could move, and it is in the `source` of every one of them.

**What the host was measured to answer.** Eight classes, by hand, through the IMP and not by a call —
a compile-time call is unavailable and cannot be, which is the same constraint the emitted body is
built around:

    class_getMethodImplementation(Cls, @selector(init))  is non-NULL   on all eight
    [[Cls alloc] init] through that IMP                    an object    on all eight
                                                             no exception
    respondsToSelector:init                                 1           on all eight
    every declared property                                present and nil

    INMessage  INPerson  INBillDetails  INBalanceAmount
    INCurrencyAmount  INCallRecord  INCar  INFile

**What the port now answers.** The same, by construction: the class defines `-init` even though the
header marks it unavailable — which compiles, because defining an unavailable method is allowed — and
forwards to the superclass's own `-init` through `class_getMethodImplementation(parent, selector)`,
never by name. The generator's rule is in `tools/intents/gen-intents.py`, in `own_init_blocked_here`:
`own_init_unavailable` walks the whole chain, which is the right question for an initialiser *with*
arguments, because such an initialiser stores them here and then has to reach a superclass `-init`; a
bare `-init` stores nothing, so the question is narrower — the selector it forwards to is the nearest
implementation in the chain, and only the one it would actually reach matters.

**Why `absent` was wrong and `implemented` is right.** Before this, all 110 were `absent` with the
reason *"the header marks the class's -init unavailable, so a port cannot call it"*. That reason was
true of a compile-time call and false of the class: leaving the method undefined sends a caller that
asks for it to a NULL IMP, which is worse than answering with an object whose properties are nil. The
marker forbids *naming* the selector at compile time, and that is the only thing it forbids.

## The three `+[X new]` of the 12.0 group, the same marker one call up

`INShortcut`, `INVoiceShortcut` and `INVoiceShortcutCenter` each mark **both** initialisers
unavailable, so the same argument that moved the 110 `-init` rows moves these three `+new` rows, and
they were `absent` for the same wrong reason before. What was measured, and how:

    sh tools/intents/probe-host-absent.sh packages/a/apple-backports/registry/Intents/ios12.json

    ios12.json  +[INShortcut new]            found=yes answers=yes declared-by=NSObject
    ios12.json  +[INVoiceShortcut new]       found=yes answers=yes declared-by=NSObject
    ios12.json  +[INVoiceShortcutCenter new] found=yes answers=yes declared-by=NSObject
    # absent rows: 3, control rows: 97 implemented rows of the same files
    # rows=100 parsed=100 unparsed=0 found=100 answered=55 inherited-from-NSObject=9

`answers=yes` is the release's own answer and `declared-by=NSObject` is whose body it is: the
metaclass chain declares `new` at `NSObject` and nowhere else. The 97 control rows of the same file
were probed in the same process and 100 of 100 names were found, so a zero elsewhere would have been
the release's and not this reader's.

That `answers=yes` and a returned object are two claims, so the second was measured separately, by a
probe that asks the selector's declaring class and then calls it. It is not in the tree and this is
its whole output (arm64-apple-macos14.0 against `/System/Library/Frameworks/Intents.framework`):

    INShortcut             declares=NSObject  returns=object  respondsToSelector:new=1
    INVoiceShortcut        declares=NSObject  returns=object  respondsToSelector:new=1
    INVoiceShortcutCenter  declares=NSObject  returns=object  respondsToSelector:new=1
    INObject               declares=NSObject  returns=object  respondsToSelector:new=1   <- control

So the port answers each `+new` with NSObject's own `+new`, reached through its IMP for the same
reason the `-init` above is: the header forbids naming the selector. `INObject` is in that table as
the control, and it is the one class of the four whose header marks nothing.

## What is NOT proven here, and is owed

- **The per-class harness is owed and is not in the tree.** The eight classes above are the
  measurement. The other hundred and two are the same rule applied to the same header, and that is a
  *claim* until a harness runs them. `tests/backports/host/intents/` holds the constants suite
  (`constants.m` and its `run.sh`) and nothing for these: the harness has to compare the port's
  `-init` with the system's class by class, and the port's classes and the framework's share a name,
  so a lookup in one process returns the framework's object and the check compares the framework with
  itself. The tree already has the tool for the fix — `tests/backports/host/prefix_selectors.py`, which
  `mpsmatrix/run.sh` uses to rename the port's classes so its implementations are reached under names
  of their own — and the port's Intents sources additionally need `CharonIntents262.h` renamed with
  them, because that header re-declares the classes the port's own SDK lacks and the host's has, and
  without the rename the host build fails with *duplicate interface definition*. The rename list is
  generated from the port's own object symbols, so every name in it is a class the port really defines.
- **Nothing here runs on a device or under `xmake emulate`.** Every answer above is the macOS host's
  own Intents, and the port's objects are armv7 iOS 6.1.3. That the `-init` survives into a linked
  6.1.3 binary is the link step's job.
- **`gates: coordinator`.** Not run by the author.

## A subclass that keeps its superclass's read-only value in its own ivar

The seventeen `intents-1a` rows — eight reservation classes' `-initWithItemReference:…` in both
spellings, `INRestaurantGuest`'s `-initWithNameComponents:…` and `INRideDriver`'s two — and the
reason they were `absent` at all: `INReservation` and `INPerson` declare their values read-only and
offer no designated initialiser, so there was nowhere to put them. The class now keeps a copy in its
own ivar and answers the getter itself. **The objects are armv7 iOS 6.1.3 and nothing in that slice
runs them**, so what is proven is the compile, the presence of the seventeen per `nm`, and the
registry's own text; the runtime behaviour — the getter's answer, a superclass-typed pointer, an
`NSSecureCoding` round trip — is owed to `intents-1c` and its renamed host harness. What is owed and
what is proven are set out in full in `facts/Intents/InheritedReadonly.md`.
