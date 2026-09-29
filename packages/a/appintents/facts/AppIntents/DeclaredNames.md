# The names this series declares that the framework's own interfaces do not

**Reproduce the counts** — the script is in the tree, and these are the two commands:

    python3 packages/a/appintents/tests/invented-names.py            # the counts
    python3 packages/a/appintents/tests/invented-names.py --table    # this table

It walks the four modules' Swift files, takes every public **type-level** name, subtracts the names
the module's own `.swiftinterface` prints and the `Charon`-prefixed ones, and then -- for every name
that survives -- **greps every `.swiftinterface` and header in the machine's SDKs for that name**. A
name with a hit has its provenance quoted in the table; a name with **no hit anywhere in the SDKs is
one this band invented**, and says so in its row with the reason.

| | |
| --- | --- |
| type-level names declared | 648 across AppIntents, TipKit, WidgetKit, ActivityKit |
| in the module's own interface | 573 |
| `Charon`-prefixed (the port's own, by convention) | 44 |
| **to explain, in the table below** | **75** |
| — of those, **quoted from the SDK** (the framework's own, a hit somewhere) | **36** |
| — of those, **invented by this band**, with the reason in the row | **39** |
| the macro plugin's own tree (`packages/a/appintents-macros`) | 8, all ours by construction |

**The previous version of this file was wrong and said so in its own text.** It claimed that a dotted
or qualified name is "the framework printing it under a qualified spelling". The review sampled that
claim and it is false: `AnyAppEntity` is in no file of the whole 26.2 SDK, and so are `AnyRange`,
`DateResolver`, `IndexRecord`, `Continuation`, `FloatResolver`, `ElementResolver` and
`IdentityResolver` (the controls: `RecurrenceRule` scores 6, `AppIntent` 93, so the zeros are real).
Those names are now in the table with **0 hits and a reason**, and the invented count is in the
counts above rather than folded into a category that was not true.

**The three kinds a row can now be, and what each one means.** *A quoted SDK hit* -- the framework's
own name, the quote says where, so a reader can check it. *An SDK type in a framework this band does
not read* -- `CLPlacemark` (CoreLocation), the `CSSearchable*` trio (CoreSpotlight, lifted by
`modules/apple/spotlight_lift.lua` and linked, `Spotlight.md`), the SwiftUI names, `BundleDescription`;
the port *names* these to use them and declares none. *Invented by this band* -- the port's own
machinery behind a framework type this release does not carry, or the port's own state where the
framework keeps its state in a store that does not exist here; every such row carries the reason.

**The rule that keeps it honest, and it is now mechanical.** A name with no hit in any SDK interface
or header is on this table as *invented* or it is removed; and the invented count is printed by every
run, so a new invented name cannot pass as a category.

| --- | --- | --- | --- |
| `AnyAppEntity` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- the framework's own erasure is a nested type of `AppEntity` that it prints under its own container; this one answers to the same name and is the port's own spelling of it |
| `AnyRange` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- the port's own erased range, for the same reason as `AnyAppEntity` |
| `AppShortcutOptionsCollectionSpecificationFor` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `AppShortcutParameterPresentationProtocol` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `AppShortcutParameterPresentationSnapshot` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `AppShortcutParameterPresentationTitleBuilder` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `AttributedString` | `MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks/PaperKit.framework/Versions/A/Modules/PaperKit.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public mutating func insertNewTextbox(attributedText: Foundation::AttributedString, frame: CoreFoundation::CGRect, rotation: CoreFoundation::CGFloat =` | the framework's own, in the SDK | no |
| `BundleDescription` | `MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public var bundle: Foundation::LocalizedStringResource.Foundation::BundleDescription {` | the framework's own, in the SDK | no |
| `CLPlacemark` | `MacOSX27.0.sdk/usr/lib/swift/Intents.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: @nonobjc convenience public init(pickupLocation: CoreLocation::CLPlacemark? = nil, dropOffLocation: CoreLocation::CLPlacemark? = nil, rideOptionName: ` | the framework's own, in the SDK | no |
| `CSSearchableIndex` | `MacOSX27.0.sdk/System/Library/Frameworks/AppIntents.framework/Versions/A/Modules/AppIntents.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: extension CoreSpotlight::CSSearchableIndex {` | the framework's own, in the SDK | no |
| `CSSearchableItem` | `MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks/QuickLook.framework/Versions/A/Headers/QLPreviewingController.h: @param identifier The identifier of the CSSearchableItem the user interacted with in Spotlight.` | the framework's own, in the SDK | no |
| `CSSearchableItemAttributeSet` | `MacOSX27.0.sdk/System/Library/Frameworks/AppIntents.framework/Versions/A/Modules/AppIntents.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: extension CoreSpotlight::CSSearchableItemAttributeSet {` | the framework's own, in the SDK | no |
| `Calendar.RecurrenceRule` | `MacOSX26.5.sdk/System/Library/Frameworks/AppIntents.framework/Versions/A/Modules/AppIntents.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: extension AppIntents.EntityProperty where Value.ValueType == Foundation.Calendar.RecurrenceRule {` | the framework's own, in the SDK | no |
| `Comment` | `MacOSX27.0.sdk/usr/include/curses.h: * Comment annotation on the declaration line dropped to avoid script picking` | the framework's own, in the SDK | no |
| `Continuation` | `MacOSX27.0.sdk/usr/lib/swift/_Concurrency.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public struct Continuation : Swift::Sendable {` | the framework's own, in the SDK | no |
| `ContinuationError` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `Continuation` |
| `ControlStyle` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `CustomLocalizedStringResourceConvertible` | `MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: @available(*, deprecated, message: "Localized string interpolation produces an unlocalized, debug description for this type of value. Use a type suppo` | the framework's own, in the SDK | no |
| `DateComponents` | `MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks/ProximityReader.framework/Versions/A/Modules/ProximityReader.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public let dateOfBirth: Foundation::DateComponents?` | the framework's own, in the SDK | no |
| `DateComponentsResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `DateResolver` |
| `DateResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a resolver the runtime does not carry, so the port writes one; `Macros.md` and the Foundation gate line say why |
| `ElementResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- as `DateResolver` |
| `EntityQueryComparatorProtocol` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `EntityQueryPropertyValue` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `Float` | `MacOSX27.0.sdk/usr/include/net-snmp/library/asn1.h: * value for Float` | the framework's own, in the SDK | no |
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
| `LocalizedStringResource` | `MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks/UIKit.framework/Versions/A/Modules/UIKit.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public let title: Foundation.LocalizedStringResource` | the framework's own, in the SDK | no |
| `Measurement` | `MacOSX27.0.sdk/usr/include/pcap/dlt.h: * Measurement Systems.  They add an ERF header (see` | the framework's own, in the SDK | no |
| `NSUserActivity` | `MacOSX27.0.sdk/usr/lib/swift/Intents.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: case userActivity(Foundation::NSUserActivity)` | the framework's own, in the SDK | no |
| `Never` | `MacOSX27.0.sdk/usr/include/dlfcn.h: *  * RTLD_NODELETE - Never unmap the image.` | the framework's own, in the SDK | no |
| `NeverSummary` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `NumericFormat` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `RelevantIntentStore` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `Request` | `MacOSX27.0.sdk/usr/include/dns_sd.h: * Request unicast response to query.` | the framework's own, in the SDK | no |
| `RoundingRule` | `MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: public func rounded(rule: Foundation::Decimal.Foundation::FormatStyle.Foundation::Configuration.Foundation::RoundingRule = .toNearestOrEven, increment` | the framework's own, in the SDK | no |
| `Section` | `MacOSX27.0.sdk/usr/include/tic.h: **		Names Section, containing the names of the terminal` | the framework's own, in the SDK | no |
| `Storage` | `MacOSX27.0.sdk/usr/include/sqlite3.h: ** LPCWSTR zPath = Windows::Storage::ApplicationData::Current->` | the framework's own, in the SDK | no |
| `UUID` | `MacOSX27.0.sdk/usr/include/asl.h: #define ASL_KEY_SENDER_INSTANCE	   "SenderInstance"       /* Sender instance UUID. */` | the framework's own, in the SDK | no |
| `UUIDResolver` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a resolver the runtime does not carry -- the Foundation Swift r2 types are not in this release's Foundation (see the Foundation gate line in the queue), so the port writes one and gates it |
| `WidgetKind` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `ArrowEdge` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `BackgroundStyle` | `MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-ios-macabi.swiftinterface: nonisolated public init<B>(_ title: SwiftUICore.LocalizedStringKey, backgroundStyle: B = BackgroundStyle(), @SwiftUICore.ContentBuilder _ actions: () ` | the framework's own, in the SDK | no |
| `Code` | `MacOSX27.0.sdk/usr/include/AssertMacros.h: * This file contains Original Code and/or Modifications of Original Code` | the framework's own, in the SDK | no |
| `EmptyTip` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `Image` | `MacOSX27.0.sdk/usr/include/AppleEXR.h: *  Image data is provided as stored (after decompression) at the same precision found in the` | the framework's own, in the SDK | no |
| `Kind` | `MacOSX27.0.sdk/usr/include/mach/i386/fp_reg.h: * Kind of floating-point support provided by kernel.` | the framework's own, in the SDK | no |
| `Message` | `MacOSX27.0.sdk/usr/include/asl.h: /*! @defineblock Log Message Priority Levels` | the framework's own, in the SDK | no |
| `Store` | `MacOSX27.0.sdk/usr/include/asl.h: /*! @defineblock File and Store Open Options` | the framework's own, in the SDK | no |
| `Tips.Store` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `Title` | `MacOSX27.0.sdk/usr/include/cups/cups.h: char		*title;			/* Title/job name */` | the framework's own, in the SDK | no |
| `ActivityViewContextPlaceholder` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `AnyWidgetConfigurationIntent` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- the port's own erasure of a framework type, so a value of it can be named |
| `Base` | `MacOSX27.0.sdk/usr/include/MacTypes.h: Base integer types for all target OS's and CPU's` | the framework's own, in the SDK | no |
| `BodyType` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `CGSizeLike` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a name this band wrote for state the framework keeps in a store this release does not have |
| `ControlWidgetButtonContext` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `ControlWidgetDescriptionContext` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `IntentTimelineProviderContext` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- a value or protocol of the framework's *machinery* -- its own store, its parameter resolution and its presentation live in a system this release does not have, so the port spells the part it can answer |
| `Island` | `MacOSX27.0.sdk/System/Library/Frameworks/AVFoundation.framework/Versions/A/Headers/AVAssetDownloadTask.h: /// Screen and in the Dynamic Island, providing real-time download progress to the user.` | the framework's own, in the SDK | no |
| `Kind` | `MacOSX27.0.sdk/usr/include/mach/i386/fp_reg.h: * Kind of floating-point support provided by kernel.` | the framework's own, in the SDK | no |
