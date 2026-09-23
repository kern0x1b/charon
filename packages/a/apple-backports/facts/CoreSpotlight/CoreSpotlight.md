# CoreSpotlight, iOS 9

`CSSearchableIndex`, `CSSearchableItem`, `CSSearchableItemAttributeSet`, `CSSearchableItemActionType`
and `CSSearchableItemActivityIdentifier` are strong-imported LOAD-FAIL symbols for provenance and
telegram, two applications of the corpus. A hard-linked class or C symbol that is absent kills the
application at launch — dyld fails to bind the non-weak import — so the classes and constants are
carried, not marked absent.

The functions live in `libCoreSpotlightBackports.dylib`, built with the `corespotlight` config,
because CoreSpotlight is the only framework it loads besides Foundation.

## The earlier verdict, retracted

An earlier pass of this port answered every write with `CSIndexErrorCodeIndexingUnsupported` and
called `isIndexingAvailable` a `documented-absent` seam, on the reasoning that iOS 6.1.3's own
`SPSpotlightManager` is a pull model and `CSSearchableIndex` is a push model, and bridging one onto
the other would be guessing at an undocumented private protocol. That reasoning does not hold: a
private, undocumented protocol is work, not a wall, the same way the Swift runtime and Metal-over-ES2
were work. The write seam is reversible, and this pass reverses it.

## What the device has

An iPhone 4S and an iPad 2 on iOS 6.1.3 have no CoreSpotlight framework and no on-device Spotlight
index an application can write to in Apple's own sense of the word. What they do have:

- `Spotlight.framework` (`/System/Library/PrivateFrameworks/Spotlight.framework/Spotlight`), a
  private framework carrying exactly one Objective-C class, `SPSpotlightManager`. Its full method
  and property list, read from `__objc_methname`/`__objc_classname` of the extracted binary:
  `init`, `dealloc`, `alloc`, `+sharedConnection`, `+defaultManager`, `+sharedManager`,
  `-startRecordUpdatesForApplication:andCategory:`, `-endRecordUpdatesForApplication:andCategory:`,
  `-requestRecordUpdatesForApplication:category:andIDs:`,
  `-_processIdentifiers:forApplication:andCategory:`, `-notifyIndexer`,
  `-appModifiedRecordIDs:forCategory:`, `-application:modifiedRecordIDs:forCategory:`,
  `-eraseIndexForApplication:category:`, plus the record-field names `_displayID`, `external_id`,
  `title`, `subtitle`, `summary`, `aux_title`, `aux_subtitle`, `category`, `content`. Objective-C
  type encodings confirm two-object-argument methods (`v16@0:4@8@12`, e.g.
  `startRecordUpdatesForApplication:andCategory:`) and three-object-argument methods
  (`v20@0:4@8@12@16`, e.g. `application:modifiedRecordIDs:forCategory:`); every argument is `@`
  (an object), so no primitive width can be wrong at the `objc_msgSend` boundary. `__text` is 0x1d4
  bytes: most of these selectors are thin forwarders to two shared internal C entry points at
  `0x366a1d78`/`0x366a1d88`, so the substantive per-selector logic (how a category's registration is
  kept, how a pull answer is actually assembled from the `_displayID`/`title`/... record fields)
  lives past those stubs and was not traced further — the class surface, not the control flow inside
  it, is what this port bridges to.
- `Search.framework` (`/System/Library/PrivateFrameworks/Search.framework/Search`), which owns
  `-_loadSearchBundles`, backed by `-contentsOfDirectoryAtPath:error:` reading each bundle's
  `principalClass` — a real directory scan, not a hardcoded table.
- Exactly eleven search bundles on the device, all Apple's own, found by listing the shared cache:
  `/System/Library/SearchBundles/{AddressBook,Application,Extended,MobileCal,MobileMail,MobileNotes,
  Reminders,TopHits,VoiceMemos,iPod}.searchBundle` and
  `/System/Library/Spotlight/SearchBundles/SMSSearch.searchBundle`. None of them is a general,
  per-installed-app entry point.
- `Application.searchBundle`'s own extracted binary names its source file as
  `SPApplicationDatastore.m` and carries the string `categoryForDomain:` — it matches installed
  application names on its own, independent of `SPSpotlightManager`'s category registration.

Confirmed by extracting both frameworks and both search bundles named above out of the armv7 shared
cache of iOS 6.1.3 with `modules/apple/dyld.lua`'s `extract` and reading their `__objc_methname`,
`__objc_classname` and `__cstring` sections with `strings`/`otool -l`; `CSSearchable`,
`MobileSpotlight` and `CoreSpotlight` are exported by none of the release's images at all.

## The `extract` bug this pass fixed

`modules/apple/dyld.lua`'s `extract` failed with `bad argument #2 to 'pack' (unsigned overflow)` on
`Spotlight.framework`, and would fail identically on any image whose `LC_DYLD_INFO_ONLY` carries a
zero-length field (`weak_bind_size` or similar) at a nonzero offset. The bounds pass that computes
`first`/`last` (and so the relocation `shift`) already excludes zero-length fields
(`if offset > 0 and length > 0`); the rewrite pass that applies `shift` did not, so a zero-length
field's stale, out-of-[first,last) offset was shifted into a huge negative number and handed to
`string.pack("<I4", ...)`. Fixed by applying the same `length > 0` guard on the write side; a
zero-length field is written back as `0`, since nothing ever reads at it. Verified by re-extracting
`Spotlight.framework` (previously a hard failure) and cross-checking the rebuilt Mach-O header's
segment/symtab/dysymtab bounds against the file size in Python — all within range, unlike the earlier
attempt's `183410688 + (8192 - 187111415) = -3692535`.

## What the port does

`CSSearchableIndex` keeps its own journal: a `CharonSpotlightStore` per index name, a property-list
of archived `CSSearchableItem`s and the batch client state, under Application Support at
`space.kern0x1b.corespotlight/<name>.plist`. `indexSearchableItems:completionHandler:` and the three
delete methods write or remove entries and call their handler with a `nil` error — a real journal, not
a `documented-absent` refusal — and `endIndexBatchWithClientState:completionHandler:` /
`fetchLastClientStateWithCompletionHandler:` persist and return the client state exactly as the
header describes, including refusing batching on `defaultSearchableIndex`. `isIndexingAvailable`
answers `YES`: the index genuinely indexes.

Every mutation also calls `CharonSpotlightBridge`, which `dlopen`s `Spotlight.framework`,
resolves `SPSpotlightManager` and `+sharedManager` with `NSClassFromString`/`objc_msgSend`, registers
the index's category (the application's own bundle identifier) with
`-startRecordUpdatesForApplication:andCategory:`, and on each write pushes the changed identifiers
with `-requestRecordUpdatesForApplication:category:andIDs:` followed by `-notifyIndexer`. Every call
is guarded by `respondsToSelector:` and wrapped in `@try`/`@catch`, off the main thread, so an
unexpected private-framework surface can never turn into a fatal error for the host application: this
is the honest bridge to the private class, not a fabricated success.

## What is not proven

`SPSpotlightManager`'s registration and push calls were exercised against a private class whose
control-flow past the two shared stub entry points was not traced, so whether the manager journals a
category it has never seen from a first-party bundle, and whether the `_displayID`/`title`/... record
fields need to accompany the pushed identifiers for the pull side to answer anything, are both
unmeasured on-device. What is measured and closes the loop regardless of that answer: even a
perfectly accepted registration cannot reach the user, because the system's own search surface is the
fixed eleven-bundle list above, none of which reads a third-party category, and
`Application.searchBundle` (the one bundle that does look at installed apps) bypasses
`SPSpotlightManager` entirely.

**The twelfth entry named above is now built, not just filed as buildable.**
`packages/a/apple-backports/CoreSpotlight/SearchBundle/CharonSearchDatastore.m` is
`org.charon.corespotlight.searchBundle`'s principal class - a real runtime subclass of the
release's own `SPSearchDatastore` (`objc_allocateClassPair` over the class
`Search.framework` exports, not a bare `NSObject` that happens to answer the protocol), packaged
by `write_searchbundle` in `modules/apple/backports.lua` and installed at
`/System/Library/SearchBundles/org.charon.corespotlight.searchBundle/` by the same `.deb` this
port already writes, whenever `corespotlight` is among the staged libraries. The protocol it
implements was read from `NotesDatastore` (`MobileNotes.searchBundle`'s own principal class) with
`llvm-otool -oV` and each selector resolved against the iOS 6.1.3 shared cache directly
(`.agent-work/handoffs/2026-09-23-corespotlight-searchbundle-measurement.md`), which corrected two
selector names an earlier `strings`-only pass got wrong (`-categoryForDomain:` and
`-wantsEveryResultInItsOwnSection` are not implemented by `NotesDatastore` at all - the real
required methods are `-displayIdentifierForDomain:`, `-searchDomains` and
`-performQuery:withResultsPipe:`). `-performQuery:withResultsPipe:` filters every app's stored
items (case-insensitive substring match against `attributeSet.title`/`.contentDescription`) and
pushes matches through `-[resultsPipe addResults:]`, the way `NotesDatastore` itself does.

This forced a real correction to `CSSearchableIndex` itself:
`CharonSpotlightStoreDirectory` wrote under `NSApplicationSupportDirectory`, sandboxed to the
indexing application's own container - a location no search bundle, running in whatever process
hosts system search, could ever read. It now writes under
`/var/mobile/Library/Caches/org.charon.corespotlight/<bundle identifier>/`, world-readable
(`0777`), the same shared-cache bridge pattern `org.charon.callkit` already uses to cross the same
kind of process boundary. `CharonSearchDatastore.m` resolves `CSSearchableItem` - this port's own
class, not Apple's, so no compile-time link is possible - by `dlopen`ing the installed
`libCoreSpotlightBackports.dylib` symlink before unarchiving, and every value that crosses that
boundary is typed `id` and read with `valueForKey:`, never a static `CSSearchableItem *`, since
this bundle is built once, not per band.

Not yet measured, because it needs a device with a running system search host: whether the daemon
that scans `/System/Library/SearchBundles/` re-reads it after install without a reboot, and whether
a real query against this datastore's one domain actually reaches `-performQuery:withResultsPipe:`
and shows a result on screen. That is the one measurement everything above was built to make
possible, filed as the next device pass rather than assumed.

## What differs from the release

The `Images`, `Media`, `Documents`, `Events`, `Places` and `Messaging` attribute categories and the
custom-key API are not carried: an application that reads or writes one of those properties sends a
message this port does not implement. `indexDelegate` is kept but never messaged: nothing in this
port's own runtime ever loses the journal the way the real index's remote process can, so there is
never a `reindexAllSearchableItemsWithAcknowledgementHandler:`/
`reindexSearchableItemsWithIdentifiers:acknowledgementHandler:` call to make. The two continuation
constants (`CSSearchableItemActionType` = `"com.apple.corespotlightitem"`,
`CSSearchableItemActivityIdentifier` = `"kCSSearchableItemActivityIdentifier"`) are carried at the
release's own values, extracted from `CoreSpotlight` of the arm64 shared cache of iOS 12.0
(`_CSSearchableItemActionType` and `_CSSearchableItemActivityIdentifier`, each a pointer to a
`CFConstantString`, read with `modules/apple/dyld.lua`'s `pointer_at`/`string_at`), but neither is
ever posted by this port: no item of this port's making is ever surfaced by the system's Spotlight
for the user to tap, so the continuation path they describe never runs here — see above for why, and
for what closing that gap actually requires. `CSIndexErrorDomain` = `"CSIndexErrorDomain"`, extracted
the same way.
