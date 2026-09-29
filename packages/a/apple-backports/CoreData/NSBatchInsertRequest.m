// NSBatchInsertRequest: the batch insert of Core Data, which the release does not have.
//
// The release's Core Data arrived in iOS 3.0, its batch DELETE and batch UPDATE arrived with the
// iOS 9.0 backports beside it - NSBatchDeleteRequest.m and NSBatchUpdateRequest.m are in this
// package - and the batch INSERT arrived at iOS 13.0 with nothing carrying it. The 16.4 header the
// port lifts DECLARES the class, with an empty ivar block and five properties it has nowhere to
// keep, so the storage is in CharonCoreData.h and this file is only what that declaration does not
// carry.
//
// The types are the header's own (NSBatchInsertRequest.h:17-43), not the corpus's selector list,
// which spells labels and not types: both handlers RETURN BOOL, and objects: takes dictionaries on
// both the name and the entity form. The enum and NSBatchInsertRequestResultTypeCount are
// Apple's and are not redeclared here.
//
// What a batch insert DOES, and the boundary of this file. The handlers are called once per row BY
// THE STORE, and this port's store is the backports' coordinator over a release that has no batch
// insert at all: there is no C function to hand the request to. So this class is the request as a
// value - the entity, the rows, the handler, the result type - and it is what a program written
// against 13.0 configures. A caller that needs its rows in a store uses the store's own path, and
// the differential for this step is over exactly that: the request's own state, on the port's own
// in-memory store, with no write to any system store.

#import <CoreData/CoreData.h>
#import "CharonCoreData.h"

// The storage. The SDK declares the class with an EMPTY ivar block (NSBatchInsertRequest.h:17),
// so this extension is where its five properties are kept, and it is here rather than in
// CharonCoreData.h because an ivar block may only appear in a class's one interface and the SDK has
// that one - a second @interface for NSBatchInsertRequest is "duplicate interface definition", which
// is what the shared header produced.
@interface NSBatchInsertRequest () {
    NSString *_charonEntityName;
    NSEntityDescription *_charonEntity;
    NSArray<NSDictionary<NSString *, id> *> *_charonObjectsToInsert;
    BOOL (^_charonDictionaryHandler)(NSMutableDictionary<NSString *, id> *);
    BOOL (^_charonManagedObjectHandler)(NSManagedObject *);
    NSBatchInsertRequestResultType _charonResultType;
}
@end

@implementation NSBatchInsertRequest

@synthesize entityName = _charonEntityName;
@synthesize entity = _charonEntity;
@synthesize objectsToInsert = _charonObjectsToInsert;
@synthesize dictionaryHandler = _charonDictionaryHandler;
@synthesize managedObjectHandler = _charonManagedObjectHandler;
@synthesize resultType = _charonResultType;

#pragma mark - The initialiser the header deprecates -init in favour of

/// -init is API_DEPRECATED_WITH_REPLACEMENT("initWithEntityName", ios(13.0,14.0)), so it exists
/// and it leaves the request with no entity: a request with no entity is one no store can run, and
/// that is what an unconfigured one is.
- (instancetype)init
{
    return [self initWithEntityName:nil objects:@[]];
}

- (instancetype)initWithEntityName:(NSString *)entityName
                          objects:(NSArray<NSDictionary<NSString *, id> *> *)dictionaries
{
    self = [super init];
    if (self) {
        _charonEntityName = [entityName copy];
        _charonObjectsToInsert = [dictionaries copy];
    }
    return self;
}

- (instancetype)initWithEntity:(NSEntityDescription *)entity
                       objects:(NSArray<NSDictionary<NSString *, id> *> *)dictionaries
{
    self = [super init];
    if (self) {
        _charonEntity = entity;
        _charonObjectsToInsert = [dictionaries copy];
    }
    return self;
}

#pragma mark - With a handler

- (instancetype)initWithEntityName:(NSString *)entityName
                  dictionaryHandler:(BOOL (^)(NSMutableDictionary<NSString *, id> *))handler
{
    self = [self initWithEntityName:entityName objects:@[]];
    if (self) {
        _charonEntityName = [entityName copy];
        _charonDictionaryHandler = [handler copy];
    }
    return self;
}

- (instancetype)initWithEntityName:(NSString *)entityName
                 managedObjectHandler:(BOOL (^)(NSManagedObject *))handler
{
    self = [self initWithEntityName:entityName objects:@[]];
    if (self) {
        _charonEntityName = [entityName copy];
        _charonManagedObjectHandler = [handler copy];
    }
    return self;
}

- (instancetype)initWithEntity:(NSEntityDescription *)entity
               dictionaryHandler:(BOOL (^)(NSMutableDictionary<NSString *, id> *))handler
{
    self = [self initWithEntity:entity objects:@[]];
    if (self) {
        _charonEntity = entity;
        _charonDictionaryHandler = [handler copy];
    }
    return self;
}

- (instancetype)initWithEntity:(NSEntityDescription *)entity
            managedObjectHandler:(BOOL (^)(NSManagedObject *))handler
{
    self = [self initWithEntity:entity objects:@[]];
    if (self) {
        _charonEntity = entity;
        _charonManagedObjectHandler = [handler copy];
    }
    return self;
}

#pragma mark - The three class constructors the header declares

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName
                                         objects:(NSArray<NSDictionary<NSString *, id> *> *)dictionaries
{
    return [[self alloc] initWithEntityName:entityName objects:dictionaries];
}

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName
                               dictionaryHandler:(BOOL (^)(NSMutableDictionary<NSString *, id> *))handler
{
    return [[self alloc] initWithEntityName:entityName dictionaryHandler:handler];
}

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName
                            managedObjectHandler:(BOOL (^)(NSManagedObject *))handler
{
    return [[self alloc] initWithEntityName:entityName managedObjectHandler:handler];
}

@end
