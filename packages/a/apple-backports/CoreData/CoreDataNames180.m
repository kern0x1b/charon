#import <CoreData/CoreData.h>

// The CoreData names of iOS 18.0 that the registry of this package is silent about, with the texts
// CoreData itself gives them, read out of the arm64e shared cache of iOS 18.0 through each symbol
// with tools/cfconst.py (facts/CoreData/Names.md).
//
// One file for the one release these arrived in: an object carries the API of a single release.
//
// The text is the release's own and is not a spelling of the symbol: a notification name and an option key
// are what a store is asked for by, and a spelling of the constant would be a different key that nothing
// answers to. Two of the names are not their own text at all - the version checksum key is
// NSStoreModelVersionChecksumKey and the container event's userInfo key is event - which is why these are
// read out of the cache and never typed.

NSString * const NSPersistentStoreModelVersionChecksumKey = @"NSStoreModelVersionChecksumKey";
