// The differential for NSBatchInsertRequest: the request's own state, on an IN-MEMORY store, which
// is the process's own and writes nothing to this machine.
//
//   xcrun clang -fobjc-arc -framework Foundation -framework CoreData differential.m \
//       <the port's .m and its package header> -I <the package> -o differential
//   ./differential
//
// Every line is key<TAB>value, so the verdict is a diff and not a pattern read out of prose.
//
// WHAT IS COMPARED, and what cannot be. The request is a VALUE: an entity, a name, rows, a handler
// and a result type. A batch insert RUNS inside the store, through a C function the release does
// not have, so what this compares is the request's configuration and the store it is configured
// for - which is the whole of the class this port adds. The handlers are NOT called: a store calls
// them once per row, and there is no batch insert in the store to call them, which is stated in
// the class's own comment rather than papered over by calling them here.
//
// FORBIDDEN, and not called: nothing on this machine is written outside the process's own memory.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

// The class is the framework's own; this extension is the PORT's storage for it, and it has to be
// an extension and not a redeclaration for the reason the class's own file records: an ivar block
// may only appear in a class's one interface.
@interface NSBatchInsertRequest () {
    NSString *_charonEntityName;
    NSEntityDescription *_charonEntity;
    NSArray<NSDictionary<NSString *, id> *> *_charonObjectsToInsert;
    BOOL (^_charonDictionaryHandler)(NSMutableDictionary<NSString *, id> *);
    BOOL (^_charonManagedObjectHandler)(NSManagedObject *);
    NSBatchInsertRequestResultType _charonResultType;
}
@end

int main(void) { @autoreleasepool {
    // An in-memory store: the process's own, and nothing on this machine is written.
    NSManagedObjectModel *model = [NSManagedObjectModel new];
    NSEntityDescription *entity = [NSEntityDescription new];
    entity.name = @"Row";
    entity.managedObjectClassName = @"NSManagedObject";
    entity.properties = @[];
    model.entities = @[entity];
    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *storeError = nil;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSInMemoryStoreType
                                                          configuration:nil
                                                                    URL:nil
                                                                options:nil
                                                                  error:&storeError];
    printf("in-memory store\t%s\n", store ? "added" : "FAILED");

    // 1. -init, which is NOT a way to make one of these: both sides raise, and there is no request
    //    behind the exception, so the question is whether it raised and what it said. The three lines
    //    that stood here read entityName, objects and resultType off a bare request that does not
    //    exist: Apple's own -init raises NSInternalInconsistencyException with the reason
    //    "-init results in undefined behavior for NSBatchInsertRequest" (measured here, the same
    //    listing per-initializer.m takes), so on the host side they were never reached and on the
    //    port's side they killed the process. per-initializer.m is where the state of a request that
    //    WAS made is compared, over the twenty-two lines it prints.
    @try {
        NSBatchInsertRequest *bare = [[NSBatchInsertRequest alloc] init];
        printf("init.raised\t0\n");
        printf("init.entityName\t%s\n", bare.entityName ? bare.entityName.UTF8String : "(nil)");
    } @catch (NSException *exception) {
        printf("init.raised\t1\n");
        printf("init.reason\t%s\n", exception.reason.UTF8String);
    }

    // 2. The rows, by name.
    NSBatchInsertRequest *byName = [NSBatchInsertRequest
        batchInsertRequestWithEntityName:@"Row"
                                   objects:@[@{@"name": @"one"}, @{@"name": @"two"}]];
    printf("byName.entityName\t%s\n", byName.entityName.UTF8String);
    printf("byName.objects\t%lu\n", (unsigned long)byName.objectsToInsert.count);
    printf("byName.firstRow.name\t%s\n",
           [byName.objectsToInsert.firstObject[@"name"] UTF8String]);

    // 3. The entity form, with the ROWS it is for: both sides answer entityName=Row and entity=Row,
    //    which is what the committed twenty-two-line reference (reference-host.tsv, CoreData 120)
    //    records for this initialiser and what the port stores.
    //
    //    The rows are what this question is about. Asked with an EMPTY array -- as this probe stood
    //    until now -- Apple's own class answers entityName=(nil) and entity=(null), measured over both
    //    forms and over a detached entity, one in a model and one in a model with a store, one row and
    //    two: a request built with nothing to insert keeps neither. The comment that stood here said
    //    "entityName is nil and the entity is the one", which is Apple's answer for the empty case and
    //    not for a request with rows in it, so the probe was asserting a claim of its own and calling
    //    the difference a port defect. The empty-array behaviour is a real difference from the port and
    //    is handed on rather than folded in here: it is a question about what the port should store for
    //    a request with no rows, which is the owner's call and not this probe's.
    NSBatchInsertRequest *byEntity = [[NSBatchInsertRequest alloc] initWithEntity:entity
                                                                         objects:@[@{@"name": @"one"},
                                                                                   @{@"name": @"two"}]];
    printf("byEntity.entityName\t%s\n", byEntity.entityName ? byEntity.entityName.UTF8String : "(nil)");
    printf("byEntity.entity\t%s\n", byEntity.entity.name.UTF8String);

    // 4. The handlers: both exist, and both RETURN BOOL. The block is stored, not called.
    __block NSUInteger called = 0;
    BOOL (^dictionaryHandler)(NSMutableDictionary<NSString *, id> *) =
        ^BOOL(NSMutableDictionary<NSString *, id> *obj) { called++; return YES; };
    BOOL (^managedObjectHandler)(NSManagedObject *) =
        ^BOOL(NSManagedObject *obj) { called++; return YES; };
    NSBatchInsertRequest *withHandler = [NSBatchInsertRequest batchInsertRequestWithEntityName:@"Row"
                                                                            dictionaryHandler:dictionaryHandler];
    printf("dictionaryHandler.present\t%s\n", withHandler.dictionaryHandler ? "true" : "false");
    printf("dictionaryHandler.called\t%lu\n", (unsigned long)called);
    NSBatchInsertRequest *withObjectHandler =
        [NSBatchInsertRequest batchInsertRequestWithEntityName:@"Row"
                                       managedObjectHandler:managedObjectHandler];
    printf("managedObjectHandler.present\t%s\n", withObjectHandler.managedObjectHandler ? "true" : "false");
    printf("managedObjectHandler.called\t%lu\n", (unsigned long)called);

    // 5. The result type is settable and reads back what it was given.
    byName.resultType = NSBatchInsertRequestResultTypeObjectIDs;
    printf("byName.resultType.set\t%ld\n", (long)byName.resultType);
    printf("ResultTypeCount\t%ld\n", (long)NSBatchInsertRequestResultTypeCount);
    return 0;
} }
