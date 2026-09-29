#import <CoreData/CoreData.h>

// The CoreData names of iOS 14.0, with the texts CoreData itself gives them, read out of the arm64e
// shared cache of iOS 18.0 through each symbol with tools/cfconst.py (facts/CoreData/Names.md).
//
// One file for the one release these arrived in: an object carries the API of a single release.
//
// The text is the release's own and is NOT the name of the symbol, and that is the whole point of reading
// it: the userInfo keys of the object-ID notifications are inserted_objectIDs and its four siblings, the
// query generation key is newQueryGeneration and the pool key NSPersistentStoreConnectionPoolMaxSize, while
// the five ubiquitous names of 7.0 are their own. A spelling of the constant would be a key that the
// release never fills and no release ever reads.

NSString * const NSPersistentStoreDeferredLightweightMigrationOptionKey = @"NSPersistentStoreDeferredLightweightMigrationOptionKey";
NSString * const NSCoreDataCoreSpotlightDelegateIndexDidUpdateNotification = @"NSCoreDataCoreSpotlightDelegateIndexDidUpdateNotification";
NSString * const NSPersistentCloudKitContainerEventChangedNotification = @"NSPersistentCloudKitContainerEventChangedNotification";
NSString * const NSPersistentCloudKitContainerEventUserInfoKey = @"event";
