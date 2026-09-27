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

Ten classes are hand written in `CharonIntents100.m`; the other 104 of the 10.0.1 group and all
22 of the 10.3 group are generated into `IN10_0.m` and `IN10_3.m` by
`tools/intents/gen-intents.py` from the SDK's own declarations. What is hand written and why:

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
  `systemImageNamed:` answers no image, because the system images are SF Symbols and this
  release has no set of them — the same answer `imageNamed:` gives for a name the app has none
  of. `imageWithURL:` reads the URL and answers no image for a URL it cannot read, which is the
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
* A subclass initialiser that keeps a value its superclass declares **read-only**
  (`INRestaurantGuest`'s `nameComponents`, which is `INPerson`'s) calls the superclass's own
  designated initialiser, with the value it has and `nil` or `0` for the arguments it does not:
  a subclass initialiser that does not offer them has no values for them. That is also what
  Apple's class does, and it is why those arguments are nil on the result.

`INPaymentStatusResolutionResult` is the one place the header and the release caches disagree:
the header's availability says iOS 10.0, and the armv7 caches of iOS 10.0.1 do not export it —
it appears in 10.3. The caches decide which object file carries it (`IN10_3.m`), and the
header's own annotation stays in its registry entry, because that is what an application
compiling against the SDK is told.

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

## What is not measured here

This framework's behaviour was written against the header of iPhoneOS 16.4 and measured against
macOS, where `Intents` exists as a framework, for the values the data classes carry and the
names they derive. It has **not** been run on the device or in the emulator: the
`donateInteractionWithCompletion:` path, the two stores, the resolution results and
`INPreferences`' three answers all need a run on the port itself before this file can say they
work rather than that they are the behaviour the header describes. Until that run, every entry
of this framework is **device-unverified**.
