// The on-disk store CSSearchableIndex.m writes and the search bundle (SearchBundle/
// CharonSearchDatastore.m, built on its own by write_searchbundle in modules/apple/backports.lua)
// reads: one directory per indexing application, each holding plists whose "entries" map a unique
// identifier to a keyed archive of a CSSearchableItem. Both sides include this header so the path
// has one definition.
#define CHARON_SPOTLIGHT_SHARED_ROOT @"/var/mobile/Library/Caches/org.charon.corespotlight"
