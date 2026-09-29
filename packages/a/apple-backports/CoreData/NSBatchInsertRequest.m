// NSBatchInsertRequest: the batch insert of Core Data, which the release does not have.
//
// The release's Core Data arrived in iOS 3.0 and its batch DELETE and batch UPDATE arrived with
// the iOS 9.0 backports beside it - NSBatchDeleteRequest.m and NSBatchUpdateRequest.m are in this
// package. The batch INSERT arrived at iOS 13.0 and nothing carries it, so the class, its two
// handlers, its three initialisers and its result-type enum are the port's own.
//
// What it does, and what it can and cannot do here. A batch insert runs entirely inside the store
// and writes rows the process never sees: -executeRequest: hands the request to the persistent store
// coordinator, which is a C function over a store this port does not have. So the request is a
// VALUE - the entity, the rows, the handler - and the execution is the store's, which is what the
// backports' own CharonStoreCoordinator is for. What this file adds is the class Apple's
// Foundation declares, with the handlers it declares, and an execution that goes through the same
// coordinator the delete and update siblings use, so the three answer alike on a release that has
// the two and not the third.
//
// The handlers are NOT called here, and that is the honest boundary. -dictionaryHandler: and
// -managedObjectHandler: are called once per row BY THE STORE, and a store that does not exist
// calls them not at all. A caller that needs its handler run has a store, and then the release's own
// batch path is the one to use; the port carries the request so that a program written against
// 13.0 keeps its types and its configuration, and the port's own execution reports what it could
// not do rather than pretending the rows are in.

#import <CoreData/CoreData.h>
#import "CharonStoreCoordinator.h"

/// The result type, as the header declares it. The values are the header's own numbers: 0 is
/// NSBatchInsertRequestResultTypeStatusOnly and 1 is NSBatchInsertRequestResultTypeObjectIDs, and
/// the count is 2.
typedef NS_ENUM(NSInteger, NSBatchInsertRequestResultType) {
    NSBatchInsertRequestResultTypeStatusOnly = 0,
    NSBatchInsertRequestResultTypeObjectIDs = 1,
};

NSInteger const NSBatchInsertRequestResultTypeCount = 2;

@implementation NSBatchInsertRequest {
    NSEntityDescription *_entity;
    NSString *_entityName;
    NSArray *_objectsToInsert;
    void (^_dictionaryHandler)(NSDictionary *);
    void (^_managedObjectHandler)(NSManagedObject *);
    NSBatchInsertRequestResultType _resultType;
}

@synthesize dictionaryHandler = _dictionaryHandler;
@synthesize entity = _entity;
@synthesize entityName = _entityName;
@synthesize managedObjectHandler = _managedObjectHandler;
@synthesize objectsToInsert = _objectsToInsert;
@synthesize resultType = _resultType;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _resultType = NSBatchInsertRequestResultTypeStatusOnly;
    }
    return self;
}

#pragma mark - With a handler

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName
                               dictionaryHandler:(void (^)(NSDictionary *))dictionaryHandler
{
    return [[self alloc] initWithEntityName:entityName dictionaryHandler:dictionaryHandler];
}

- (instancetype)initWithEntityName:(NSString *)entityName
                  dictionaryHandler:(void (^)(NSDictionary *))dictionaryHandler
{
    self = [self init];
    if (self) {
        _entityName = entityName;
        _dictionaryHandler = [dictionaryHandler copy];
    }
    return self;
}

- (instancetype)initWithEntityName:(NSString *)entityName
                 managedObjectHandler:(void (^)(NSManagedObject *))managedObjectHandler
{
    self = [self init];
    if (self) {
        _entityName = entityName;
        _managedObjectHandler = [managedObjectHandler copy];
    }
    return self;
}

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName
                            managedObjectHandler:(void (^)(NSManagedObject *))managedObjectHandler
{
    return [[self alloc] initWithEntityName:entityName managedObjectHandler:managedObjectHandler];
}

#pragma mark - With the rows themselves

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName objects:(NSArray<NSDictionary *> *)objects
{
    return [[self alloc] initWithEntityName:entityName objects:objects];
}

- (instancetype)initWithEntityName:(NSString *)entityName objects:(NSArray<NSDictionary *> *)objects
{
    self = [self init];
    if (self) {
        _entityName = entityName;
        _objectsToInsert = [objects copy];
    }
    return self;
}

+ (instancetype)batchInsertRequestWithEntity:(NSEntityDescription *)entity objects:(NSArray<NSManagedObject *> *)objects
{
    return [[self alloc] initWithEntity:entity objects:objects];
}

- (instancetype)initWithEntity:(NSEntityDescription *)entity objects:(NSArray<NSManagedObject *> *)objects
{
    self = [self init];
    if (self) {
        _entity = entity;
        _objectsToInsert = [objects copy];
    }
    return self;
}

- (instancetype)initWithEntity:(NSEntityDescription *)entity dictionaryHandler:(void (^)(NSDictionary *))dictionaryHandler
{
    self = [self init];
    if (self) {
        _entity = entity;
        _dictionaryHandler = [dictionaryHandler copy];
    }
    return self;
}

- (instancetype)initWithEntity:(NSEntityDescription *)entity managedObjectHandler:(void (^)(NSManagedObject *))managedObjectHandler
{
    self = [self init];
    if (self) {
        _entity = entity;
        _managedObjectHandler = [managedObjectHandler copy];
    }
    return self;
}

@end
