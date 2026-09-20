#import <CoreData/CoreData.h>

@interface NSBatchDeleteResult (CharonInit)
- (instancetype)initWithResultType:(NSBatchDeleteRequestResultType)resultType andObject:(id)result;
@end

static NSBatchDeleteResult *charon_batch_delete(NSManagedObjectContext *context, NSBatchDeleteRequest *request, NSError **error)
{
    NSFetchRequest *fetch = [request.fetchRequest copy];
    fetch.resultType = NSManagedObjectResultType;
    if (request.affectedStores)
        fetch.affectedStores = request.affectedStores;
    NSManagedObjectContext *worker = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    worker.persistentStoreCoordinator = context.persistentStoreCoordinator;
    __block id outcome = nil;
    __block NSError *failure = nil;
    [worker performBlockAndWait:^{
        NSArray *objects = [worker executeFetchRequest:fetch error:&failure];
        if (!objects)
            return;
        NSMutableArray *identifiers = [NSMutableArray arrayWithCapacity:objects.count];
        for (NSManagedObject *object in objects) {
            [identifiers addObject:object.objectID];
            [worker deleteObject:object];
        }
        if (objects.count && ![worker save:&failure])
            return;
        if (request.resultType == NSBatchDeleteResultTypeObjectIDs)
            outcome = [identifiers copy];
        else if (request.resultType == NSBatchDeleteResultTypeCount)
            outcome = @(identifiers.count);
        else
            outcome = @YES;
    }];
    if (!outcome) {
        if (error)
            *error = failure;
        return nil;
    }
    return [[NSBatchDeleteResult alloc] initWithResultType:request.resultType andObject:outcome];
}

@implementation NSManagedObjectContext (CharonExecuteRequest)

- (id)executeRequest:(NSPersistentStoreRequest *)request error:(NSError **)error
{
    if ([request isKindOfClass:[NSFetchRequest class]])
        return [self executeFetchRequest:(NSFetchRequest *)request error:error];
    if (request.requestType == 7)
        return charon_batch_delete(self, (NSBatchDeleteRequest *)request, error);
    return [self.persistentStoreCoordinator executeRequest:request withContext:self error:error];
}

@end
