# The CoreSpotlight classes AppIntents extends

The five rows this module adds to CoreSpotlight - `CSSearchableIndex.indexAppEntities(_:priority:)`,
`.deleteAppEntities(ofType:)`, `.deleteAppEntities(identifiedBy:ofType:)`,
`CSSearchableItem.init(appEntity:)` and `.init(appEntity:priority:)`, plus
`associateAppEntity(_:priority:)` on the item and its attribute set - are AppIntents' own extensions on
the three classes the CoreSpotlight backports carry (`registry/CoreSpotlight/ios9.json`: all three
`implemented`, with the store the port keeps under `/var/mobile/Library/Caches/org.charon.corespotlight`
and the bridge to the release's own `SPSpotlightManager`).

## Why the classes needed an overlay of their own

The SDK marks the three classes iOS 9, in the framework's own macros:

    CS_CLASS_AVAILABLE(10_13, 9_0)
    CS_TVOS_UNAVAILABLE
    @interface CSSearchableIndex : NSObject

`apple.lift` lowers availability for the seven frameworks in its `FRAMEWORKS` list, and its rewriter
(`lift.lift_macro`) names `API_AVAILABLE`, `NS_AVAILABLE`, `NS_CLASS_AVAILABLE`, `CF_AVAILABLE`,
`NS_DEPRECATED` and the `*_IOS` family. `CS_CLASS_AVAILABLE` and `CS_AVAILABLE` are in none of them,
and CoreSpotlight is not in the list, so the lift leaves every mark where it is - measured: a Swift
file naming `CSSearchableIndex` at `armv7-apple-ios6.1.3` answers "'CSSearchableIndex' is only
available in iOS 9.0 or newer".

So `modules/apple/spotlight_lift.lua` does it for this module, with the lift's own three rules: only
what the registry carries is lowered, the rewrite is at the place the macro is written, and both ways
are checked before the overlay is used. It lowers fifteen marks for the release: the three classes,
the twelve categories of them (`CSOptionalBatching`, `CSCustomAttributes`, `CSDocumentsIndex`, the four
in `_General`, `_CSEvents`, `_CSImage`, `_CSMedia`, `_CSMessaging`, `_CSPlaces`), and four members of
their own surface - the one initializer the port's own attribute set is built with
(`initWithItemContentType:`, whose `API_DEPRECATED(..., ios(9.0, ...))` the SDK would otherwise
refuse at 6.1.3), `compareByRank:`, and two properties.

It refuses the overlay, rather than producing one that lies, when a class the registry says is
implemented is not declared by the SDK's headers, when a class the rewrite touched is not one the
registry carries as implemented, and when the registry grows an entry for a *member* of these classes
with a status other than `implemented` - a member the registry has decided on keeps its mark in
`apple.lift`, and this rewriter lowers a class's whole surface and cannot keep one member marked.

## What the extensions do

`indexAppEntities` builds a `CSSearchableItem` per entity and hands them to `indexSearchableItems`,
which is the port's own store - the same call any other caller of CoreSpotlight makes, so an entity
indexed here is found by the port's search and not only by AppIntents. The entry's content type is
the entity type's name, its title and description are the entity's own display representation, and its
keywords are the entity's synonyms; the entity's identifier is written under
`appEntityIdentifier`, the key the framework's own search result reads.

`deleteAppEntities(ofType:)` and `deleteAppEntities(identifiedBy:ofType:)` read the journal the
backports keep - the same plists, over the same files - for the identifiers of one content type, and
hand them to `deleteSearchableItems`. With no CoreSpotlight backports there is no index and nothing
is removed, which is what a delete of an index that holds nothing does.

The two `NSUserActivity` rows (`widgetConfigurationIntent(of:)`, `appEntityIdentifier`) are behind
`-DCHARON_APPINTENTS_LIFTED_HEADERS`, which the package sets when the runtime it builds against was
built with the backports: `NSUserActivity` arrived in iOS 8 and the Foundation backports carry it, and
the runtime is what hands the lifted headers over. They place on such a runtime; with a runtime built
without the backports there is no `NSUserActivity` on the release at all, and the rows read `missing`
rather than being declared against a class that is not there.
