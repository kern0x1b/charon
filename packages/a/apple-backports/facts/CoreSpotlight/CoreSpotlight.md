# CoreSpotlight, iOS 9

`CSSearchableIndex`, `CSSearchableItem`, `CSSearchableItemAttributeSet`, `CSSearchableItemActionType`
and `CSSearchableItemActivityIdentifier` are strong-imported LOAD-FAIL symbols for provenance and
telegram, two applications of the corpus. A hard-linked class or C symbol that is absent kills the
application at launch — dyld fails to bind the non-weak import — so the classes and constants are
carried, not marked absent.

The functions live in `libCoreSpotlightBackports.dylib`, built with the `corespotlight` config,
because CoreSpotlight is the only framework it loads besides Foundation.

## What the device has

An iPhone 4S and an iPad 2 on iOS 6.1.3 have no CoreSpotlight framework and no on-device Spotlight
index an application can write to. What the device does have is `Spotlight.framework`, a private
framework, carrying `SPSpotlightManager` (`+sharedManager`, `-application:modifiedRecordIDs:forCategory:`,
`-eraseIndexForApplication:category:`) — Apple's own pre-CoreSpotlight indexing mechanism, used
in this release by Messages and Calendar. It is a **pull** model: the system asks the app for the
record IDs it changed and the app answers from its own store; there is no header, and no published
contract for the delegate protocol the manager calls back into. CoreSpotlight's `CSSearchableIndex`
is a **push** model: the app hands the index whole items and the index journals them. The two do
not compose — bridging one onto the other would be guessing at a private, undocumented protocol,
which is worse than an honest refusal. This is the wall the verdict allows `documented-absent` to
stand at: the write seam, not the class.

Confirmed by extracting `Spotlight.framework` and searching the armv7 shared cache of iOS 6.1.3 for
`CSSearchable`, `MobileSpotlight` and `CoreSpotlight`: none of those names are exported by the
release at all; only `SPSpotlightManager` and the apps that already use it privately (Messages'
`CKSpotlightQuery`, Calendar's `CalSpotlightSearch`) are there.

## What the port does

`CSSearchableIndex.isIndexingAvailable` answers `NO`, `defaultSearchableIndex` and `initWithName:`
give a real instance (an index that exists but writes nowhere is what a device that answers
`isIndexingAvailable == NO` looks like on a release that does have the framework), and every write
method calls its completion handler with an `NSError` of `CSIndexErrorDomain`,
`CSIndexErrorCodeIndexingUnsupported` (-1005) — the release's own code and text for "Indexing isn't
supported on this device," read from the comment beside the enum case in the header of iOS 16.4, not
invented. `beginIndexBatch` does nothing, since there is no batch to begin. `CSSearchableItem` and
`CSSearchableItemAttributeSet` are ordinary real objects independent of whether the index ever
writes them: `CSSearchableItem` generates a UUID when no identifier is given and defaults
`expirationDate` to one month out, resetting to that default when set to `nil`, exactly as the
header says; `CSSearchableItemAttributeSet` carries the 19 properties of the `CSGeneral` category —
the ones the header gives no later than iOS 9.0 (`displayName`, `alternateNames`, `path`,
`contentURL`, `thumbnailURL`, `thumbnailData`, `relatedUniqueIdentifier`, `metadataModificationDate`,
`contentType`, `contentTypeTree`, `keywords`, `title`, `version`, `supportsPhoneCall`,
`supportsNavigation`, `containerTitle`, `containerDisplayName`, `containerIdentifier`,
`containerOrder`) with real storage, `NSCopying` and `NSSecureCoding`.

## What differs from the release

The `Images`, `Media`, `Documents`, `Events`, `Places` and `Messaging` attribute categories and the
custom-key API are not carried: an application that reads or writes one of those properties sends a
message this port does not implement. `indexDelegate` is kept but never messaged, since nothing is
ever indexed to ask a reindex for. The two continuation constants
(`CSSearchableItemActionType` = `"com.apple.corespotlightitem"`, `CSSearchableItemActivityIdentifier`
= `"kCSSearchableItemActivityIdentifier"`) are carried at the release's own values, extracted from
`CoreSpotlight` of the arm64 shared cache of iOS 12.0 (`_CSSearchableItemActionType` and
`_CSSearchableItemActivityIdentifier`, each a pointer to a `CFConstantString`, read with
`modules/apple/dyld.lua`'s `pointer_at`/`string_at`), but neither is ever posted by this port: no
item of this port's making is ever surfaced by the system's Spotlight for the user to tap, so the
continuation path they describe never runs here. `CSIndexErrorDomain` = `"CSIndexErrorDomain"`,
extracted the same way.
