# The names this series declares that the framework's own interfaces do not

**Reproduce the counts** -- the script is in the tree, and these are the three commands:

    python3 packages/a/appintents/tests/invented-names.py --control   # the refusal, for a missing input
    python3 packages/a/appintents/tests/invented-names.py             # the counts
    python3 packages/a/appintents/tests/invented-names.py --table     # this table

**Where the interfaces come from, and why it is a real path.** The first version read three of the
four from `.agent-work/kits/*-ios.swiftinterface` -- files that exist only in the band worktree that
extracted them. The review measured the consequence on a **fresh detached checkout**, where those
paths do not exist: the script silently scored TipKit, WidgetKit and ActivityKit as absent from every
interface, and the counts came out **425 in the interfaces / 223 to explain** against the 573/75 it
printed in my worktree. Each path is now a glob under **`charon@iphoneos-sdk`'s own install of 26.2**
-- the machine's copy of the release the rows are written against, and the same files the worktree
copies came from (TipKit 1279, WidgetKit 1785, ActivityKit 676 lines) -- and a glob matching **no**
file exits non-zero naming the pattern, with `--control` as the test of that property. This store holds
three installs of 26.2, so a glob matching several is read in full and the count printed: which copies
were read is never a silent choice either.

**The counts, from a fresh detached checkout at the previous commit** (the run the review asked for,
in `charon/.agent-work/worktrees/verify-r5`, a checkout with none of my `.agent-work/` in it):

| | |
| --- | --- |
| type-level names declared | 648 across AppIntents, TipKit, WidgetKit, ActivityKit |
| in the module's own interface | **584** |
| `Charon`-prefixed (the port's own, by convention) | **44** |
| **to explain, in the table below** | **64** |
| -- of those, **quoted from the SDK** with the hit | 6 |
| -- of those, **invented by this band**, with the reason in the row | **25** |
| the macro plugin's own tree (`packages/a/appintents-macros`) | 8, all ours by construction |

**The first version of this file was wrong and said so in its own text.** It claimed a dotted or
qualified name is "the framework printing it under a qualified spelling"; the review sampled that and
it is false -- `AnyAppEntity` is in no file of the whole 26.2 SDK, and so are `AnyRange`,
`DateResolver`, `IndexRecord`, `FloatResolver`, `ElementResolver` and `IdentityResolver` (the
controls: `RecurrenceRule` scores 6, `AppIntent` 93). Every row now carries **the SDK hit, quoted**,
or says **invented, with the reason**, and the invented count is printed by every run, so a new
invented name cannot pass as a category.

**The three kinds a row can be.** *A quoted SDK hit* -- the framework's own name, and the quote says
where. *An SDK type in a framework this band does not read* -- `CLPlacemark` (CoreLocation), the
`CSSearchable*` trio (CoreSpotlight, lifted by `modules/apple/spotlight_lift.lua`, see `Spotlight.md`),
the SwiftUI names, `BundleDescription`; the port names these to use them and declares none.
*Invented by this band* -- its own machinery behind a framework type this release does not carry, or
its own state where the framework keeps state in a store that does not exist here; each such row
carries the reason.

| name | hits in the four interfaces | what it is | invented, with reason |
| --- | --- | --- | --- |
| `AnyAppEntity` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- the framework's own erasure is a nested type of `AppEntity` that it prints under its own container; this one answers to the same name and is the port's own spelling of it |
| `AnyRange` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- the port's own erased range, for the same reason as `AnyAppEntity` |
| `AppShortcutOptionsCollectionSpecificationFor` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `AppShortcutParameterPresentationProtocol` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `AppShortcutParameterPresentationSnapshot` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `AppShortcutParameterPresentationTitleBuilder` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `BundleDescription` | `MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public var bundle: Foundation::LocalizedStringResource.Foundation::BundleDescription {` | the framework's own, in the SDK | no |
| `Comment` | `MacOSX27.0.sdk/usr/include/curses.h: * Comment annotation on the declaration line dropped to avoid script picking` | the framework's own, in the SDK | no |
| `Continuation` | `MacOSX27.0.sdk/usr/lib/swift/_Concurrency.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public struct Continuation : Swift::Sendable {` | the framework's own, in the SDK | no |
| `ContinuationError` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `Continuation` |
| `ControlStyle` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `CustomLocalizedStringResourceConvertible` | `MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: @available(*, deprecated, message: "Localized string interpolation produces an unlocalized, debug description for this type of value. Use a type suppo` | the framework's own, in the SDK | no |
| `DateComponentsResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `DateResolver` |
| `DateResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a resolver the runtime does not carry, so the port writes one; `Macros.md` and the Foundation gate line say why |
| `ElementResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `DateResolver` |
| `EntityQueryComparatorProtocol` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `EntityQueryPropertyValue` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `FloatResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `DateResolver` |
| `IdentityResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `DateResolver` |
| `IndexRecord` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- the port's own record of a donation's index entry; the framework keeps that state in its own store |
| `IntentChoiceRequest` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentConfirmationRequest` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentDonation` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentDonationStore` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentItemBuilder` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentItemSectionBuilder` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentModesFlags` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentParameterValueRange` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `Kind` | `MacOSX27.0.sdk/usr/include/mach/i386/fp_reg.h: * Kind of floating-point support provided by kernel.` | the framework's own, in the SDK | no |
| `LocalizedStringResource` | `MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks/UIKit.framework/Versions/A/Modules/UIKit.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public let title: Foundation.LocalizedStringResource` | the framework's own, in the SDK | no |
| `NeverSummary` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
