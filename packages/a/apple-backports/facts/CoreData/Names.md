# The CoreData names of iOS 7.0 to 18.0: which seven are carried, and what the other twenty-two are

The corpus lists **29 CoreData constant rows as missing. Seven are carried here; the other 22 are not
this band's work, and each of the 22 is accounted for below.** The measurement that decided it is
`registry/CoreData.json`: nine of the 22 are **already decided `absent` there**, with reasons and a
facts file, and COORDINATION §5 is explicit that an explicit registry decision outranks a find in the
tree. Carrying a name another band decided against, with a different reason, is not this band's call.

## The seven carried

`NSPersistentStoreCoordinatorStoresWillChangeNotification` (7.0),
`NSPersistentStoreDeferredLightweightMigrationOptionKey` (14.0),
`NSCoreDataCoreSpotlightDelegateIndexDidUpdateNotification` (14.0),
`NSPersistentCloudKitContainerEventChangedNotification` (14.0),
`NSPersistentCloudKitContainerEventUserInfoKey` (14.0),
`NSPersistentStoreStagedMigrationManagerOptionKey` (17.0) and
`NSPersistentStoreModelVersionChecksumKey` (18.0) — in `CoreDataNames{70,140,170,180}.m`, one release
each, with `registry/CoreData/names.json`.

Not typed. Each value is read out of the arm64e shared cache of iOS 18.0 through its own symbol with
`tools/cfconst.py`. **Two of the seven are not their own text at all**, which is the whole reason they
are read and never typed:

| symbol | the value CoreData holds |
| --- | --- |
| `NSPersistentStoreModelVersionChecksumKey` | `NSStoreModelVersionChecksumKey` |
| `NSPersistentCloudKitContainerEventUserInfoKey` | `event` |
| the other five | their own names |

A notification name and an option key are what a store is *asked for by*. `NSPersistentStore…OptionKey`
spelled as the constant's name would be a key nothing on any release answers to.

**Checked against a second source**, the host's own CoreData, which exports all seven:
`tests/backports/host/coredatanames` reads each value on both sides and compares — **7 agreed, 0
differed**.

## The five recorded absent beside them, and why

`NSPersistentStoreRebuildFromUbiquitousContentOption`, `…RemoveUbiquitousMetadataOption`,
`…UbiquitousContainerIdentifierKey`, `…UbiquitousPeerTokenOption` and `…UbiquitousTransitionTypeKey` are
iCloud, and **iOS 6 has no iCloud and no ubiquitous container at all**. The sibling names of this
family are already `absent` in `registry/CoreData.json` with that reason; these five were the same
family left silent, and they are now decided the same way rather than left to a reader to guess.
A dictionary of this shape can be built on this release; it changes nothing, and an application that
checks for the key before writing it is told the truth.

## The seven that are not symbols at all

`NSManagedObjectContext.NotificationKey.queryGeneration` (10.0), the same key's `deletedObjectIDs`,
`insertedObjectIDs`, `invalidatedObjectIDs`, `refreshedObjectIDs` and `updatedObjectIDs` (10.3), and
`NSManagedObjectContext.ScheduledTaskType.enqueued` and `.immediate` (15.0) are **Swift enum cases**.
The compiler writes the value into a Swift caller; there is no symbol for an Objective-C library to
export, so no row of this kind can be a missing symbol. They are the Swift overlay's work and a
different deliverable, and nothing is owed for them here.

## The nine the registry already decides

`registry/CoreData.json` already carries nine of the corpus's CoreData constant rows as `absent` with
reasons and a `maximum` where the band set one — among them `NSManagedObjectContextQueryGenerationKey`,
whose stated reason is that query generations pin a context to a write-ahead-logging snapshot and the
store of iOS 6 keeps a rollback journal and reads the latest rows only. **Those nine are not missing
work: they are decisions the corpus does not read.** The corpus's `missing` column says the release
exports no such symbol, which is true of all of them; it cannot see that the registry has already
answered. Every registry row this band adds is recorded in the corpus's own terms and the difference is
this file, so the next reader does not have to rediscover it.
